"""Deterministic hero-surface builders.

Hero answers don't need the LLM for structure (COMPONENT_CATALOG.md §3.1):
a fixed template binds component props to adapter data in the surface data
model. The LLM is only in the loop for the generic tier and, later, for
choosing between templates.

Each builder returns (caption, components, data_model).
"""

from __future__ import annotations

from typing import Any

Lang = str  # "en" | "hi" | "te"


def _chips(suggestions: list[dict[str, str]]) -> dict[str, Any]:
    return {"id": "chips", "component": "FollowUpChips", "suggestions": suggestions}


def _bind(path: str) -> dict[str, str]:
    return {"path": path}


# ── cricket ────────────────────────────────────────────────────────────────

_CRICKET_LAG_NOTICE = {
    "en": "Scores are delayed by about 5 minutes.",
    "hi": "स्कोर लगभग 5 मिनट की देरी से दिखते हैं।",
    "te": "స్కోర్లు సుమారు 5 నిమిషాల ఆలస్యంతో కనిపిస్తాయి.",
}
_CRICKET_CHIPS = {
    "en": [
        {"label": "Full scorecard", "query": "full scorecard IND vs AUS"},
        {"label": "Points table", "query": "series points table"},
        {"label": "Next match?", "query": "when is the next IND match"},
    ],
    "hi": [
        {"label": "पूरा स्कोरकार्ड", "query": "IND vs AUS पूरा स्कोरकार्ड"},
        {"label": "पॉइंट्स टेबल", "query": "सीरीज़ पॉइंट्स टेबल"},
        {"label": "अगला मैच?", "query": "IND का अगला मैच कब है"},
    ],
    "te": [
        {"label": "పూర్తి స్కోర్‌కార్డ్", "query": "IND vs AUS పూర్తి స్కోర్‌కార్డ్"},
        {"label": "పాయింట్ల పట్టిక", "query": "సిరీస్ పాయింట్ల పట్టిక"},
        {"label": "తదుపరి మ్యాచ్?", "query": "IND తదుపరి మ్యాచ్ ఎప్పుడు"},
    ],
}
_CRICKET_CAPTION = {
    "en": "India need 43 off 30 — Kohli is batting on 52.",
    "hi": "इंडिया को 30 गेंदों पर 43 चाहिए — कोहली 52 पर खेल रहे हैं।",
    "te": "ఇండియాకు 30 బంతుల్లో 43 కావాలి — కోహ్లీ 52పై ఆడుతున్నారు.",
}


def cricket_surface(data: dict[str, Any], lang: Lang):
    components = [
        {"id": "root", "component": "Column", "children": ["lag_notice", "score", "chips"]},
        {
            "id": "lag_notice",
            "component": "Notice",
            "variant": "legal",
            "text": _CRICKET_LAG_NOTICE[lang],
            "dense": True,
        },
        {
            "id": "score",
            "component": "CricketLiveScore",
            "matchId": data["matchId"],
            "matchTitle": _bind("/cricket/matchTitle"),
            "statusText": _bind("/cricket/statusText"),
            "teams": _bind("/cricket/teams"),
            "batters": _bind("/cricket/batters"),
            "bowler": _bind("/cricket/bowler"),
            "recentBalls": _bind("/cricket/recentBalls"),
            "lagSeconds": _bind("/cricket/lagSeconds"),
            "updatedAtText": _bind("/cricket/updatedAtText"),
        },
        _chips(_CRICKET_CHIPS[lang]),
    ]
    return _CRICKET_CAPTION[lang], components, {"cricket": data}


# ── panchang ───────────────────────────────────────────────────────────────

_PANCHANG_CHIPS = {
    "en": [
        {"label": "Rahu kalam tomorrow", "query": "rahu kalam tomorrow"},
        {"label": "This week's festivals", "query": "festivals this week"},
    ],
    "hi": [
        {"label": "कल का राहुकाल", "query": "कल का राहुकाल"},
        {"label": "इस हफ्ते के त्योहार", "query": "इस हफ्ते के त्योहार"},
    ],
    "te": [
        {"label": "రేపటి రాహుకాలం", "query": "రేపటి రాహుకాలం"},
        {"label": "ఈ వారం పండుగలు", "query": "ఈ వారం పండుగలు"},
    ],
}
_PANCHANG_CAPTION = {
    "en": "Today is Chaturdashi; rahu kalam is 3:30 to 5 PM.",
    "hi": "आज चतुर्दशी है; राहुकाल 3:30 से 5 बजे तक है।",
    "te": "నేడు చతుర్దశి; రాహుకాలం 3:30 నుండి 5 వరకు.",
}


def panchang_surface(data: dict[str, Any], lang: Lang):
    components = [
        {"id": "root", "component": "Column", "children": ["panchang", "chips"]},
        {
            "id": "panchang",
            "component": "PanchangCard",
            "dateText": _bind("/panchang/dateText"),
            "locationName": _bind("/panchang/locationName"),
            "tithi": _bind("/panchang/tithi"),
            "nakshatra": _bind("/panchang/nakshatra"),
            "yoga": _bind("/panchang/yoga"),
            "karana": _bind("/panchang/karana"),
            "sunriseText": _bind("/panchang/sunriseText"),
            "sunsetText": _bind("/panchang/sunsetText"),
            "rahuKalam": _bind("/panchang/rahuKalam"),
            "festivals": _bind("/panchang/festivals"),
            "variant": "full",
        },
        _chips(_PANCHANG_CHIPS[lang]),
    ]
    return _PANCHANG_CAPTION[lang], components, {"panchang": data}


# ── weather / aqi ──────────────────────────────────────────────────────────

_WEATHER_CHIPS = {
    "en": [
        {"label": "Hourly today", "query": "hourly weather today"},
        {"label": "AQI here", "query": "air quality here"},
        {"label": "Weekend?", "query": "weather this weekend"},
    ],
    "hi": [
        {"label": "आज घंटेवार", "query": "आज घंटेवार मौसम"},
        {"label": "यहां AQI", "query": "यहां की वायु गुणवत्ता"},
        {"label": "वीकेंड?", "query": "इस वीकेंड का मौसम"},
    ],
    "te": [
        {"label": "నేటి గంటవారీ", "query": "నేటి గంటవారీ వాతావరణం"},
        {"label": "ఇక్కడ AQI", "query": "ఇక్కడి గాలి నాణ్యత"},
        {"label": "వీకెండ్?", "query": "ఈ వీకెండ్ వాతావరణం"},
    ],
}
_WEATHER_CAPTION = {
    "en": "Heavy rain in Hyderabad today, 29 degrees — orange alert is out.",
    "hi": "हैदराबाद में आज भारी बारिश, 29 डिग्री — ऑरेंज अलर्ट जारी है।",
    "te": "హైదరాబాద్‌లో నేడు భారీ వర్షం, 29 డిగ్రీలు — ఆరెంజ్ అలర్ట్ ఉంది.",
}


def weather_surface(data: dict[str, Any], lang: Lang):
    components = [
        {"id": "root", "component": "Column", "children": ["weather", "chips"]},
        {
            "id": "weather",
            "component": "WeatherStrip",
            "locationName": _bind("/weather/locationName"),
            "current": _bind("/weather/current"),
            "days": _bind("/weather/days"),
            "alerts": _bind("/weather/alerts"),
        },
        _chips(_WEATHER_CHIPS[lang]),
    ]
    return _WEATHER_CAPTION[lang], components, {"weather": data}


_AQI_CHIPS = {
    "en": [
        {"label": "Best time to go out", "query": "when is AQI lowest today"},
        {"label": "Weather", "query": "weather today"},
    ],
    "hi": [
        {"label": "बाहर कब जाएं", "query": "आज AQI कब सबसे कम होगा"},
        {"label": "मौसम", "query": "आज का मौसम"},
    ],
    "te": [
        {"label": "బయటికెళ్లే సమయం", "query": "నేడు AQI ఎప్పుడు తక్కువ"},
        {"label": "వాతావరణం", "query": "నేటి వాతావరణం"},
    ],
}
_AQI_CAPTION = {
    "en": "Air quality is poor at 287 — better to mask up outdoors.",
    "hi": "वायु गुणवत्ता खराब है, 287 — बाहर मास्क पहनना बेहतर है।",
    "te": "గాలి నాణ్యత పేలవం, 287 — బయట మాస్క్ మంచిది.",
}


def aqi_surface(data: dict[str, Any], lang: Lang):
    components = [
        {"id": "root", "component": "Column", "children": ["aqi", "chips"]},
        {
            "id": "aqi",
            "component": "AqiMeter",
            "locationName": _bind("/aqi/locationName"),
            "aqi": _bind("/aqi/aqi"),
            "category": _bind("/aqi/category"),
            "categoryText": _bind("/aqi/categoryText"),
            "dominantPollutant": _bind("/aqi/dominantPollutant"),
            "stationName": _bind("/aqi/stationName"),
            "updatedAtText": _bind("/aqi/updatedAtText"),
            "healthAdviceText": _bind("/aqi/healthAdviceText"),
        },
        _chips(_AQI_CHIPS[lang]),
    ]
    return _AQI_CAPTION[lang], components, {"aqi": data}
