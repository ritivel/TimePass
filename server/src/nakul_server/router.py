"""Intent routing, M0 edition: keyword match across en/hi/te (any script).

This is a deliberate stub. M1 replaces it with a proper language-ID +
normalization + intent pipeline (PRODUCT_SPEC §5); the interface — a query
string in, a category out — stays.
"""

from __future__ import annotations

import re
from enum import Enum


class Category(str, Enum):
    CRICKET = "cricket"
    PANCHANG = "panchang"
    WEATHER = "weather"
    AQI = "aqi"
    GENERIC = "generic"


_KEYWORDS: dict[Category, list[str]] = {
    # AQI before weather: "air quality" queries often also say a city + weather-ish words
    Category.AQI: [
        "aqi", "air quality", "pollution", "smog",
        "प्रदूषण", "वायु गुणवत्ता", "కాలుష్యం", "గాలి నాణ్యత",
    ],
    # NOTE: no bare " vs " — it hijacks generic comparisons ("mutual funds vs FD")
    Category.CRICKET: [
        "cricket", "score", "match", "ipl", "t20", "odi", "wicket",
        "क्रिकेट", "स्कोर", "मैच", "క్రికెట్", "స్కోరు", "మ్యాచ్",
    ],
    Category.PANCHANG: [
        "panchang", "tithi", "muhurat", "muhurtham", "rahu", "nakshatra", "ekadashi", "purnima", "amavasya",
        "पंचांग", "तिथि", "मुहूर्त", "राहुकाल", "नक्षत्र",
        "పంచాంగం", "తిథి", "ముహూర్తం", "రాహుకాలం", "నక్షత్రం",
    ],
    Category.WEATHER: [
        "weather", "rain", "temperature", "forecast", "mausam", "baarish", "barish", "humidity",
        "मौसम", "बारिश", "तापमान",
        "వాతావరణం", "వర్షం", "ఉష్ణోగ్రత",
    ],
}


def route(query: str) -> Category:
    q = f" {query.casefold()} "
    q = re.sub(r"\s+", " ", q)
    for category, words in _KEYWORDS.items():
        if any(w in q for w in words):
            return category
    return Category.GENERIC
