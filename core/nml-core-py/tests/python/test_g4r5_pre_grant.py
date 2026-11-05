"""AI-G4 round 5, row R6 F-PRE-TOKENS (rules epoch 73): the pre block names the rule a cast GRANTED, and the replay gate puts it
back as the ledger buff the table's token is.

THE ACT (`fixtures/g4r5_pre_grant/`, the round-4 recording of the 1105 corpus, trimmed like the other shoot fixtures): gf_1000_net_037
act 10. Two Change Vassal Micro-Titans cast Breath of Change on themselves ("Bane when Shooting", once); the table then rolls the
defender's re-roll on the first volley and the core, which reads a live grant since #2500, never saw the grant: the replay's pre block
had no key for it, the act parted at roll 3 (a table defense die the core did not draw).

HONEST LIMIT. The round-4 recording predates the recorder, so its act-10 pre line is `units: {}`. The fixture's pre line is DERIVED from
the table's own log line ("Breath of Change on <unit> is ACTIVE: grants Bane when Shooting", the way `classify_r4.py` BUFF reads it) in
the form the fixed recorder writes; the recorder itself is proven by its gdUnit tests (test/v36/g4_h1a_test.gd, the live cast path) and
round 5's recording proves the two halves end to end.
"""

from __future__ import annotations

import copy
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FX = Path(__file__).resolve().parent / "fixtures" / "g4r5_pre_grant"


def gate(capsys, ref: Path) -> tuple[int, int, str]:
    """The gate's own run over `ref` (every dice face compared): (FULL-equal acts, shooting acts, the report)."""
    srg.run(ref, str(REPO), "table", 0, 99, True, sighting="model", movement=True)
    out = capsys.readouterr().out
    m = re.search(r"EQUAL : (\d+)/(\d+) acts FULL-equal", out)
    assert m, out
    return int(m.group(1)), int(m.group(2)), out


def test_a_granted_rule_in_the_pre_block_reaches_the_volley(capsys):
    equal, acts, out = gate(capsys, FX)
    assert (equal, acts) == (1, 1), out
    assert "OWNER : 1/1" in out, out


def test_a_pre_block_without_the_grants_key_replays_as_before(capsys, tmp_path):
    """Mutant: the same recording with the key stripped (the round-4 shape) parts again at the defender's re-roll."""
    ref = tmp_path / "ref"
    shutil.copytree(FX, ref)
    for f in ref.glob("*/acts.jsonl"):
        rows = [json.loads(x) for x in f.read_text().splitlines()]
        for r in rows:
            for rec in (r.get("units") or {}).values() if r.get("kind") == "pre" else []:
                assert rec.pop("grants") == ["Bane when Shooting"], "fixture broken: the pre line must carry the grant"
        f.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    equal, acts, out = gate(capsys, ref)
    assert (equal, acts) == (0, 1), out


def test_patch_pre_adds_one_ledger_buff_per_granted_name_to_the_named_unit_only():
    head, lines, _, _ = srg.read_game(next(FX.iterdir()))
    plain = lines[0]["state"]
    uid, other = list(srg.read_pre(next(FX.iterdir()))[10])[0], None
    other = next(k for k in plain["units"] if k != uid)
    before = copy.deepcopy(plain)
    out = srg.patch_pre(plain, {uid: {"alive": plain["units"][uid]["alive"], "shaken": False, "grants": ["Bane when Shooting", "Rending"]}})
    buffs = out["units"][uid]["ledger"]["buffs"]
    assert [b["grants_rule"] for b in buffs[-2:]] == ["Bane when Shooting", "Rending"]
    assert all(b["granted_to"] == [uid] for b in buffs[-2:])
    assert out["units"][other] == plain["units"][other], "an unnamed unit is untouched"
    assert plain == before, "the input state is not edited in place"
    none = srg.patch_pre(plain, {uid: {"alive": plain["units"][uid]["alive"], "shaken": False}})
    assert none["units"][uid].get("ledger") == plain["units"][uid].get("ledger"), "a record without the key adds nothing"
