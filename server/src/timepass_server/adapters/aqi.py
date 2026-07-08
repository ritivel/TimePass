"""Real CPCB AQI adapter via data.gov.in.

Resource 3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69 ("Real time Air Quality Index
from various locations", Ministry of Env/CPCB). One row per station per
pollutant; `avg_value` is the CPCB sub-index (0–500). Overall AQI per station
= max sub-index across its pollutants; the city number we show is the mean of
station AQIs (city-worst is alarmist, a single station is arbitrary).

Requires DATA_GOV_IN_API_KEY; falls back to the fixture in weather.py when
missing or on any upstream error. Cached per city for 10 minutes — CPCB
updates hourly, so marginal cost trends to ~0 (PRODUCT_SPEC §6).
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from datetime import datetime, timezone, timedelta
from typing import Any

import httpx

log = logging.getLogger(__name__)

_RESOURCE = "https://api.data.gov.in/resource/3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69"
_IST = timezone(timedelta(hours=5, minutes=30))
_CACHE_TTL_SECONDS = 600
_cache: dict[str, tuple[float, dict[str, Any]]] = {}

# CPCB categories (breakpoint -> key). categoryText/health advice localized.
_CATEGORIES = [
    (50, "good"),
    (100, "satisfactory"),
    (200, "moderate"),
    (300, "poor"),
    (400, "veryPoor"),
    (500, "severe"),
]

_CATEGORY_TEXT = {
    "good": {"en": "Good", "hi": "अच्छी", "te": "మంచిది"},
    "satisfactory": {"en": "Satisfactory", "hi": "संतोषजनक", "te": "సంతృప్తికరం"},
    "moderate": {"en": "Moderate", "hi": "मध्यम", "te": "మధ్యస్థం"},
    "poor": {"en": "Poor", "hi": "खराब", "te": "పేలవం"},
    "veryPoor": {"en": "Very poor", "hi": "बहुत खराब", "te": "చాలా పేలవం"},
    "severe": {"en": "Severe", "hi": "गंभीर", "te": "తీవ్రం"},
}

_HEALTH_ADVICE = {
    "good": {
        "en": "Air is clean — enjoy the outdoors.",
        "hi": "हवा साफ है — बाहर का आनंद लें।",
        "te": "గాలి శుభ్రంగా ఉంది — బయట ఆనందించండి.",
    },
    "satisfactory": {
        "en": "Fine for most; unusually sensitive people should watch for discomfort.",
        "hi": "अधिकांश के लिए ठीक; अति-संवेदनशील लोग ध्यान रखें।",
        "te": "చాలామందికి ఫర్వాలేదు; అతి సున్నితమైనవారు జాగ్రత్త.",
    },
    "moderate": {
        "en": "Sensitive groups should limit prolonged outdoor exertion.",
        "hi": "संवेदनशील लोग बाहर लंबी मेहनत सीमित करें।",
        "te": "సున్నిత వర్గాలు బయట సుదీర్ఘ శ్రమ తగ్గించాలి.",
    },
    "poor": {
        "en": "Sensitive groups should avoid outdoor exertion; consider a mask outdoors.",
        "hi": "संवेदनशील लोग बाहर मेहनत से बचें; मास्क पहनें।",
        "te": "సున్నిత వర్గాలు బయట శ్రమ మానాలి; మాస్క్ వాడండి.",
    },
    "veryPoor": {
        "en": "Avoid outdoor activity; keep windows closed and use a mask outside.",
        "hi": "बाहरी गतिविधि से बचें; खिड़कियां बंद रखें, बाहर मास्क पहनें।",
        "te": "బయటి కార్యకలాపాలు మానండి; కిటికీలు మూసి ఉంచండి, బయట మాస్క్.",
    },
    "severe": {
        "en": "Stay indoors; avoid all outdoor exertion. Use purifiers if available.",
        "hi": "घर के अंदर रहें; बाहर बिल्कुल न निकलें। हो सके तो प्यूरीफायर चलाएं।",
        "te": "ఇంట్లోనే ఉండండి; బయటికి వెళ్లకండి. వీలైతే ప్యూరిఫైయర్ వాడండి.",
    },
}

_AGO_TEXT = {
    "en": lambda mins: f"{mins} min" if mins < 90 else f"{mins // 60} hr",
    "hi": lambda mins: f"{mins} मिनट" if mins < 90 else f"{mins // 60} घंटे",
    "te": lambda mins: f"{mins} నిమి" if mins < 90 else f"{mins // 60} గం",
}

# Query keyword → data.gov.in city value. Extend as usage data comes in.
_CITY_KEYWORDS: dict[str, str] = {
    "delhi": "Delhi", "दिल्ली": "Delhi", "ఢిల్లీ": "Delhi",
    "mumbai": "Mumbai", "मुंबई": "Mumbai", "ముంబై": "Mumbai",
    "hyderabad": "Hyderabad", "हैदराबाद": "Hyderabad", "హైదరాబాద్": "Hyderabad",
    "bengaluru": "Bengaluru", "bangalore": "Bengaluru", "बेंगलुरु": "Bengaluru", "బెంగళూరు": "Bengaluru",
    "chennai": "Chennai", "चेन्नई": "Chennai", "చెన్నై": "Chennai",
    "kolkata": "Kolkata", "कोलकाता": "Kolkata", "కోల్‌కతా": "Kolkata",
    "pune": "Pune", "पुणे": "Pune", "పుణె": "Pune",
    "ahmedabad": "Ahmedabad", "अहमदाबाद": "Ahmedabad",
    "jaipur": "Jaipur", "जयपुर": "Jaipur",
    "lucknow": "Lucknow", "लखनऊ": "Lucknow",
    "patna": "Patna", "पटना": "Patna",
    "gurugram": "Gurugram", "gurgaon": "Gurugram", "गुरुग्राम": "Gurugram",
    "noida": "Noida", "नोएडा": "Noida",
    "visakhapatnam": "Visakhapatnam", "vizag": "Visakhapatnam", "విశాఖపట్నం": "Visakhapatnam",
    "vijayawada": "Vijayawada", "విజయవాడ": "Vijayawada",
    "warangal": "Warangal", "వరంగల్": "Warangal",
}


def city_from_query(query: str, default: str = "Delhi") -> str:
    q = query.casefold()
    for keyword, city in _CITY_KEYWORDS.items():
        if keyword in q:
            return city
    return default


def category_for(aqi: int) -> str:
    for limit, key in _CATEGORIES:
        if aqi <= limit:
            return key
    return "severe"


def summarize_records(records: list[dict[str, Any]]) -> dict[str, Any] | None:
    """City rollup from station×pollutant rows: station AQI = max sub-index;
    city AQI = mean of station AQIs; dominant pollutant = argmax most often."""
    stations: dict[str, dict[str, int]] = {}
    latest: datetime | None = None
    for row in records:
        try:
            value = int(float(row["avg_value"]))
        except (KeyError, TypeError, ValueError):
            continue  # 'NA' rows
        stations.setdefault(row["station"], {})[row["pollutant_id"]] = value
        try:
            ts = datetime.strptime(row["last_update"], "%d-%m-%Y %H:%M:%S").replace(tzinfo=_IST)
            latest = ts if latest is None or ts > latest else latest
        except (KeyError, ValueError):
            pass

    per_station = {
        name: max(subs.items(), key=lambda kv: kv[1])
        for name, subs in stations.items()
        if subs
    }
    if not per_station:
        return None

    city_aqi = round(sum(v for _, v in per_station.values()) / len(per_station))
    dominant_counts: dict[str, int] = {}
    for pollutant, _ in per_station.values():
        dominant_counts[pollutant] = dominant_counts.get(pollutant, 0) + 1
    dominant = max(dominant_counts, key=dominant_counts.get)  # type: ignore[arg-type]

    minutes_ago = None
    if latest is not None:
        minutes_ago = max(0, int((datetime.now(tz=_IST) - latest).total_seconds() // 60))

    return {
        "aqi": city_aqi,
        "dominant": dominant,
        "stationCount": len(per_station),
        "minutesAgo": minutes_ago,
    }


async def fetch_city_records(city: str) -> list[dict[str, Any]]:
    api_key = os.environ["DATA_GOV_IN_API_KEY"]
    # data.gov.in's WAF tarpits the default python-httpx User-Agent (requests
    # hang to timeout); any explicit UA goes through in ~1s.
    async with httpx.AsyncClient(
        timeout=15,
        headers={"User-Agent": "TimePass/0.1 (aqi-adapter)", "Accept": "application/json"},
    ) as client:
        last_error: Exception | None = None
        for attempt in range(2):  # gov endpoints drop the odd TLS handshake
            try:
                resp = await client.get(
                    _RESOURCE,
                    params={
                        "api-key": api_key,
                        "format": "json",
                        "limit": 500,
                        "filters[city]": city,
                    },
                )
                resp.raise_for_status()
                return resp.json().get("records", [])
            except (httpx.TransportError, httpx.HTTPStatusError) as e:
                last_error = e
                if attempt == 0:
                    await asyncio.sleep(0.5)
        raise last_error  # type: ignore[misc]


async def get_aqi(query: str, lang: str) -> dict[str, Any]:
    """AqiMeter payload from live CPCB data; fixture fallback on any failure."""
    city = city_from_query(query)

    cached = _cache.get(city)
    summary: dict[str, Any] | None = None
    if cached and cached[0] > time.monotonic():
        summary = cached[1]
    elif os.environ.get("DATA_GOV_IN_API_KEY"):
        try:
            records = await fetch_city_records(city)
            summary = summarize_records(records)
            if summary is not None:
                _cache[city] = (time.monotonic() + _CACHE_TTL_SECONDS, summary)
        except Exception:
            log.exception("CPCB AQI fetch failed for %s, falling back to fixture", city)

    if summary is None:
        from . import weather

        return await weather.get_aqi_fixture(query, lang, city)

    category = category_for(summary["aqi"])
    mins = summary["minutesAgo"]
    return {
        "locationName": city,
        "aqi": summary["aqi"],
        "category": category,
        "categoryText": _CATEGORY_TEXT[category][lang],
        "dominantPollutant": summary["dominant"],
        "stationName": f"{summary['stationCount']} CPCB stations",
        "updatedAtText": _AGO_TEXT[lang](mins) if mins is not None else "—",
        "healthAdviceText": _HEALTH_ADVICE[category][lang],
    }
