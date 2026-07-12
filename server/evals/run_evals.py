# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx>=0.27", "pyyaml>=6"]
# ///
"""Generic-tier eval harness.

Runs the queries in evals/queries.yaml against a running orchestrator
(default localhost:8000) and scores each stream:

  outcome     ok | degraded (fallback surface) | error
  t_caption   seconds until the caption line
  t_final     seconds until the final updateComponents
  components  component mix of the final surface

Usage:
  uv run evals/run_evals.py [--base http://localhost:8000] [--limit N] [--concurrency N]

Results: summary table on stdout + full records in evals/results.jsonl
(overwritten each run). Requires GEMINI_API_KEY on the *server* — degraded
mock answers are counted as degraded.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import time
from collections import Counter
from pathlib import Path

import httpx
import yaml

HERE = Path(__file__).resolve().parent

# Fallback surfaces are recognizable: Markdown text matching the degrade/mock
# strings. Keep in sync with llm.py.
_FALLBACK_MARKERS = ("mock generic answer", "मॉक जवाब", "మాక్ సమాధానం",
                     "couldn't build a visual answer", "विज़ुअल जवाब नहीं बन पाया",
                     "విజువల్ సమాధానం రాలేదు")


async def run_query(client: httpx.AsyncClient, base: str, q: str, lang: str) -> dict:
    record: dict = {"q": q, "lang": lang, "outcome": "error",
                    "t_caption": None, "t_final": None, "components": []}
    t0 = time.monotonic()
    try:
        async with client.stream(
            "POST", f"{base}/v1/query",
            json={"query": q, "lang": lang},
            timeout=90,
        ) as resp:
            if resp.status_code != 200:
                record["error"] = f"http {resp.status_code}"
                return record
            last_components: list[dict] = []
            async for line in resp.aiter_lines():
                if not line.strip():
                    continue
                msg = json.loads(line)
                now = time.monotonic() - t0
                if "nakul" in msg:
                    record["t_caption"] = round(now, 2)
                    record["caption"] = msg["nakul"]["caption"]
                elif "updateComponents" in msg:
                    last_components = msg["updateComponents"]["components"]
                    record["t_final"] = round(now, 2)
            record["components"] = [c["component"] for c in last_components]
            text_blob = json.dumps(last_components, ensure_ascii=False)
            degraded = any(marker in text_blob for marker in _FALLBACK_MARKERS)
            record["outcome"] = "degraded" if degraded else "ok"
    except Exception as e:  # noqa: BLE001 — eval harness records, never raises
        record["error"] = f"{type(e).__name__}: {e}"
    return record


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://localhost:8000")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--concurrency", type=int, default=3)
    args = parser.parse_args()

    queries = yaml.safe_load((HERE / "queries.yaml").read_text())["queries"]
    if args.limit:
        queries = queries[: args.limit]

    sem = asyncio.Semaphore(args.concurrency)
    async with httpx.AsyncClient() as client:
        async def bounded(item):
            async with sem:
                return await run_query(client, args.base, item["q"], item["lang"])

        records = await asyncio.gather(*(bounded(item) for item in queries))

    out = HERE / "results.jsonl"
    out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records))

    outcomes = Counter(r["outcome"] for r in records)
    captions = sorted(r["t_caption"] for r in records if r["t_caption"] is not None)
    finals = sorted(r["t_final"] for r in records if r["t_final"] is not None)
    comp_usage = Counter(c for r in records for c in set(r["components"]))

    def pct(values, p):
        return values[min(len(values) - 1, int(len(values) * p))] if values else None

    print(f"\n{'=' * 56}")
    print(f"queries: {len(records)}   ok: {outcomes['ok']}   "
          f"degraded: {outcomes['degraded']}   error: {outcomes['error']}")
    if finals:
        print(f"t_caption  p50 {pct(captions, .5)}s   p90 {pct(captions, .9)}s")
        print(f"t_final    p50 {pct(finals, .5)}s   p90 {pct(finals, .9)}s")
    print("component usage:",
          ", ".join(f"{name}×{n}" for name, n in comp_usage.most_common()))
    for r in records:
        if r["outcome"] != "ok":
            print(f"  [{r['outcome']}] {r['q'][:60]} — {r.get('error', 'fallback surface')}")
    print(f"full records: {out}")


if __name__ == "__main__":
    asyncio.run(main())
