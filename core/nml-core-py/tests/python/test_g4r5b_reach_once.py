"""AI-G4 round 5, row R17 F-REACH-ONCE (the shooting HARNESS, rules epoch 73): a spell's range grant is counted once.

THE BUNDLED GAMES are the round-4 `fixtures/g4r4_granted_reach/` (gf_026 act 9, gf_027 act 2: Lust Cultists cast the
Lust Boon grant, "Enhanced Lustbound" in the repo registry, +8" shooting range, and shoot a Flamer of printed range 12").
That fixture predates the recorder's `grants` key (#2513): its pre block carries only `reach` (8). Since #2513 the pre
block carries BOTH views of the same grant and the gate used both: `with_reach` raised the printed range by `reach`
AND `patch_pre` stamped `grants` as a ledger buff the core reads the range off itself (12 + 8 + 8 = 28" instead of 20"),
so the Flamer fired 3 dice where the table fired 1.

The derived fixture here is the round-4 one with `grants` added to the pre records that carry `reach`, the shape the
fixed recorder writes. The ORIGINAL fixture (no `grants`) is the control: an older recording still needs the stand-in.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FX = Path(__file__).resolve().parent / "fixtures" / "g4r4_granted_reach"
GRANT = "Enhanced Lustbound"


def gate(capsys, ref: Path) -> tuple[int, int, str]:
    """The gate's own run over `ref` (every dice face compared): (FULL-equal acts, shooting acts, the report)."""
    srg.run(ref, str(REPO), "table", 0, 99, True, sighting="model", movement=True)
    out = capsys.readouterr().out
    m = re.search(r"EQUAL : (\d+)/(\d+) acts FULL-equal", out)
    assert m, out
    return int(m.group(1)), int(m.group(2)), out


def derive(tmp_path: Path, every_reach_record: bool) -> Path:
    """The round-4 fixture with `grants` on its pre records. `every_reach_record`: on each record that carries `reach`
    (host and joined hero); else on the host only (the hero's record keeps `reach` and has no `grants`)."""
    ref = tmp_path / "ref"
    shutil.copytree(FX, ref)
    for f in ref.glob("*/acts.jsonl"):
        rows = [json.loads(x) for x in f.read_text().splitlines()]
        for r in rows:
            if r.get("kind") != "pre":
                continue
            recs = [rec for rec in r["units"].values() if rec.get("reach")]
            for rec in recs if every_reach_record else [max(recs, key=lambda q: q["alive"])]:
                rec["grants"] = [GRANT]
        f.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    return ref


@pytest.mark.parametrize("every_reach_record", [True, False], ids=["grants-on-every-reach-record", "grants-on-the-host-only"])
def test_a_grant_in_the_pre_block_is_counted_once(capsys, tmp_path, every_reach_record):
    """RED before the row: the stand-in and the ledger buff both add the +8", the Flamer fires 3 dice (table: 1)."""
    equal, acts, out = gate(capsys, derive(tmp_path, every_reach_record))
    assert (equal, acts) == (2, 2), out


def test_a_pre_block_with_reach_and_without_grants_keeps_the_stand_in(capsys):
    """The control: the original fixture (an older recording, `reach` only) stays equal through the stand-in."""
    equal, acts, out = gate(capsys, FX)
    assert (equal, acts) == (2, 2), out
    assert "OWNER : 2/2" in out, out


def test_with_reach_returns_the_profiles_unchanged_when_a_record_carries_grants(tmp_path):
    g = FX / "gf_1000_net_026"
    head, lines, _, _ = srg.read_game(g)
    host = lines[0]["pick"]["action"]["unit"]
    pre = srg.read_pre(derive(tmp_path, False) / "gf_1000_net_026")[9]
    assert pre[host]["grants"] == [GRANT] and pre[host]["reach"] == 8
    hero = next(u for u in pre if u != host)
    assert "grants" not in pre[hero] and pre[hero]["reach"] == 8, "fixture shape: the hero's record has reach but no grants"
    assert srg.with_reach(head["profiles"], pre) == head["profiles"], "the ledger buff carries the range, the stand-in must not"
    reach_only = {u: {k: v for k, v in rec.items() if k != "grants"} for u, rec in pre.items()}
    raised = srg.with_reach(head["profiles"], reach_only)
    assert {w["name"]: w["range"] for w in raised[host]["weapons"]}["Battle Rifle"] == 32, "without grants the stand-in is on"
