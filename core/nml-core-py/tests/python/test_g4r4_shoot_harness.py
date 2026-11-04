"""AI-G4 round 4, the shooting HARNESS rows (rules epoch 73): H-DANG-CUT, H-ROUND-BOUNDARY, H-AIM-ORDER and the pre
half of C-GRANTED-RANGE. Four ways the replay gate started the core from a state the table never had.

THE BUNDLED GAMES (`fixtures/g4r4_*/`, the round-3 recording of the 1104 corpus, trimmed like the other shoot fixtures:
the header, `auto` placeholders for every other ordinal, the act line with its pre/verb lines, every roll up to the
act, the act's sidecar shots). The acts and what they closed:

  * H-ROUND-BOUNDARY - gf_001 act 25, gf_037 act 18. The table's last roll of the act is the NEXT round's start roll
    (the Shaken recovery test), stamped under the last activation's ordinal with `round` 4 while the act is in round
    3. The gate compared it against the core's volley and counted a "table_longer" act. The gate now keeps only the
    rolls of the act's own round.
  * H-AIM-ORDER - gf_047 act 2. The spell killed all five models of the target host before the volley; the joined
    hero stands. The gate mapped the aim from the act-START units (host alive), so the core got a split aimed at a
    dead host and stayed silent. The aim is now mapped from the state after the pre patch.
  * C-GRANTED-RANGE (pre half) - gf_026 act 9, gf_027 act 2. The cast Lust Boon grants +8" reach; the core takes a
    reach bonus only from a unit's static rules. The pre block carries the grant as `reach` (inches, the growth of
    the unit's shooting-range bonus over the cast leg) and the gate adds it to the printed range of the unit's ranged
    weapons for that one act (the core reads `range + reach_bonus_in` everywhere, so it is the same sum).
  * H-DANG-CUT - aof_005 act 26, aof_024 act 16, aof_032 act 23, gf_021 act 15. When a cast follows the dangerous
    test the gate cuts both, so the shooter's own losses must come from the pre block - and the recorder took its
    snapshot AFTER the test. The recorder now snapshots before it (gdUnit, test/v36/g4_h1a_test.gd, the live path);
    here the gate replays the pre block the fixed recorder stamps, and `patch_pre` takes the survivors' wounds.

HONEST LIMITS. The pre blocks of the four H-DANG-CUT games and of the two reach games are DERIVED from the recording
(the shooter chain's state in the act that followed; the reach from the book's registry) in the form the fixed
recorder writes, because the recording predates the fix; the recorder itself is proven by its own gdUnit tests. The
dangerous test's morale leg (aof_003 act 24, gf_047 act 10) is not in this row: it needs a core knob.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FX = Path(__file__).resolve().parent / "fixtures"


def gate(capsys, ref: Path) -> tuple[int, int, str]:
    """The gate's own run over `ref` (every dice face compared): (FULL-equal acts, shooting acts, the report)."""
    srg.run(ref, str(REPO), "table", 0, 99, True, sighting="model", movement=True)
    out = capsys.readouterr().out
    m = re.search(r"EQUAL : (\d+)/(\d+) acts FULL-equal", out)
    assert m, out
    return int(m.group(1)), int(m.group(2)), out


def test_the_next_rounds_start_roll_is_not_part_of_the_act(capsys):
    ref = FX / "g4r4_round_boundary"
    for g in ref.iterdir():
        head, lines, dice, _ = srg.read_game(g)
        act = lines[0]
        late = [r for r in dice if int(r["act"]) == act["act"] and int(r["round"]) > int(act["round"])]
        assert late, "fixture broken: %s act %d has no roll of a later round" % (g.name, act["act"])
    equal, acts, out = gate(capsys, ref)
    assert (equal, acts) == (2, 2), out


def test_the_aim_is_mapped_from_the_state_after_the_spell(capsys):
    equal, acts, out = gate(capsys, FX / "g4r4_aim_order")
    assert (equal, acts) == (1, 1), out


def test_a_granted_reach_in_the_pre_block_reaches_the_volley(capsys):
    equal, acts, out = gate(capsys, FX / "g4r4_granted_reach")
    assert (equal, acts) == (2, 2), out
    assert "OWNER : 2/2" in out, out


def test_a_pre_block_without_the_reach_key_replays_as_before(capsys, tmp_path):
    """An old recording has no `reach`: the header stays as recorded, the act parts at the count as it always did."""
    ref = tmp_path / "ref"
    shutil.copytree(FX / "g4r4_granted_reach", ref)
    for f in ref.glob("*/acts.jsonl"):
        rows = [json.loads(x) for x in f.read_text().splitlines()]
        for r in rows:
            for rec in (r.get("units") or {}).values() if r.get("kind") == "pre" else []:
                rec.pop("reach", None)
        f.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    equal, acts, out = gate(capsys, ref)
    assert (equal, acts) == (0, 2), out


def test_with_reach_raises_the_ranged_weapons_of_the_named_unit_only():
    g = FX / "g4r4_granted_reach" / "gf_1000_net_026"
    head, lines, _, _ = srg.read_game(g)
    uid, = [u for u, r in srg.read_pre(g)[9].items() if r.get("reach")]
    out = srg.with_reach(head["profiles"], srg.read_pre(g)[9])
    before = {w["name"]: w["range"] for w in head["profiles"][uid]["weapons"]}
    after = {w["name"]: w["range"] for w in out[uid]["weapons"]}
    assert before["Battle Rifle"] == 24 and after["Battle Rifle"] == 32
    assert before["Strike"] == after["Strike"] == 0, "a melee weapon has no reach to grow"
    assert all(out[k] is head["profiles"][k] for k in head["profiles"] if k != uid), "other units are untouched"
    assert srg.with_reach(head["profiles"], {}) == head["profiles"] and srg.with_reach(head["profiles"], None) == head["profiles"]


def test_the_shooters_own_dangerous_losses_replay_full_equal(capsys):
    equal, acts, out = gate(capsys, FX / "g4r4_dang_cut")
    assert (equal, acts) == (4, 4), out
    assert "OWNER : 4/4" in out, out


def test_patch_pre_takes_the_survivors_wounds():
    """aof_005 act 26: the hero of the shooter chain (Tough 3) stands at 3 wounds in the act-start state; a pre record
    that names its wounds after the dangerous test starts the core from them, a record without wounds changes nothing."""
    g = FX / "g4r4_dang_cut" / "aof_1000_net_005"
    head, lines, _, _ = srg.read_game(g)
    plain = lines[0]["state"]
    hero = next(k for k, u in plain["units"].items() if u.get("attached_to") and u["wounds"] == [3])
    hurt = srg.patch_pre(plain, {hero: {"alive": 1, "shaken": False, "wounds": [2]}})
    assert hurt["units"][hero]["wounds"] == [2] and hurt["units"][hero]["alive"] == 1
    old = srg.patch_pre(plain, {hero: {"alive": 1, "shaken": False}})
    assert old["units"][hero]["wounds"] == [3], "a record from before the key keeps the recorded wounds"
    assert plain["units"][hero]["wounds"] == [3], "the input state is not edited in place"
