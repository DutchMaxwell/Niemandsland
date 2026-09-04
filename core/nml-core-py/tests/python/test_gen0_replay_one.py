"""DESIGN_gen0_training §5 step 2 — the replay-fidelity proof, and its reds.

The claim under test is that `tools/gen0_replay_one.py` can tell a faithful
replay from an unfaithful one. Two halves:

  * the COMPARATOR on its own — `menu_diff` is field-by-field with FLOAT
    equality, so a 1e-9 shift on one destination coordinate is a divergence,
    not a rounding difference. This half needs nothing outside the repo;

  * the TOOL end to end on real corpus games, through its CLI so the module's
    monkeypatching of `selfplay._pick_for` never leaks into the rest of the
    suite. Green: every recorded menu reproduced. Three reds, each of which
    must FAIL and name the position it failed at — a wrong dice seed, a
    shifted act index, and a file missing `record_cands`. A fourth case, NOT
    a red: `record_aux` (Gen-1 recorder fix) is additive and must not be
    refused.

The corpus half is skipped where the corpus, the army lists or the terrain
bank are absent (CI), and it only reproduces when `PYTHONPATH` points at a
module built from the corpus's own commit — which is the tool's contract, and
measured in the PR: 20/20 games and 844/844 menus at `ef9a3e48`.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import gen0_replay_one as gr  # noqa: E402

TOOL = str(Path(__file__).resolve().parents[2] / "tools" / "gen0_replay_one.py")
CORPUS = Path(os.path.expanduser("~/selfplay_out/gen0_teacher"))
BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(gr.LISTS)
GAMES = ["gen0_s10000_d10000.json", "gen0_s2232_d4232.json", "gen0_s4030_d8030.json"]


def _corpus_missing() -> bool:
    return not (BANK.is_dir() and LISTS.is_dir()
                and all((CORPUS / g).exists() for g in GAMES))


needs_corpus = pytest.mark.skipif(_corpus_missing(), reason="Gen-0 corpus not on this box")


def _run(*args: str) -> tuple[int, str]:
    p = subprocess.run([sys.executable, TOOL, *args], capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# ------------------------------------------------------------- comparator ---


def test_identical_menus_report_no_difference():
    menu = [{"kind": 0, "unit": "p1_1"}, {"kind": 2, "unit": "p1_1", "dest": [1.5, 0.0, -2.5]}]
    assert gr.menu_diff(menu, [dict(c) for c in menu]) == ""


def test_a_short_menu_is_named_by_width_before_any_field():
    menu = [{"kind": 0, "unit": "p1_1"}, {"kind": 0, "unit": "p1_2"}]
    assert gr.menu_diff(menu[:1], menu) == "menu width 1, recorded 2"


def test_a_one_nanometre_destination_shift_is_a_divergence():
    """Float EQUALITY, not tolerance — this is the whole fingerprint. The same
    shift is what a wrong core build produces, and it must not be forgiven."""
    want = [{"kind": 2, "unit": "p1_1", "dest": [0.48260000348091125, 0.0, -0.0762]}]
    got = [{"kind": 2, "unit": "p1_1", "dest": [0.4826000044809113, 0.0, -0.0762]}]
    assert gr.menu_diff(got, want).startswith("cand[0].dest = ")


def test_a_missing_optional_key_is_a_divergence():
    """`cand_plain` stamps `patient`/`wave`/`shoot` only where they belong, so a
    key present on one side and absent on the other is a real difference."""
    want = [{"kind": 1, "unit": "p1_1", "dest": [0.0, 0.0, 0.0], "patient": True}]
    got = [{"kind": 1, "unit": "p1_1", "dest": [0.0, 0.0, 0.0]}]
    assert gr.menu_diff(got, want) == "cand[0].patient = None, recorded True"


# ---------------------------------------------------- replay_knobs / epoch ---


def test_replay_knobs_reads_rules_epoch_off_the_prescreen_sibling():
    """Root cause of the 15% Gen-2 replay gap this closes: the recorder
    stamps the epoch ONE LEVEL UP, `prescreen["rules_epoch"]`, a sibling of
    `prescreen["knobs"]` rather than a member of it — `kn` (the record's own
    `knobs`) is silent on `rules_epoch`, so the sibling wins over the legacy
    pin."""
    prescreen = {"knobs": {}, "rules_epoch": 3}
    assert gr.replay_knobs(prescreen["knobs"], prescreen)["rules_epoch"] == 3


def test_replay_knobs_prefers_its_own_key_over_the_sibling_stamp():
    """A record whose own `knobs.rules_epoch` disagrees with the sibling
    (never true today, but the rule the fallback must honour) is read off
    `knobs` — the sibling is a FALLBACK, not an override."""
    prescreen = {"knobs": {"rules_epoch": 2}, "rules_epoch": 3}
    assert gr.replay_knobs(prescreen["knobs"], prescreen)["rules_epoch"] == 2


def test_replay_knobs_keeps_the_legacy_pin_with_neither_key_present():
    """Every Gen-0/Gen-1 file predates both `knobs.rules_epoch` and the
    sibling stamp — this is `KNOBS`'s own unchanged behaviour before this
    fix, `prescreen` argument included or omitted."""
    assert gr.replay_knobs({}, {"knobs": {}})["rules_epoch"] == 0
    assert gr.replay_knobs({})["rules_epoch"] == 0


# ------------------------------------------------ replay_knobs / melee_reach ---


def test_replay_knobs_reads_melee_reach_off_the_records_own_top_level_knobs():
    """Gen-2b export gate (reproduced on gen0_s10013_d14013.json: divergence
    at seq 14, cand[7] a wholly different candidate). `play_game()` stamps
    `melee_reach` (PR #669 / issue #635, W2 S0) only into the record's own
    TOP-LEVEL `knobs` — its actual return value — never into
    `prescreen.knobs` (a different producer, the prescreen step's generation
    config, predating this knob and silent on it in every record). Without
    this fallback `replay_knobs` keeps `KNOBS`'s legacy pin ("all") for every
    "table" Gen-2b record, so the candidate menu the replay computes diverges
    from the one recorded."""
    record = {"prescreen": {"knobs": {}}, "knobs": {"melee_reach": "table"}}
    assert gr.replay_knobs(record["prescreen"]["knobs"], record["prescreen"],
                           record)["melee_reach"] == "table"


def test_replay_knobs_prefers_its_own_key_over_the_top_level_stamp():
    """A record whose own `prescreen.knobs.melee_reach` disagrees with the
    top-level stamp (never true today, but the rule the fallback must
    honour) is read off `prescreen.knobs` — the top-level stamp is a
    FALLBACK, not an override, exactly the rule the `rules_epoch` sibling
    fallback above already honours."""
    record = {"prescreen": {"knobs": {"melee_reach": "all"}},
              "knobs": {"melee_reach": "table"}}
    assert gr.replay_knobs(record["prescreen"]["knobs"], record["prescreen"],
                           record)["melee_reach"] == "all"


def test_replay_knobs_keeps_the_legacy_melee_reach_pin_with_neither_key_present():
    """Every pre-#669 corpus (Gen-0/Gen-1/Gen-1b/Gen-2) stamps neither key —
    `KNOBS`'s own unchanged legacy pin, `record` argument included or
    omitted."""
    assert gr.replay_knobs({}, {"knobs": {}}, {"knobs": {}})["melee_reach"] == "all"
    assert gr.replay_knobs({})["melee_reach"] == "all"


# ---------------------------------------------------------- green and red ---


@needs_corpus
def test_the_replay_reproduces_every_recorded_menu():
    code, out = _run(*[str(CORPUS / g) for g in GAMES])
    assert "[VERDICT] PASS %d/%d games" % (len(GAMES), len(GAMES)) in out, out
    assert code == 0, out
    for line in out.splitlines():
        if line.startswith("[GAME]"):
            got, want = line.split()[2].split("/")
            assert got == want, line


@needs_corpus
def test_a_wrong_dice_seed_diverges_and_names_the_position():
    code, out = _run("--dice-offset", "1", *[str(CORPUS / g) for g in GAMES])
    assert code == 1, out
    assert "[VERDICT] FAIL 0/%d games" % len(GAMES) in out, out
    assert out.count("seq ") >= len(GAMES), out


@needs_corpus
def test_a_shifted_act_index_diverges(tmp_path):
    """The corpus is read-only, so the corruption rides a COPY: one row's
    `cands.best` moved by one turns a faithful replay into a different game."""
    rec = json.loads((CORPUS / GAMES[0]).read_text(encoding="utf-8"))
    row = rec["planner_positions"][5]["cands"]
    row["best"] = (row["best"] + 1) % len(row["list"])
    bad = tmp_path / GAMES[0]
    bad.write_text(json.dumps(rec), encoding="utf-8")
    code, out = _run(str(bad))
    assert code == 1, out
    assert "[VERDICT] FAIL 0/1 games" in out, out


@needs_corpus
def test_a_file_missing_record_cands_is_refused(tmp_path):
    """`record_cands` landed at PR #522: a file recorded without it carries no
    candidate menu to replay against at all."""
    rec = json.loads((CORPUS / GAMES[0]).read_text(encoding="utf-8"))
    rec["prescreen"]["knobs"]["record_cands"] = False
    bad = tmp_path / GAMES[0]
    bad.write_text(json.dumps(rec), encoding="utf-8")
    code, out = _run(str(bad))
    assert code != 0, out
    assert "REFUSED" in out, out


@needs_corpus
def test_a_record_aux_file_is_accepted_not_refused(tmp_path):
    """Gen-1 recorder fix: `record_aux` (PR #533) hangs ADDITIVE AUX targets
    (models alive / wounds) off `rounds_log` and the result — it never
    changes the game actually played, so a record stamping it must replay
    exactly like one that does not, not get refused at the door."""
    rec = json.loads((CORPUS / GAMES[0]).read_text(encoding="utf-8"))
    rec["prescreen"]["knobs"]["record_aux"] = True
    ok = tmp_path / GAMES[0]
    ok.write_text(json.dumps(rec), encoding="utf-8")
    code, out = _run(str(ok))
    assert "REFUSED" not in out, out
    assert "[VERDICT] PASS 1/1 games" in out, out
    assert code == 0, out
