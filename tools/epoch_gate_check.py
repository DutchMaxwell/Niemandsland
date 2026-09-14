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
     pre-bump behaviour is asserted and not merely hoped for. Both the struct-literal form
     (`rules_epoch: 12`) and the positional form (`build_for(.., 12)`) count -- the lead's own
     grep missed the positional form once and dispatched an agent to build tests that existed.
  4. The diff must add at least one test that pins the NEW epoch, by constant or by number.

Usage: epoch_gate_check.py <diff-file>   (reads a unified diff; exit 1 on refusal)
"""
import re
import sys

CONST_RE = re.compile(r"^\+\s*pub const EPOCH_(\d+)_([A-Z0-9_]+)\s*:\s*u32\s*=\s*(\d+)\s*;")
CURRENT_RE = re.compile(r"^\+\s*pub const CURRENT_RULES_EPOCH\s*:\s*u32\s*=\s*(\d+)\s*;")
CURRENT_OLD_RE = re.compile(r"^-\s*pub const CURRENT_RULES_EPOCH\s*:\s*u32\s*=\s*(\d+)\s*;")
LIVE_GATE_RE = re.compile(r"^\+(?![^\n]*//).*rule_on\s*\([^,]+,\s*CURRENT_RULES_EPOCH\s*\)")


def epochs_pinned(added_lines, max_epoch):
    """Every epoch number the added lines pin.

    Four forms, all of which occur in this repo and three of which a naive
    `rules_epoch: <n>` grep misses -- the lead's own grep missed the positional one on
    2026-09-14 and dispatched an agent to write tests that already existed:
      a) struct literal   `Seams { rules_epoch: 12, .. }`
      b) positional arg   `build_for(&mut reg, p, 12)`, `deploy_side(.., 7, 15)`,
                          `surge_stamp_of("X", "gf", "faction", 16)`
      c) the test's NAME  `at_epoch_12_...`, `..._below_epoch_17`, `..._epoch_15_still_...`
      d) the frozen constant `EPOCH_<n>_<NAME>`
    (b) is only counted on lines that are plainly test calls, to keep dice counts and board
    coordinates out of the result.
    """
    out = set()
    for line in added_lines:
        low = line.lower()
        for m in re.finditer(r"rules_epoch\s*:\s*(\d+)", line):
            out.add(int(m.group(1)))
        for m in re.finditer(r"\bEPOCH_(\d+)_[A-Z0-9_]+", line):
            out.add(int(m.group(1)))
        for m in re.finditer(r"fn\s+[a-z0-9_]*epoch_?(\d+)[a-z0-9_]*\s*\(", low):
            out.add(int(m.group(1)))
        for m in re.finditer(r"fn\s+[a-z0-9_]*?(?:at|below|above|from)_(\d+)[a-z0-9_]*\s*\(", low):
            out.add(int(m.group(1)))
        # positional: a bare integer that could be an epoch, in a call, on a line that is
        # either in a test context or mentions epoch/build_for/stamp explicitly.
        if ("epoch" in low or "build_for" in low or "_of(" in low
                or "deploy_side" in low or "assert" in low or "let " in low):
            for m in re.finditer(r",\s*(\d+)\s*[,)]", line):
                v = int(m.group(1))
                if 1 <= v <= max_epoch:
                    out.add(v)
    return out


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
        print("epoch-gate: no CURRENT_RULES_EPOCH bump in this diff - nothing to check.")
        return 0
    print(f"epoch-gate: bump {old_epoch} -> {new_epoch}")

    fails = []

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

    pinned = epochs_pinned(added, new_epoch)
    # Rule 3 asks for the epoch IMMEDIATELY below the bump, not "any small number". The loose
    # reading let every test file pass on an unrelated literal; all five rules PRs of 2026-09-13/14
    # pin their exact predecessor, so the tight reading is both correct and achievable.
    old_leg = {old_epoch} & pinned if old_epoch is not None else set()
    new_leg = {e for e in pinned if e >= new_epoch}
    if not old_leg:
        fails.append(
            f"rule 3: no added test pins epoch {old_epoch}, the one immediately below the bump. "
            "The OLD leg is unproven, so nothing asserts that already recorded games still replay "
            "unchanged. Add a test that runs at {old} and asserts the PRE-bump outcome by value.".format(old=old_epoch)
        )
    if not new_leg and not any(f"EPOCH_{new_epoch}_" in l for l in added):
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
