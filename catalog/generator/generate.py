# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml>=6"]
# ///
"""Catalog generator — the single source of truth pipeline.

Reads catalog/catalog.yaml and emits:
  catalog/dist/catalog.json        A2UI-style catalog schema (server validator + reference)
  catalog/dist/system_prompt.md    model-facing prompt fragment (composition rules + component docs)
  app/lib/catalog/schemas.g.dart   Dart schema maps for genui CatalogItem registration

Never edit the outputs by hand. Run: uv run catalog/generator/generate.py

Note on A2UI alignment: dynamic props are emitted as an inlined
`oneOf [literal, {path} binding]` instead of `$ref`s to the spec's
common_types.json, because catalogs may not carry custom $defs and we keep
dist/ self-contained. Revisit when migrating to protocol v1.0.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "catalog" / "catalog.yaml"
DIST = ROOT / "catalog" / "dist"
DART_OUT = ROOT / "app" / "lib" / "catalog" / "schemas.g.dart"

SCALARS = {"string": "string", "number": "number", "integer": "integer", "boolean": "boolean"}

ACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "event": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "context": {"type": "object"},
            },
            "required": ["name"],
            "additionalProperties": False,
        }
    },
    "required": ["event"],
    "additionalProperties": False,
}

PATH_BINDING = {
    "type": "object",
    "properties": {"path": {"type": "string", "pattern": "^/"}},
    "required": ["path"],
    "additionalProperties": False,
}


def scalar_schema(spec: dict) -> dict:
    schema: dict = {"type": SCALARS[spec["type"]]}
    if "enum" in spec:
        schema["enum"] = list(spec["enum"])
    if "default" in spec:
        schema["default"] = spec["default"]
    if spec.get("description"):
        schema["description"] = str(spec["description"]).strip()
    # dynamic (default true for scalars): literal OR {path} binding
    if spec.get("dynamic", True):
        wrapped = {"oneOf": [schema, PATH_BINDING]}
        if "description" in schema:
            wrapped["description"] = schema.pop("description")
        return wrapped
    return schema


def prop_schema(spec: dict) -> dict:
    t = spec["type"]
    if t in SCALARS:
        return scalar_schema(spec)
    if t == "children":
        schema = {
            "type": "array",
            "items": {"type": "string"},
            "description": "Ids of child components (adjacency list).",
        }
        if "maxItems" in spec:
            schema["maxItems"] = spec["maxItems"]
        return schema
    if t == "childId":
        return {"type": "string", "description": "Id of the single child component."}
    if t == "action":
        return ACTION_SCHEMA
    if t == "object":
        schema = object_schema(spec["fields"], spec.get("description"))
    elif t == "array":
        item_spec = spec["items"]
        items = (
            object_schema(item_spec["fields"])
            if "fields" in item_spec
            else scalar_schema(item_spec)
        )
        schema = {"type": "array", "items": items}
        for k in ("minItems", "maxItems"):
            if k in spec:
                schema[k] = spec[k]
        if spec.get("description"):
            schema["description"] = str(spec["description"]).strip()
    else:
        raise ValueError(f"unknown prop type: {t}")
    # objects/arrays are bindable too (hero payloads live in the data model)
    if spec.get("dynamic", True):
        return {"oneOf": [schema, PATH_BINDING]}
    return schema


def object_schema(fields: dict, description: str | None = None) -> dict:
    schema: dict = {
        "type": "object",
        "properties": {name: prop_schema(spec) for name, spec in fields.items()},
        "additionalProperties": False,
    }
    required = [name for name, spec in fields.items() if spec.get("required")]
    if required:
        schema["required"] = required
    if description:
        schema["description"] = str(description).strip()
    return schema


def component_schema(name: str, comp: dict) -> dict:
    props: dict = {
        "id": {"type": "string"},
        "component": {"const": name},
    }
    for pname, pspec in (comp.get("props") or {}).items():
        props[pname] = prop_schema(pspec)
    required = ["id", "component"] + [
        p for p, s in (comp.get("props") or {}).items() if s.get("required")
    ]
    return {
        "type": "object",
        "description": str(comp.get("description", "")).strip(),
        "properties": props,
        "required": required,
        "additionalProperties": False,
    }


def build_catalog(src: dict) -> dict:
    components = {
        name: component_schema(name, comp) for name, comp in src["components"].items()
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "catalogId": src["catalogId"],
        "protocol": src["protocol"],
        "instructions": src["instructions"].strip(),
        "components": components,
    }


def prop_signature(name: str, spec: dict, indent: str = "  ") -> list[str]:
    """Human/LLM-readable one-liner(s) for a prop."""
    t = spec["type"]
    req = "" if spec.get("required") else "?"
    if t in SCALARS:
        detail = f"enum[{', '.join(map(str, spec['enum']))}]" if "enum" in spec else t
    elif t == "children":
        detail = "array of component ids"
    elif t == "childId":
        detail = "component id"
    elif t == "action":
        detail = "{event: {name, context}}"
    elif t == "object":
        inner = ", ".join(
            f"{n}{'' if s.get('required') else '?'}" for n, s in spec["fields"].items()
        )
        detail = f"{{{inner}}}"
    elif t == "array":
        item = spec["items"]
        if "fields" in item:
            inner = ", ".join(
                f"{n}{'' if s.get('required') else '?'}" for n, s in item["fields"].items()
            )
            detail = f"array of {{{inner}}}"
        else:
            detail = f"array of {item['type']}"
        bounds = []
        if "minItems" in spec:
            bounds.append(str(spec["minItems"]))
        if "maxItems" in spec:
            bounds.append(str(spec["maxItems"]))
        if bounds:
            detail += f" [{'-'.join(bounds)}]"
    else:
        detail = t
    line = f"{indent}- {name}{req}: {detail}"
    if spec.get("description"):
        line += f" — {str(spec['description']).strip()}"
    return [line]


def build_prompt(src: dict) -> str:
    lines = [
        "## UI catalog",
        "",
        f"Catalog id: {src['catalogId']} (A2UI {src['protocol']}, flat adjacency list;",
        'every component instance is {"id", "component", ...props}; string/number props',
        'accept either a literal or a {"path": "/data/model/path"} binding).',
        "",
        src["instructions"].strip(),
        "",
        "### Components",
        "",
    ]
    for name, comp in src["components"].items():
        desc = " ".join(str(comp.get("description", "")).split())
        lines.append(f"**{name}** — {desc}")
        props = comp.get("props") or {}
        if not props:
            lines.append("  (no props)")
        for pname, pspec in props.items():
            lines.extend(prop_signature(pname, pspec))
        for ev, payload in (comp.get("events") or {}).items():
            lines.append(f"  event: {ev} {json.dumps(payload)}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def dart_literal(value, indent: int = 0) -> str:
    pad, pad_in = "  " * indent, "  " * (indent + 1)
    if isinstance(value, dict):
        if not value:
            return "<String, Object?>{}"
        entries = [
            f"{pad_in}{dart_literal(str(k))}: {dart_literal(v, indent + 1)},"
            for k, v in value.items()
        ]
        return "<String, Object?>{\n" + "\n".join(entries) + f"\n{pad}}}"
    if isinstance(value, list):
        if not value:
            return "<Object?>[]"
        entries = [f"{pad_in}{dart_literal(v, indent + 1)}," for v in value]
        return "<Object?>[\n" + "\n".join(entries) + f"\n{pad}]"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        escaped = value.replace("\\", r"\\").replace("'", r"\'").replace("$", r"\$").replace("\n", r"\n")
        return f"'{escaped}'"
    if value is None:
        return "null"
    return repr(value)


def _dart_component_schema(schema: dict) -> dict:
    """genui's CatalogItem injects the `component` discriminator itself and
    tracks `id` at the Component level, so the Dart dataSchema must carry
    only the component-specific props."""
    out = dict(schema)
    out["properties"] = {
        k: v for k, v in schema["properties"].items() if k not in ("id", "component")
    }
    out["required"] = [r for r in schema.get("required", []) if r not in ("id", "component")]
    out.pop("additionalProperties", None)
    return out


def build_dart(src: dict, catalog: dict) -> str:
    custom = {
        name: _dart_component_schema(schema)
        for name, schema in catalog["components"].items()
        if not src["components"][name].get("adopted")
    }
    header = (
        "// GENERATED by catalog/generator/generate.py — DO NOT EDIT.\n"
        "// Source: catalog/catalog.yaml\n"
        "//\n"
        "// JSON Schemas for TimePass custom components, keyed by component name.\n"
        "// Adopted Basic Catalog primitives are provided by package:genui and are\n"
        "// intentionally absent here.\n\n"
        f"const String catalogId = {dart_literal(catalog['catalogId'])};\n\n"
    )
    body = "const Map<String, Map<String, Object?>> componentSchemas = {\n"
    for name, schema in custom.items():
        body += f"  '{name}': {dart_literal(schema, 1)},\n"
    body += "};\n"
    return header + body


def main() -> int:
    src = yaml.safe_load(SRC.read_text())
    catalog = build_catalog(src)

    DIST.mkdir(parents=True, exist_ok=True)
    (DIST / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    (DIST / "system_prompt.md").write_text(build_prompt(src))
    DART_OUT.parent.mkdir(parents=True, exist_ok=True)
    DART_OUT.write_text(build_dart(src, catalog))

    n_total = len(catalog["components"])
    n_custom = sum(1 for c in src["components"].values() if not c.get("adopted"))
    print(f"catalog.json        {n_total} components ({n_custom} custom) -> {DIST / 'catalog.json'}")
    print(f"system_prompt.md    {len(build_prompt(src).split())} words -> {DIST / 'system_prompt.md'}")
    print(f"schemas.g.dart      {n_custom} schemas -> {DART_OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
