#!/usr/bin/env python3
"""Refuse a rules PR that bumps the epoch without proving BOTH legs of its gate.

An epoch gate exists so that every already recorded game replays unchanged. A PR that bumps
`CURRENT_RULES_EPOCH` and tests only the NEW behaviour has proved half of that and asserted the
other half. Until 2026-09-14 the lead read every such PR by hand; this is that reading, mechanised.

Rules enforced, all derived from incidents in this repo:
  1. A bump must introduce a NEW frozen constant `EPOCH_<n>_<NAME> = <n>` matching the new epoch.
     (Without it, gates get written against the moving symbol -- see rule 2.)
  2. No NEW gate may read `rule_on(<x>, CURRENT_RULES_EPOCH)`. That symbol moves with the next
     bump, silently re-dating every gate written against it; it cost this repo an incident at
     epoch 4 and a repeat on 2026-09-13 (#921), and `acts.rs` has said so since #928.
  3. The diff must add at least one test that pins the OLD epoch (`<n-1>` or lower), so the
      pre-bump behaviour is asserted and not merely hoped for. Since #972 the pin must MOVE
      with a renumber: only the frozen constant or a test name carrying the epoch proves
      the leg; a bare literal (`rules_epoch: 12`, `epoch(49)`) still counts in the census
      but the #972 renumber left such pins silently running below the new gate.
   4. Same for the NEW leg: pin by constant or test name; a bare literal is refused alike.
   5. A diff that adds a NEW `EPOCH_<n>_<NAME>` constant WITHOUT bumping `CURRENT_RULES_EPOCH` is
      refused (reported as "rule 4") -- a rules fix landing below the live epoch gates nothing.
   6. `CURRENT_RULES_EPOCH` must move UP (reported as "rule 5") -- a stale rebase re-dates the gate.
   7. When the bump is to N, the GDScript recorder mirror `scripts/solo/act_recorder.gd` must set
      `static var rules_epoch: int = N` in the SAME diff (reported as "rule 6"), or the diff carries a
      literal `MIRROR HOLD:` reason (the #935 pattern). A core-only port that skips the mirror leaves
      table recordings stamping a stale epoch, which replays with every newer gate OFF (2026-09-14).


Usage: epoch_gate_check.py <diff-file>   (reads a unified diff; exit 1 on refusal)
"""
import re
import sys

CONST_RE = re.compile(r"^\+\s*pub const EPOCH_(\d+)_([A-Z0-9_]+)\s*:\s*u32\s*=\s*(\d+)\s*;")
CURRENT_RE = re.compile(r"^\+\s*pub const CURRENT_RULES_EPOCH\s*:\s*u32\s*=\s*(\d+)\s*;")
CURRENT_OLD_RE = re.compile(r"^-\s*pub const CURRENT_RULES_EPOCH\s*:\s*u32\s*=\s*(\d+)\s*;")
LIVE_GATE_RE = re.compile(r"^\+(?![^\n]*//).*rule_on\s*\([^,]+,\s*CURRENT_RULES_EPOCH\s*\)")
MIRROR_RE = re.compile(r"^\+\s*static var rules_epoch\s*:\s*int\s*=\s*(\d+)")
MIRROR_HOLD_RE = re.compile(r"MIRROR HOLD:\s*\S")


def epochs_pinned(added_lines, max_epoch):
    """Census of the epoch numbers the added lines pin, split by PIN FORM.

    Four forms occur in this repo, three of which a naive `rules_epoch: <n>` grep misses:
      a) struct literal   `Seams { rules_epoch: 12, .. }`             -> bare literal
      b) positional arg   `build_for(.., 12)`, `epoch(49)` first arg  -> bare literal
      c) the test's NAME  `..._at_epoch_12`, `..._below_epoch_17`     -> strong pin
      d) the frozen constant `EPOCH_<n>_<NAME>`                       -> strong pin
    A bare literal still COUNTS, but since #972 it no longer PROVES a leg: a renumber
    moves the gate and leaves the literal below it; only (c)/(d) move with the constant.
    Returns (strong, literal): epoch -> one naming line each. (b) counts only on plainly
    test-call lines, and the #954 lookahead keeps BOTH of two integers in a row.
    """
    strong = {}
    literal = {}
    for line in added_lines:
        low = line.lower()
        for m in re.finditer(r"rules_epoch\s*:\s*(\d+)", line):
            literal.setdefault(int(m.group(1)), line)
        for m in re.finditer(r"\bEPOCH_(\d+)_[A-Z0-9_]+", line):
            strong.setdefault(int(m.group(1)), line)
        for m in re.finditer(r"fn\s+[a-z0-9_]*epoch_?(\d+)[a-z0-9_]*\s*\(", low):
            strong.setdefault(int(m.group(1)), line)
        for m in re.finditer(r"fn\s+[a-z0-9_]*?(?:at|below|above|from)_(\d+)[a-z0-9_]*\s*\(", low):
            strong.setdefault(int(m.group(1)), line)
        # positional: a bare integer that could be an epoch, in a call, on a line that is
        # either in a test context or mentions epoch/build_for/stamp explicitly.
        if ("epoch" in low or "build_for" in low or "_of(" in low
                or "deploy_side" in low or "assert" in low or "let " in low):
            for m in re.finditer(r",\s*(\d+)\s*(?=[,)])", line):
                v = int(m.group(1))
                if 1 <= v <= max_epoch:
                    literal.setdefault(v, line)
            # the #972 shape `epoch(49)`: first argument, no comma in front of it.
            for m in re.finditer(r"\b[a-z0-9_]*epoch[a-z0-9_]*\s*\(\s*(\d+)\s*[,)]", low):
                v = int(m.group(1))
                if 1 <= v <= max_epoch:
                    literal.setdefault(v, line)
    return strong, literal


def main(path):
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    added = [l for l in lines if l.startswith("+") and not l.startswith("+++")]

    new_epoch = old_epoch = None
    for l in added:
        m = CURRENT_RE.match(l)
        if m:
            new_epoch = int(m.group(1))
    for l in lines:
        m = CURRENT_OLD_RE.match(l)
        if m:
            old_epoch = int(m.group(1))

    if new_epoch is None:
        if any(CONST_RE.match(l) for l in added):
            print("epoch-gate: REFUSED")
            print(
                "::error::epoch-gate: rule 4: a new EPOCH_<n> constant was added without bumping "
                "CURRENT_RULES_EPOCH - a rules fix landing below the live epoch gates nothing"
            )
            return 1
        print("epoch-gate: no CURRENT_RULES_EPOCH bump in this diff - nothing to check.")
        return 0
    print(f"epoch-gate: bump {old_epoch} -> {new_epoch}")

    fails = []

    if old_epoch is not None and new_epoch <= old_epoch:
        fails.append(
            f"rule 5: CURRENT_RULES_EPOCH {new_epoch} is not above the previous {old_epoch} - "
            "renumber to the live epoch + 1 at rebase"
        )

    mirrored = [int(m.group(1)) for m in (MIRROR_RE.match(l) for l in added) if m]
    held = any(MIRROR_HOLD_RE.search(l) for l in added)
    if new_epoch not in mirrored and not held:
        fails.append(
            f"rule 6: core epoch {new_epoch} bumped but the recorder mirror (act_recorder.gd) "
            f"is not {new_epoch} and no 'MIRROR HOLD:' reason is in the diff"
        )

    consts = {int(m.group(1)): m.group(3) for m in (CONST_RE.match(l) for l in added) if m}
    if new_epoch not in consts:
        fails.append(
            f"rule 1: no new `pub const EPOCH_{new_epoch}_<NAME>: u32 = {new_epoch};` was added. "
            "A gate needs a FROZEN constant of its own; gating against the moving symbol re-dates "
            "itself on the next bump."
        )
    elif consts[new_epoch] != str(new_epoch):
        fails.append(f"rule 1: EPOCH_{new_epoch}_* is defined as {consts[new_epoch]}, not {new_epoch}.")

    live = [l for l in added if LIVE_GATE_RE.match(l)]
    if live:
        fails.append(
            "rule 2: %d new gate(s) read `rule_on(.., CURRENT_RULES_EPOCH)`. Use the frozen "
            "EPOCH_<n>_<NAME> instead. First: %s" % (len(live), live[0].strip()[:110])
        )

    strong, literal = epochs_pinned(added, new_epoch)
    # Rule 3 asks for the epoch IMMEDIATELY below the bump, not "any small number". The loose
    # reading let every test file pass on an unrelated literal; all five rules PRs of 2026-09-13/14
    # pin their exact predecessor, so the tight reading is both correct and achievable.
    # Since #972 the pin must also MOVE with a renumber: a bare literal counts in the
    # census but proves nothing; only the frozen constant or the test name pins a leg.
    old_leg = {old_epoch} & set(strong) if old_epoch is not None else set()
    old_leg_literal = {old_epoch} & set(literal) if old_epoch is not None else set()
    new_leg = {e for e in strong if e >= new_epoch}
    new_leg_literal = {e for e in literal if e >= new_epoch}
    if not old_leg:
        if old_leg_literal:
            fails.append(
                f"rule 3: epoch {old_epoch} is pinned only by a bare literal "
                f"({literal[old_epoch].strip()[:110]}) -- a renumber silently leaves it below "
                f"the gate (#972), so pin it by its frozen constant (EPOCH_{old_epoch}_<NAME>) "
                "or name the test with the epoch."
            )
        else:
            fails.append(
                f"rule 3: no added test pins epoch {old_epoch}, the one immediately below the bump. "
                "The OLD leg is unproven, so nothing asserts that already recorded games still replay "
                "unchanged. Add a test that runs at {old} and asserts the PRE-bump outcome by value.".format(old=old_epoch)
            )
    if not new_leg and not any(f"EPOCH_{new_epoch}_" in l for l in added):
        if new_leg_literal:
            fails.append(
                f"rule 4: epoch {min(new_leg_literal)} is pinned only by a bare literal "
                f"({literal[min(new_leg_literal)].strip()[:110]}) -- a renumber silently leaves "
                f"it below the gate (#972), so pin it by its frozen constant "
                f"(EPOCH_{new_epoch}_<NAME>) or name the test with the epoch."
            )
        else:
            fails.append(f"rule 4: no added test pins epoch {new_epoch} or its constant.")

    if fails:
        print("epoch-gate: REFUSED")
        for f in fails:
            print(f"::error::epoch-gate: {f}")
        return 1
    print(f"epoch-gate: OK - old leg pinned at {sorted(old_leg)}, new leg at {sorted(new_leg) or 'constant'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
