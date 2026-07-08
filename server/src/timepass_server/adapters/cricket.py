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

# A short looping ball-by-ball sequence so the live-refresh loop produces
# visible updates against fixtures. The real feed replaces `_snapshots()`.
_BASE: dict[str, Any] = {
    "matchId": "fixture_ind_aus_t20_3",
    "matchTitle": "IND vs AUS · 3rd T20I",
    "teams": [
        {"name": "India", "shortName": "IND", "scoreText": "159/4", "oversText": "15.0"},
        {"name": "Australia", "shortName": "AUS", "scoreText": "201/7", "oversText": "20.0"},
    ],
    "bowler": {"name": "Starc", "figuresText": "2/34", "oversText": "3.2"},
}

_SNAPSHOTS: list[dict[str, Any]] = [
    {
        "ind": ("159/4", "15.0"),
        "status": {"en": "IND need 43 off 30 balls", "hi": "IND को 30 गेंदों पर 43 रन चाहिए",
                   "te": "IND కు 30 బంతుల్లో 43 పరుగులు కావాలి"},
        "batters": [{"name": "Kohli", "runsText": "52*", "ballsText": "31", "onStrike": True},
                    {"name": "Rahul", "runsText": "12", "ballsText": "8", "onStrike": False}],
        "recentBalls": ["4", "1", "W", "6", "2", "0"],
    },
    {
        "ind": ("165/4", "15.3"),
        "status": {"en": "IND need 37 off 27 balls", "hi": "IND को 27 गेंदों पर 37 रन चाहिए",
                   "te": "IND కు 27 బంతుల్లో 37 పరుగులు కావాలి"},
        "batters": [{"name": "Kohli", "runsText": "57*", "ballsText": "34", "onStrike": False},
                    {"name": "Rahul", "runsText": "13", "ballsText": "9", "onStrike": True}],
        "recentBalls": ["1", "W", "6", "2", "0", "4"],
    },
    {
        "ind": ("171/4", "16.0"),
        "status": {"en": "IND need 31 off 24 balls", "hi": "IND को 24 गेंदों पर 31 रन चाहिए",
                   "te": "IND కు 24 బంతుల్లో 31 పరుగులు కావాలి"},
        "batters": [{"name": "Kohli", "runsText": "61*", "ballsText": "37", "onStrike": True},
                    {"name": "Rahul", "runsText": "15", "ballsText": "11", "onStrike": False}],
        "recentBalls": ["6", "2", "0", "4", "1", "1"],
    },
    {
        "ind": ("180/4", "16.4"),
        "status": {"en": "IND need 22 off 20 balls", "hi": "IND को 20 गेंदों पर 22 रन चाहिए",
                   "te": "IND కు 20 బంతుల్లో 22 పరుగులు కావాలి"},
        "batters": [{"name": "Kohli", "runsText": "68*", "ballsText": "40", "onStrike": True},
                    {"name": "Rahul", "runsText": "17", "ballsText": "13", "onStrike": False}],
        "recentBalls": ["2", "0", "4", "1", "1", "6"],
    },
]

_UPDATED = {"en": "just now", "hi": "अभी-अभी", "te": "ఇప్పుడే"}

_tick = 0


async def get_live_match(query: str, lang: str) -> dict[str, Any]:
    """Returns the CricketLiveScore payload for the data model.

    Each call advances the fixture one snapshot so live refreshes visibly
    update the card.
    """
    global _tick
    snap = _SNAPSHOTS[_tick % len(_SNAPSHOTS)]
    _tick += 1

    data = dict(_BASE)
    score, overs = snap["ind"]
    data["teams"] = [
        {**_BASE["teams"][0], "scoreText": score, "oversText": overs},
        _BASE["teams"][1],
    ]
    data["statusText"] = snap["status"][lang]
    data["batters"] = snap["batters"]
    data["recentBalls"] = snap["recentBalls"]
    data["updatedAtText"] = _UPDATED[lang]
    data["lagSeconds"] = LAG_SECONDS
    return data
