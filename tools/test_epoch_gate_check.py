#!/usr/bin/env python3
"""Tests for tools/epoch_gate_check.py.

The gate's whole job is to refuse half-proven rules PRs, so these tests feed it the
byte-exact unified diffs of the two holes found on 2026-09-14 by reading the source:
a PR that adds a NEW `EPOCH_<n>_<NAME>` constant WITHOUT bumping `CURRENT_RULES_EPOCH`
(the old code printed "nothing to check" and gated nothing), and a PR whose bump is at
or below the live epoch (a stale branch rebased carelessly). A diff that touches no
epoch symbol at all must still pass untouched.

Since the #972 lesson (a renumber 49 -> 51 at rebase left literal pins running below
the new gate) the gate's own tests also pin the pin rule: a leg is PROVEN only by the
frozen constant or a test name carrying the epoch; bare literals still count in the
census but a literal-only leg is refused.

Run:  python3 -m pytest tools/test_epoch_gate_check.py
"""

import importlib.util
import os
import subprocess
import sys
import textwrap

_HERE = os.path.dirname(os.path.abspath(__file__))
_CHECKER = os.path.join(_HERE, "epoch_gate_check.py")


def run_checker(tmp_path, diff_text):
    diff = tmp_path / "pr.diff"
    diff.write_text(textwrap.dedent(diff_text))
    return subprocess.run(
        [sys.executable, _CHECKER, str(diff)], capture_output=True, text=True
    )


def test_new_epoch_constant_without_bump_is_refused(tmp_path):
    """Hole 1: an EPOCH constant lands with no CURRENT_RULES_EPOCH bump at all."""
    r = run_checker(
        tmp_path,
        """\
        diff --git a/core/nml-core/src/rules.rs b/core/nml-core/src/rules.rs
        --- a/core/nml-core/src/rules.rs
        +++ b/core/nml-core/src/rules.rs
        @@ -10,2 +10,4 @@
        +pub const EPOCH_23_LATE_FIX: u32 = 23;
        +
        """,
    )
    assert r.returncode == 1, r.stdout + r.stderr
    assert (
        "rule 4: a new EPOCH_<n> constant was added without bumping CURRENT_RULES_EPOCH"
        " - a rules fix landing below the live epoch gates nothing"
    ) in r.stdout


def test_bump_at_or_below_previous_epoch_is_refused(tmp_path):
    """Hole 2: a stale rebase sets CURRENT_RULES_EPOCH to 18 while main already lives at 19."""
    r = run_checker(
        tmp_path,
        """\
        diff --git a/core/nml-core/src/rules.rs b/core/nml-core/src/rules.rs
        --- a/core/nml-core/src/rules.rs
        +++ b/core/nml-core/src/rules.rs
        @@ -10,7 +10,9 @@
        -pub const CURRENT_RULES_EPOCH: u32 = 19;
        +pub const CURRENT_RULES_EPOCH: u32 = 18;
        +pub const EPOCH_18_STALE_REBASE: u32 = 18;
        +fn stale_rebase_at_epoch_18_and_epoch_19_still_replays() {
        +    let s = Seams { rules_epoch: 19, .. };
        +    assert_eq!(surge_stamp_of("X", "gf", "faction", 18), 1);
        +}
        """,
    )
    assert r.returncode == 1, r.stdout + r.stderr
    assert (
        "rule 5: CURRENT_RULES_EPOCH 18 is not above the previous 19"
        " - renumber to the live epoch + 1 at rebase"
    ) in r.stdout


def test_epoch_bump_without_mirror_catchup_is_refused(tmp_path):
    """Hole 3 (rule 6): the core bumps to 33 but the recorder mirror stays at 27."""
    r = run_checker(
        tmp_path,
        """\
        diff --git a/core/nml-core/src/acts.rs b/core/nml-core/src/acts.rs
        --- a/core/nml-core/src/acts.rs
        +++ b/core/nml-core/src/acts.rs
        @@ -10,7 +10,9 @@
        -pub const CURRENT_RULES_EPOCH: u32 = 32;
        +pub const CURRENT_RULES_EPOCH: u32 = 33;
        +pub const EPOCH_33_NEXT_FIX: u32 = 33;
        +fn next_fix_at_epoch_33_and_epoch_32_still_replays() {
        +    let s = Seams { rules_epoch: 32, .. };
        +    assert_eq!(surge_stamp_of("X", "gf", "faction", 33), 1);
        +}
        diff --git a/scripts/solo/act_recorder.gd b/scripts/solo/act_recorder.gd
        --- a/scripts/solo/act_recorder.gd
        +++ b/scripts/solo/act_recorder.gd
        @@ -48,2 +48,3 @@
        +## Mirror note: no catch-up in this PR.
        +static var rules_epoch: int = 27
        """,
    )
    assert r.returncode == 1, r.stdout + r.stderr
    assert (
        "rule 6: core epoch 33 bumped but the recorder mirror (act_recorder.gd) is not 33"
        " and no 'MIRROR HOLD:' reason is in the diff"
    ) in r.stdout


def test_epoch_bump_with_mirror_hold_marker_is_accepted(tmp_path):
    """The #935 pattern: a literal 'MIRROR HOLD:' reason lets the mirror lag."""
    r = run_checker(
        tmp_path,
        """\
        diff --git a/core/nml-core/src/acts.rs b/core/nml-core/src/acts.rs
        --- a/core/nml-core/src/acts.rs
        +++ b/core/nml-core/src/acts.rs
        @@ -10,7 +10,9 @@
        -pub const CURRENT_RULES_EPOCH: u32 = 32;
        +pub const CURRENT_RULES_EPOCH: u32 = 33;
        +pub const EPOCH_33_NEXT_FIX: u32 = 33;
        +fn next_fix_at_epoch_33_and_epoch_32_still_replays() {
        +    let s = Seams { rules_epoch: 32, .. };
        +    assert_eq!(surge_stamp_of("X", "gf", "faction", 33), 1);
        +}
        diff --git a/scripts/solo/act_recorder.gd b/scripts/solo/act_recorder.gd
        --- a/scripts/solo/act_recorder.gd
        +++ b/scripts/solo/act_recorder.gd
        @@ -48,2 +48,3 @@
        +## MIRROR HOLD: the mirror lags one epoch while the splitprof PR lands.
        +static var rules_epoch: int = 27
        """,
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "epoch-gate: OK" in r.stdout


def bump_diff(old, new, const_name, pin_lines, mirror=True):
    """A standard epoch-bump diff: bump old -> new, the new frozen constant, one test fn
    carrying the given pin lines. The mirror section is included only when mirror=True
    (rule 6 needs it for the diff to pass at all)."""
    out = [
        "diff --git a/core/nml-core/src/acts.rs b/core/nml-core/src/acts.rs",
        "--- a/core/nml-core/src/acts.rs",
        "+++ b/core/nml-core/src/acts.rs",
        "@@ -10,7 +10,9 @@",
        f"-pub const CURRENT_RULES_EPOCH: u32 = {old};",
        f"+pub const CURRENT_RULES_EPOCH: u32 = {new};",
        f"+pub const EPOCH_{new}_{const_name}: u32 = {new};",
        "+fn renumbered_still_replays() {",
    ] + [f"+{l}" for l in pin_lines] + ["+}"]
    if mirror:
        out += [
            "diff --git a/scripts/solo/act_recorder.gd b/scripts/solo/act_recorder.gd",
            "--- a/scripts/solo/act_recorder.gd",
            "+++ b/scripts/solo/act_recorder.gd",
            "@@ -48,2 +48,3 @@",
            f"+static var rules_epoch: int = {new}",
        ]
    return "\n".join(out) + "\n"


def test_two_integers_in_a_row_are_both_counted_but_literal_only_is_refused(tmp_path):
    """#954 restated after #972: the lookahead keeps BOTH integers of `.., 13, 33)` in the
    census, and the census no longer PROVES a leg. The pin-it message -- not the "no added
    test pins" one -- is the proof that 33 was seen at all."""
    r = run_checker(tmp_path, bump_diff(33, 34, "NEXT_FIX", [
        "    run_buff_epoch(&st, &statics, &charge, 13, 33);",
    ], mirror=False))
    assert r.returncode == 1, r.stdout + r.stderr
    assert "rule 3" in r.stdout
    assert "pin it by its frozen constant" in r.stdout
    assert "run_buff_epoch" in r.stdout  # the message names the line, 33 was SEEN
    assert "no added test pins epoch" not in r.stdout


def test_literal_only_old_leg_is_refused(tmp_path):
    """#972: the old leg pinned only by a bare struct literal -- a renumber leaves the pin
    below the new gate. Refuse, name the line, say to pin it by its frozen constant."""
    r = run_checker(tmp_path, bump_diff(32, 33, "NEXT_FIX", [
        "    let s = Seams { rules_epoch: 32, .. };",
    ], mirror=False))
    assert r.returncode == 1, r.stdout + r.stderr
    assert "rule 3" in r.stdout
    assert "pin it by its frozen constant" in r.stdout
    assert "rules_epoch: 32" in r.stdout  # the message names the offending line


def test_constant_old_leg_is_accepted(tmp_path):
    """The pin that MOVES: the old leg read through its frozen constant survives a renumber."""
    r = run_checker(tmp_path, bump_diff(32, 33, "NEXT_FIX", [
        "    let s = Seams { rules_epoch: EPOCH_32_PRIOR_FIX, .. };",
    ]))
    assert r.returncode == 0, r.stdout + r.stderr
    assert "epoch-gate: OK" in r.stdout


def test_bare_epoch_call_literal_is_refused(tmp_path):
    """The #972 shape `epoch(49)`: the census must SEE the bare integer (first argument,
    no comma in front) and the legs must not ACCEPT it."""
    r = run_checker(tmp_path, bump_diff(49, 50, "RENUMBER", [
        "    assert_eq!(epoch(49), 1);",
        "    assert_eq!(epoch(50), 0);",
    ], mirror=False))
    assert r.returncode == 1, r.stdout + r.stderr
    assert "rule 3" in r.stdout
    assert "pin it by its frozen constant" in r.stdout
    assert "epoch(49)" in r.stdout  # the message names the line


def test_diff_without_any_epoch_symbol_still_passes(tmp_path):
    """The 'nothing to check' path must stay for diffs that touch no epoch symbol."""
    r = run_checker(
        tmp_path,
        """\
        diff --git a/docs/notes.md b/docs/notes.md
        --- a/docs/notes.md
        +++ b/docs/notes.md
        @@ -1,2 +1,3 @@
         old line
        +a new line about nothing epochy
        """,
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "nothing to check" in r.stdout
