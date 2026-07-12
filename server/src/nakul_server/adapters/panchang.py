"""Panchang data adapter.

M0: fixture-backed. Real integration (Prokerala / VedicAstroAPI, PRODUCT_SPEC §4)
is cacheable per city+date, so marginal cost trends to ~0. All times are
pre-formatted and localized here — the model never formats panchang timings.
"""

from __future__ import annotations

from typing import Any

_FIXTURE: dict[str, dict[str, Any]] = {
    "en": {
        "dateText": "Tuesday, 8 July · Ashadha Shukla Chaturdashi",
        "tithi": {"name": "Chaturdashi", "endsAtText": "until 9:32 PM"},
        "nakshatra": {"name": "Mula", "endsAtText": "until 7:14 PM"},
        "yoga": {"name": "Shubha"},
        "karana": {"name": "Vanija"},
        "sunriseText": "5:48 AM",
        "sunsetText": "6:52 PM",
        "rahuKalam": {"startText": "3:30 PM", "endText": "5:00 PM"},
        "festivals": ["Guru Purnima (tomorrow)"],
    },
    "hi": {
        "dateText": "मंगलवार, 8 जुलाई · आषाढ़ शुक्ल चतुर्दशी",
        "tithi": {"name": "चतुर्दशी", "endsAtText": "रात 9:32 तक"},
        "nakshatra": {"name": "मूल", "endsAtText": "शाम 7:14 तक"},
        "yoga": {"name": "शुभ"},
        "karana": {"name": "वणिज"},
        "sunriseText": "5:48 AM",
        "sunsetText": "6:52 PM",
        "rahuKalam": {"startText": "3:30 PM", "endText": "5:00 PM"},
        "festivals": ["गुरु पूर्णिमा (कल)"],
    },
    "te": {
        "dateText": "మంగళవారం, 8 జులై · ఆషాఢ శుక్ల చతుర్దశి",
        "tithi": {"name": "చతుర్దశి", "endsAtText": "రాత్రి 9:32 వరకు"},
        "nakshatra": {"name": "మూల", "endsAtText": "సాయంత్రం 7:14 వరకు"},
        "yoga": {"name": "శుభ"},
        "karana": {"name": "వణిజ"},
        "sunriseText": "5:48 AM",
        "sunsetText": "6:52 PM",
        "rahuKalam": {"startText": "3:30 PM", "endText": "5:00 PM"},
        "festivals": ["గురు పూర్ణిమ (రేపు)"],
    },
}


async def get_daily_panchang(query: str, lang: str, city: str = "Hyderabad") -> dict[str, Any]:
    """Returns the PanchangCard payload for the data model."""
    data = dict(_FIXTURE[lang])
    data["locationName"] = city
    return data
