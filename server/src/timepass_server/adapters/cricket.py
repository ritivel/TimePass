"""Cricket data adapter.

M0: fixture-backed. Real integration (EntitySport or Roanuz, PRODUCT_SPEC §4)
plugs in behind the same payload shape, which mirrors the CricketLiveScore
props contract. The mandatory display lag (legal posture, PRODUCT_SPEC §4) is
applied here, not in the client.
"""

from __future__ import annotations

import os
from typing import Any

LAG_SECONDS = int(os.environ.get("CRICKET_LAG_SECONDS", "300"))

_FIXTURE: dict[str, Any] = {
    "matchId": "fixture_ind_aus_t20_3",
    "matchTitle": "IND vs AUS · 3rd T20I",
    "statusText": {
        "en": "IND need 43 off 30 balls",
        "hi": "IND को 30 गेंदों पर 43 रन चाहिए",
        "te": "IND కు 30 బంతుల్లో 43 పరుగులు కావాలి",
    },
    "teams": [
        {"name": "India", "shortName": "IND", "scoreText": "159/4", "oversText": "15.0"},
        {"name": "Australia", "shortName": "AUS", "scoreText": "201/7", "oversText": "20.0"},
    ],
    "batters": [
        {"name": "Kohli", "runsText": "52*", "ballsText": "31", "onStrike": True},
        {"name": "Rahul", "runsText": "12", "ballsText": "8", "onStrike": False},
    ],
    "bowler": {"name": "Starc", "figuresText": "2/34", "oversText": "3.2"},
    "recentBalls": ["4", "1", "W", "6", "2", "0"],
    "updatedAtText": {"en": "15s ago", "hi": "15 सेकंड पहले", "te": "15 సెకన్ల క్రితం"},
}


async def get_live_match(query: str, lang: str) -> dict[str, Any]:
    """Returns the CricketLiveScore payload for the data model."""
    data = dict(_FIXTURE)
    data["statusText"] = data["statusText"][lang]
    data["updatedAtText"] = data["updatedAtText"][lang]
    data["lagSeconds"] = LAG_SECONDS
    return data
