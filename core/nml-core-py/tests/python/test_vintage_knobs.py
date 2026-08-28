"""NML-1130 — the parity gates replay a corpus at ITS OWN vintage.

WHAT BROKE. PR #446 (D5-4) made the header knob `engage_fold` default ON in
the Rust twin (`core/nml-core/src/acts.rs`); PR #448 (NML-1103) did the same
for conditional AP via `LEGACY_NO_COND_AP`. `melee_replay_gate.py` was the
only gate that ever set `engage_fold` explicitly (its own D5-4 red proof
needed a knob to flip); every other gate — `charge_gate`, `dice_gate`,
`shoot_replay_gate`, `sight_gate`, `charge_move_gate`, `qa_gate` (via
`selfplay.play_game`) — inherited whichever default the twin carried on the
day it ran, silently, even though every corpus under `~/selfplay_out` was
RECORDED before one or both PRs landed.

`shoot_replay_gate.vintage_knobs()` reads a corpus's OWN header and resolves
what it should replay with; `resolve_vintage_flag()` is the `auto`/`on`/`off`
CLI knob every gate now exposes as `--engage-fold`/`--cond-ap`.

This file pins `vintage_knobs`/`resolve_vintage_flag`/`vintage_report_line`
at the unit level, then one small end-to-end plumbing test per gate group —
proving the CLI flag actually reaches `core.set_header`/
`nml_core.set_legacy_no_cond_ap`, not just that argparse accepts it — using
the bundled fixtures, or, where a gate needs a corpus shape the fixtures
don't carry (`moves_calls.jsonl`, a `core_s<seed>.json` result), a minimal
directory built in `tmp_path`.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import nml_core  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "alien_hives_1000.json"
ARMY2 = LISTS / "battle_brothers_1000.json"

#: mirrors test_dice_gate.py's GAMES map — the two bundled fixtures, one
#: shooting game and one charge game.
GAMES = {
    "shoot_replay": "alien_hives_1000_vs_battle_brothers_1000_s33",
    "melee_replay": "alien_hives_1000_vs_change_disciples_1000_s31",
}
#: real shas off THIS repo's own history — PR #448's (NML-1103) merge commit
#: and one commit either side of it — so the ancestor check has something to
#: answer without needing a synthetic git repo.
COND_AP_FIX = "c94f825"
BEFORE_FIX = "1c269d8"   # PR #446 (D5-4), merged before #448
AFTER_FIX = "8c724b3"    # merged after #448


@pytest.fixture(scope="module")
def two_game_ref(tmp_path_factory) -> Path:
    """The two bundled fixtures under their original names, as a `--ref` dir
    — `dice_gate.py`'s `dice_seed_of` cross-check needs the `_s<seed>` suffix
    to match the arena json, which is why they cannot simply be pointed at in
    place."""
    out = tmp_path_factory.mktemp("nml1130_ref")
    for src, name in GAMES.items():
        shutil.copytree(FIXTURES / src, out / name)
    return out


@pytest.fixture
def charge_move_ref(tmp_path) -> Path:
    """The melee fixture plus an EMPTY `moves_calls.jsonl` header line —
    enough for `charge_move_gate.run()` to pick the game up and reach its
    per-game `set_header` call (where NML-1130's flags land), with no
    recorded charge move for it to compare landings against."""
    game = tmp_path / GAMES["melee_replay"]
    shutil.copytree(FIXTURES / "melee_replay", game)
    (game / "moves_calls.jsonl").write_text(json.dumps({"board_in": [48.0, 72.0]}) + "\n")
    return tmp_path


# --------------------------------------------------------- vintage_knobs ---


def test_engage_fold_present_is_read_verbatim():
    assert srg.vintage_knobs({"knobs": {"engage_fold": True}})["engage_fold"] is True
    assert srg.vintage_knobs({"knobs": {"engage_fold": False}})["engage_fold"] is False


def test_engage_fold_absent_defaults_off():
    """No corpus recorded before PR #446 stamps the key at all — the table it
    ran on had no fold, so `auto` must not silently inherit the twin's ON
    default."""
    assert srg.vintage_knobs({})["engage_fold"] is False
    assert srg.vintage_knobs({"knobs": {}})["engage_fold"] is False


def test_cond_ap_present_is_read_verbatim():
    assert srg.vintage_knobs({"knobs": {"cond_ap": True}})["cond_ap"] is True
    assert srg.vintage_knobs({"knobs": {"cond_ap": False}})["cond_ap"] is False


def test_cond_ap_absent_with_no_repo_falls_back_on():
    """No commit pin reaches the header (qbf_ref/qbg_ref carry none) and no
    `repo` was handed in to ask git — the documented FALLBACK, not the naive
    'absent -> legacy' reading (NML-1128: that reading costs qbg_ref 141+
    acts of pick equality)."""
    assert srg.vintage_knobs({})["cond_ap"] is True
    assert srg.vintage_knobs({"knobs": {}}, repo=None)["cond_ap"] is True


def test_cond_ap_absent_with_a_commit_pin_before_the_fix_reads_legacy_off():
    head = {"knobs": {}, "commit": BEFORE_FIX}
    assert srg.vintage_knobs(head, repo=str(REPO))["cond_ap"] is False


def test_cond_ap_absent_with_a_commit_pin_at_or_after_the_fix_reads_on():
    assert srg.vintage_knobs(
        {"knobs": {}, "commit": COND_AP_FIX}, repo=str(REPO))["cond_ap"] is True
    assert srg.vintage_knobs(
        {"knobs": {}, "base_commit": AFTER_FIX}, repo=str(REPO))["cond_ap"] is True


def test_cond_ap_commit_pin_can_ride_inside_knobs_too():
    head = {"knobs": {"commit": BEFORE_FIX}}
    assert srg.vintage_knobs(head, repo=str(REPO))["cond_ap"] is False


def test_cond_ap_an_unresolvable_commit_falls_back_on():
    """A pin git cannot place (typo, shallow clone, wrong repo) must not
    raise — and must not silently read as legacy, which would be the wrong
    direction to fail in for a corpus this fallback cannot otherwise judge."""
    head = {"knobs": {}, "commit": "0000000not-a-real-sha"}
    assert srg.vintage_knobs(head, repo=str(REPO))["cond_ap"] is True


# ---------------------------------------------------- resolve_vintage_flag ---


def test_resolve_vintage_flag_on_and_off_ignore_the_header():
    head = {"knobs": {"engage_fold": True, "cond_ap": False}}
    assert srg.resolve_vintage_flag("off", head, str(REPO), "engage_fold") is False
    assert srg.resolve_vintage_flag("on", head, str(REPO), "cond_ap") is True


def test_resolve_vintage_flag_auto_delegates_to_vintage_knobs():
    head = {"knobs": {"engage_fold": True, "cond_ap": False}}
    assert srg.resolve_vintage_flag("auto", head, str(REPO), "engage_fold") is True
    assert srg.resolve_vintage_flag("auto", head, str(REPO), "cond_ap") is False


# ----------------------------------------------------- vintage_report_line ---


def test_vintage_report_line_a_single_pair_prints_once():
    assert srg.vintage_report_line({(True, False)}) == "engage_fold=True cond_ap=False"


def test_vintage_report_line_mixed_pairs_say_so():
    line = srg.vintage_report_line({(True, True), (False, True)})
    assert line.startswith("engage_fold/cond_ap MIXED:")
    assert "(engage_fold=False cond_ap=True)" in line
    assert "(engage_fold=True cond_ap=True)" in line


# ---------------------------------------------- per-gate flag plumbing ------


def test_shoot_replay_gate_plumbs_engage_fold_and_cond_ap(two_game_ref, capsys):
    srg.run(two_game_ref, str(REPO), "table", 0, 0, True, engage_fold="on", cond_ap="on")
    out_on = capsys.readouterr().out
    srg.run(two_game_ref, str(REPO), "table", 0, 0, True, engage_fold="off", cond_ap="off")
    out_off = capsys.readouterr().out
    assert "engage_fold=True cond_ap=True" in out_on
    assert "engage_fold=False cond_ap=False" in out_off


def test_melee_replay_gate_plumbs_engage_fold_and_cond_ap(two_game_ref, capsys):
    import melee_replay_gate as mrg

    mrg.run(two_game_ref, str(REPO), "table", 0, True, engage_fold="on", cond_ap="on")
    out_on = capsys.readouterr().out
    mrg.run(two_game_ref, str(REPO), "table", 0, True, engage_fold="off", cond_ap="off")
    out_off = capsys.readouterr().out
    assert "engage_fold=True cond_ap=True" in out_on
    assert "engage_fold=False cond_ap=False" in out_off


def test_melee_replay_gate_red_no_hero_fold_still_wins_over_engage_fold_on(two_game_ref, capsys):
    """The existing D5-4 red proof (`--red-no-hero-fold`) forces the fold OFF
    regardless of what `--engage-fold` asks for — NML-1130 must not weaken
    a red proof that already shipped."""
    import melee_replay_gate as mrg

    mrg.run(two_game_ref, str(REPO), "table", 0, True, engage_fold="on", no_hero_fold=True)
    assert "engage_fold=False" in capsys.readouterr().out


def test_dice_gate_plumbs_engage_fold_and_cond_ap(two_game_ref, tmp_path, capsys):
    import dice_gate as dg

    dg.run(two_game_ref, str(REPO), 0, str(tmp_path / "a.json"), "", True,
           engage_fold="on", cond_ap="on")
    out_on = capsys.readouterr().out
    dg.run(two_game_ref, str(REPO), 0, str(tmp_path / "b.json"), "", True,
           engage_fold="off", cond_ap="off")
    out_off = capsys.readouterr().out
    assert "engage_fold=True cond_ap=True" in out_on
    assert "engage_fold=False cond_ap=False" in out_off


def test_charge_gate_plumbs_engage_fold_and_cond_ap(two_game_ref, capsys):
    import charge_gate as cg

    cg.run(two_game_ref, str(REPO), "table", 0, engage_fold="on", cond_ap="on")
    out_on = capsys.readouterr().out
    cg.run(two_game_ref, str(REPO), "table", 0, engage_fold="off", cond_ap="off")
    out_off = capsys.readouterr().out
    assert "engage_fold=True cond_ap=True" in out_on
    assert "engage_fold=False cond_ap=False" in out_off


def test_charge_move_gate_plumbs_engage_fold_and_cond_ap(charge_move_ref, capsys):
    import charge_move_gate as cmg

    cmg.run(charge_move_ref, str(REPO), 0, False, False, True, engage_fold="on", cond_ap="on")
    out_on = capsys.readouterr().out
    cmg.run(charge_move_ref, str(REPO), 0, False, False, True, engage_fold="off", cond_ap="off")
    out_off = capsys.readouterr().out
    assert "engage_fold=True cond_ap=True" in out_on
    assert "engage_fold=False cond_ap=False" in out_off


def test_sight_gate_port_plumbs_engage_fold_and_cond_ap():
    """`sight_gate.py` imports `nml_core` lazily, only under `--port`
    (`run()`'s `global nml_core; import nml_core`) — reproduced here so
    `port_check` can be called directly without a full `run()` invocation."""
    import sight_gate as sg

    sg.nml_core = nml_core
    game = FIXTURES / "shoot_replay"
    p_on = sg.port_check([game], str(REPO), "", engage_fold="on", cond_ap="on")
    p_off = sg.port_check([game], str(REPO), "", engage_fold="off", cond_ap="off")
    assert p_on["vintage"] == "engage_fold=True cond_ap=True"
    assert p_off["vintage"] == "engage_fold=False cond_ap=False"


def test_qa_gate_plumbs_engage_fold_and_cond_ap(tmp_path, capsys):
    """No real corpus needed: `qa_gate.py` reads no per-game header at all
    (`core_s<seed>.json` carries none — see `vintage_knobs`'s docstring), so
    the flags resolve once against `vintage_knobs({})` and print regardless
    of whether any game's army lists were found (they are not, here — the
    'NO ARMY LIST' line proves every game took that skip, never touching
    `selfplay.play_game`)."""
    import qa_gate

    game = tmp_path / "nowhere_1000_vs_nowhere2_1000_s1"
    game.mkdir()
    (game / "core_s1.json").write_text("{}")
    qa_gate.main(["--ref", str(tmp_path), "--bank", str(tmp_path), "--lists", str(tmp_path),
                  "--engage-fold", "on", "--cond-ap", "on"])
    out_on = capsys.readouterr().out
    qa_gate.main(["--ref", str(tmp_path), "--bank", str(tmp_path), "--lists", str(tmp_path),
                  "--engage-fold", "off", "--cond-ap", "off"])
    out_off = capsys.readouterr().out
    assert "NO ARMY LIST for 1 game(s)" in out_on
    assert "engage_fold=True cond_ap=True" in out_on
    assert "engage_fold=False cond_ap=False" in out_off


@pytest.mark.skipif(not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists()),
                    reason="no terrain bank / AI lists on this machine")
def test_play_game_stamps_engage_fold_and_cond_ap():
    """`selfplay.play_game`'s two NML-1130 params, end to end: stamped into
    the result's `knobs` for documentation, applied via the header knob and
    `nml_core.set_legacy_no_cond_ap` (see the function docstring), and the
    call itself does not raise with either off."""
    import selfplay as sp

    core = nml_core.load(str(REPO))
    got = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core,
                        engage_fold=False, cond_ap=False)
    assert got["knobs"]["engage_fold"] is False
    assert got["knobs"]["cond_ap"] is False


@pytest.mark.skipif(not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists()),
                    reason="no terrain bank / AI lists on this machine")
def test_play_game_cond_ap_default_leaves_the_global_flag_untouched(monkeypatch):
    """REGRESSION PIN. `test_selfplay.py`/`test_sidecars.py`/`test_rows.py`
    already manage `LEGACY_NO_COND_AP` themselves around a `play_game` call
    (an `autouse` fixture, for `m3_ref_v2`'s known-legacy corpus). A first cut
    of this parameter defaulted `cond_ap` to `True` and called
    `set_legacy_no_cond_ap` unconditionally — which silently reset the flag
    those fixtures had just set, mid-test, and broke all three files when the
    FULL suite ran (green in isolation, red in the full run — the ordering
    tell). `cond_ap=None` (the default) must not call `set_legacy_no_cond_ap`
    at all; an explicit bool still must."""
    import selfplay as sp

    calls: list[bool] = []
    monkeypatch.setattr(nml_core, "set_legacy_no_cond_ap", calls.append)
    core = nml_core.load(str(REPO))
    sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core)  # no cond_ap kwarg
    assert calls == []
    sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, cond_ap=True)
    assert calls == [False]
