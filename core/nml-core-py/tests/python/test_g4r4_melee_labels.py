"""AI-G4 round 3, rows R3-H2 and R3-H3 (rules epoch 73) - who signs a die, in the charge and the shoot replay gate.

R3-H2. The table signs a LONE joined hero's save with its dead host's label, the core with the hero's own. The shoot
gate relaxed that (`signer_ok`, #2413); the charge gate still compared owner labels exactly and parted on it.

R3-H3. A rule-generated extra die (Bloodborn / Primal / Predator ... "for each unmodified 6, one more attack") is
signed by the HOST at the table and by the ROLLING MEMBER in the core. The gates accept either label for that die and
for no other, and still compare its count, target and faces in full.

THE BUNDLED GAMES (the 1104 recording, round 3, trimmed like the other fixtures: header, `auto` placeholders before the
act, the act line, every roll up to it verbatim):

  * `fixtures/g4r4_h2_lone_hero_melee/gf_1000_net_015` act 19 - the lone hero is charged; its save is roll 4.
  * `fixtures/g4r4_h3_extra_die_melee/gf_1000_net_034` act 26 - a joined hero's 6s add 2 dice (roll 5).
  * `fixtures/g4r4_h3_extra_die_shoot/gf_1000_net_034` act 28 - the same family in a volley (roll 6).
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
LONE, EXTRA, EXTRA_SHOT = (FIXTURES / n for n in ("g4r4_h2_lone_hero_melee", "g4r4_h3_extra_die_melee", "g4r4_h3_extra_die_shoot"))


def melee(capsys, root: Path) -> str:
    mrg.run(root, str(REPO), "table", 0, True, movement=True)
    return capsys.readouterr().out


def shoot(capsys, root: Path) -> str:
    srg.run(root, str(REPO), "table", 0, 99, True, sighting="model", movement=True)
    return capsys.readouterr().out


def edited(src: Path, tmp_path: Path, seq: int, **fields) -> Path:
    """A copy of the fixture root with the table's roll `seq` changed - the mutant the gate must still catch."""
    dst = tmp_path / src.name
    shutil.copytree(src, dst)
    path = next(dst.glob("*/dice.jsonl"))
    rows = [json.loads(x) for x in path.read_text().splitlines()]
    path.write_text("\n".join(json.dumps(dict(r, **fields) if r["seq"] == seq else r) for r in rows) + "\n")
    return dst


def test_a_lone_heros_save_signed_by_its_dead_host_is_full_equal_in_the_charge_gate(capsys):
    out = melee(capsys, LONE)
    assert "EQUAL : 1/1 acts FULL-equal" in out, out
    assert "parted: 0 shape, 0 faces" in out, out


def test_the_lone_hero_relaxation_names_only_the_host(capsys, tmp_path):
    out = melee(capsys, edited(LONE, tmp_path, 26, owner="AI (Jokers)"))
    assert "EQUAL : 0/1 acts FULL-equal" in out and "first field to part: owner=1" in out, out


def test_an_extra_die_signed_by_the_host_is_full_equal_in_the_charge_gate(capsys):
    out = melee(capsys, EXTRA)
    assert "EQUAL : 1/1 acts FULL-equal" in out, out
    assert "parted: 0 shape, 0 faces" in out, out


def test_the_extra_die_is_still_compared_in_full(capsys, tmp_path):
    out = melee(capsys, edited(EXTRA, tmp_path, 56, faces=[2, 2]))
    assert "parted: 0 shape, 1 faces" in out, out


def test_only_the_extra_die_may_carry_the_host_label(capsys, tmp_path):
    """The hero's own 3-dice attack (seq 55) signed by the host is a real signer bug and parts as before."""
    out = melee(capsys, edited(EXTRA, tmp_path, 55, owner="AI (Saurian Warriors)"))
    assert "EQUAL : 0/1 acts FULL-equal" in out and "first field to part: owner=1" in out, out


def test_an_extra_die_signed_by_the_host_is_owner_equal_in_the_shoot_gate(capsys):
    out = shoot(capsys, EXTRA_SHOT)
    assert "OWNER : 1/1 acts FULL-equal AND every roll signed by the same unit" in out, out
