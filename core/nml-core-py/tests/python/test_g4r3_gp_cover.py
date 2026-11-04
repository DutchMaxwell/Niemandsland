"""AI-G4 round 3, row F-GP-COVER (rules epoch 73) - the cover flag of EVERY moving member is set at the landing.

THE BUNDLED GAME. `fixtures/g4r3_gp_cover/gf_1000_net_035` is the recorded Saurian Starhosts v Soul Snatcher Cults game
(GF 1000 pt, NET arm, seed 36296), trimmed to the header, act 4 (state + pick only), `auto` placeholders for the ordinals
before it, every roll of acts 1-4 verbatim and the shots of act 4.

Act 4 (round 1, ADVANCE): the Neophytes (10 models) walk into a ruin with their joined hero `Cult Leader`, who carries
Grounded Precision (+1 to hit while in cover). The table reads cover AFTER the move (`_solo_majority_in_cover`: a
single-model unit by its centre, a squad by more than half of its bases fully inside), for the host AND the hero, and the
hero hits on 3+. The core refreshed the host's flag from its centre cell only and left the hero's at the pre-move
value (out of cover), so the hero hit on 4+ and the volley parted.

  * the shoot replay gate (the parity set: table hero_attach, model sighting, movement port): act 4 is FULL-equal.
  * the landing carries the table's flags: host AND hero in cover (before the move: neither).
  * below rules epoch 73 the hero's flag is still the pre-move one (byte-identical).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "g4r3_gp_cover"


def _act() -> tuple[dict, dict]:
    rows = [json.loads(x) for x in (FIXTURE / "gf_1000_net_035" / "acts.jsonl").read_text().splitlines() if x.strip()]
    return rows[0], next(r for r in rows if r["kind"] == "act")


def _landing(rules_epoch: int) -> dict:
    import nml_core

    head, act = _act()
    knobs = dict(head["knobs"], movement=True, hero_attach=True, engage_fold=True, rules_epoch=rules_epoch)
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    nxt = core.resolve(core.state_of(act["state"]), act["pick"]["action"])
    return nxt.plain()["units"]


def _chain() -> tuple[str, str]:
    _, act = _act()
    host = act["pick"]["action"]["unit"]
    return host, act["state"]["units"][host]["attached"][0]


def test_the_gate_replays_act_4_full_equal(capsys):
    srg.run(FIXTURE, str(REPO), "table", 0, 99, True, sighting="model", movement=True)
    out = capsys.readouterr().out
    m = re.search(r"EQUAL : (\d+)/(\d+) acts FULL-equal", out)
    assert m and (int(m.group(1)), int(m.group(2))) == (1, 1), out


def test_the_landing_carries_the_cover_flag_of_host_and_hero():
    host, hero = _chain()
    units = _landing(73)
    assert (units[host]["in_cover"], units[hero]["in_cover"]) == (True, True)


def test_below_epoch_73_the_hero_keeps_its_pre_move_flag():
    host, hero = _chain()
    _, act = _act()
    assert act["state"]["units"][hero]["in_cover"] is False
    assert _landing(72)[hero]["in_cover"] is False
