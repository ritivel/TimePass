"""Weather + AQI adapter.

M0: fixture-backed. Real integrations: IMD API platform (forecast/nowcast/
warnings) and CPCB real-time AQI via data.gov.in (PRODUCT_SPEC §4) — both
effectively free. aqicn.org is banned for paid apps; do not use it.
"""

from __future__ import annotations

from typing import Any

_WEATHER: dict[str, dict[str, Any]] = {
    "en": {
        "current": {
            "tempText": "29°",
            "condition": "thunderstorm",
            "conditionText": "Heavy rain, thunderstorms",
            "feelsLikeText": "feels like 33°",
            "humidityText": "82%",
            "windText": "14 km/h",
        },
        "days": [
            {"dayLabel": "Wed", "minText": "26°", "maxText": "29°", "condition": "thunderstorm", "rainPctText": "90%"},
            {"dayLabel": "Thu", "minText": "25°", "maxText": "28°", "condition": "rain", "rainPctText": "70%"},
            {"dayLabel": "Fri", "minText": "26°", "maxText": "30°", "condition": "partlyCloudy", "rainPctText": "30%"},
            {"dayLabel": "Sat", "minText": "27°", "maxText": "32°", "condition": "clear"},
            {"dayLabel": "Sun", "minText": "27°", "maxText": "33°", "condition": "clear"},
        ],
        "alerts": [{"severity": "warning", "text": "IMD orange alert: heavy rainfall expected today"}],
    },
    "hi": {
        "current": {
            "tempText": "29°",
            "condition": "thunderstorm",
            "conditionText": "भारी बारिश, आंधी-तूफ़ान",
            "feelsLikeText": "महसूस 33°",
            "humidityText": "82%",
            "windText": "14 km/h",
        },
        "days": [
            {"dayLabel": "बुध", "minText": "26°", "maxText": "29°", "condition": "thunderstorm", "rainPctText": "90%"},
            {"dayLabel": "गुरु", "minText": "25°", "maxText": "28°", "condition": "rain", "rainPctText": "70%"},
            {"dayLabel": "शुक्र", "minText": "26°", "maxText": "30°", "condition": "partlyCloudy", "rainPctText": "30%"},
            {"dayLabel": "शनि", "minText": "27°", "maxText": "32°", "condition": "clear"},
            {"dayLabel": "रवि", "minText": "27°", "maxText": "33°", "condition": "clear"},
        ],
        "alerts": [{"severity": "warning", "text": "IMD ऑरेंज अलर्ट: आज भारी बारिश की संभावना"}],
    },
    "te": {
        "current": {
            "tempText": "29°",
            "condition": "thunderstorm",
            "conditionText": "భారీ వర్షం, ఉరుములతో కూడిన వాన",
            "feelsLikeText": "అనుభూతి 33°",
            "humidityText": "82%",
            "windText": "14 km/h",
        },
        "days": [
            {"dayLabel": "బుధ", "minText": "26°", "maxText": "29°", "condition": "thunderstorm", "rainPctText": "90%"},
            {"dayLabel": "గురు", "minText": "25°", "maxText": "28°", "condition": "rain", "rainPctText": "70%"},
            {"dayLabel": "శుక్ర", "minText": "26°", "maxText": "30°", "condition": "partlyCloudy", "rainPctText": "30%"},
            {"dayLabel": "శని", "minText": "27°", "maxText": "32°", "condition": "clear"},
            {"dayLabel": "ఆది", "minText": "27°", "maxText": "33°", "condition": "clear"},
        ],
        "alerts": [{"severity": "warning", "text": "IMD ఆరెంజ్ అలర్ట్: నేడు భారీ వర్షాలు"}],
    },
}

_AQI: dict[str, dict[str, Any]] = {
    "en": {"categoryText": "Poor", "healthAdviceText": "Sensitive groups should avoid outdoor exertion; consider a mask outdoors."},
    "hi": {"categoryText": "खराब", "healthAdviceText": "संवेदनशील लोग बाहर मेहनत से बचें; बाहर मास्क पहनें।"},
    "te": {"categoryText": "పేలవం", "healthAdviceText": "సున్నిత వర్గాలు బయట శ్రమ తగ్గించాలి; బయట మాస్క్ వాడండి."},
}


async def get_weather(query: str, lang: str, city: str = "Hyderabad") -> dict[str, Any]:
    """Returns the WeatherStrip payload for the data model."""
    data = dict(_WEATHER[lang])
    data["locationName"] = city
    return data


async def get_aqi(query: str, lang: str, city: str = "Delhi") -> dict[str, Any]:
    """Returns the AqiMeter payload for the data model (CPCB scale)."""
    loc = dict(_AQI[lang])
    return {
        "locationName": f"Anand Vihar, {city}" if city == "Delhi" else city,
        "aqi": 287,
        "category": "poor",
        "categoryText": loc["categoryText"],
        "dominantPollutant": "PM2.5",
        "stationName": "Anand Vihar",
        "updatedAtText": "20 min",
        "healthAdviceText": loc["healthAdviceText"],
    }
