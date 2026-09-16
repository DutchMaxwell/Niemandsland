"""The replay pin forwards a record's `mission` stamp (Gen-8 export regression).

`gen0_replay_one.replay_knobs` merges only the keys `KNOBS` pins. `mission` was
not pinned, so a seize_ground / domination / ... record replayed as a duel: the
Gen-8 export (16.09.2026) lost 3,502 of 4,350 games at seq 0 ("menu width").
RED on main before the pin: `merged["mission"]` is absent. A record silent on the
key (every duel, the recorder stamps it only when != "duel") still replays a duel.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import gen0_replay_one as gr  # noqa: E402


def test_a_stamped_mission_is_forwarded_to_the_replay():
    kn = {"mission": "seize_ground", "objectives": "mission"}
    merged = gr.replay_knobs(kn, {"knobs": kn}, {"knobs": kn})
    assert merged.get("mission") == "seize_ground"
    assert merged["objectives"] == "mission"


def test_a_record_silent_on_mission_still_replays_a_duel():
    merged = gr.replay_knobs({}, {}, {})
    assert merged.get("mission") == "duel"
