#!/usr/bin/env bash
# test_private_access_gate.sh -- "test accesses to main.gd privates may only fall" gate.
#
# Why: on 23.11.2026 457 test files made 3,733 accesses to main.gd private
# members (`_main._...`). Every extraction out of main.gd (26k lines) breaks
# those tests although no behaviour changes. The intended door is the test
# facade under test/support/, which is excluded from this count. This gate
# counts the remaining direct accesses per member and fails only when a
# member's count RISES or a new member appears. Drops are fine and are
# printed, so the baseline can be tightened deliberately.
#
# Usage:
#   tools/test_private_access_gate.sh            # compare against the baseline
#   tools/test_private_access_gate.sh --record   # rewrite the baseline
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT/tools/test_private_access_baseline.txt"
MODE="${1:-check}"
PATTERN='_main\._[a-z][a-z0-9_]*'

cd "$ROOT" || { echo "test_private_access_gate: cannot enter the repo root"; exit 1; }

# git grep walks tracked files only, which is what the baseline records.
# `sed 's/.*:_main\.//'` strips the "path:" prefix and the `_main.` stem; the
# match itself cannot contain a colon, so the greedy strip is safe.
raw=$(mktemp)
git grep -o -E "$PATTERN" -- 'test/' ':!test/support/' >"$raw" 2>/dev/null
grep_rc=$?
if [ "$grep_rc" -gt 1 ]; then
  rm -f "$raw"
  echo "test_private_access_gate: git grep failed (exit $grep_rc) -- the instrument is broken."
  exit 1
fi
current=$(sed 's/.*:_main\.//' "$raw" | sort | uniq -c | awk '{print $2 " " $1}' | sort)
rm -f "$raw"

if [ -z "$current" ]; then
  echo "test_private_access_gate: no accesses measured -- the instrument is broken, not the code."
  echo "test_private_access_gate: refusing to pass on an empty measurement."
  exit 1
fi

if [ "$MODE" = "--record" ]; then
  {
    printf '# Test accesses to main.gd private members: one "name count" per line, sorted.\n'
    printf '# Only files under test/ count; test/support/ is the intended facade and is excluded.\n'
    printf '# Regenerate deliberately after a migration lowers the counts:\n'
    printf '#   tools/test_private_access_gate.sh --record\n'
    printf '%s\n' "$current"
  } > "$BASE"
  echo "test_private_access_gate: baseline recorded ($(printf '%s\n' "$current" | wc -l) members)"
  exit 0
fi

[ -f "$BASE" ] || { echo "test_private_access_gate: no baseline at $BASE -- run tools/test_private_access_gate.sh --record"; exit 1; }

CURRENT="$current" python3 - "$BASE" <<'PYEOF'
import os, sys

base = {}
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    name, count = line.rsplit(" ", 1)
    base[name] = int(count)

cur = {}
for line in os.environ.get("CURRENT", "").splitlines():
    line = line.strip()
    if not line:
        continue
    name, count = line.rsplit(" ", 1)
    cur[name] = int(count)

btot = sum(base.values())
ctot = sum(cur.values())
# A total that halved in one change cannot be a real cleanup of this size; it
# means the measurement lost files (pathspec no longer matching, sparse
# checkout). Counts can only fall through a partial read, so a large drop is
# the one shape that can silently hide new accesses.
if ctot * 2 < btot:
    print(f"test_private_access_gate: measurement suspiciously small: {ctot} accesses vs {btot} baseline")
    print("test_private_access_gate: (pathspec/checkout problem?) re-run, or --record if deliberate")
    sys.exit(1)

bad = []
for name, count in sorted(cur.items()):
    b = base.get(name, 0)
    if count > b:
        bad.append(f"  {name}: {b} -> {count}  (+{count - b})")
for name, count in sorted(base.items()):
    c = cur.get(name, 0)
    if c < count:
        print(f"  improved: {name}: {count} -> {c}")

if bad:
    print("test_private_access_gate: NEW test accesses to main.gd private members")
    print("\n".join(bad))
    print("Route the setup through test/support/ instead of writing main.gd's privates,")
    print("or -- if the access is a genuine one-off -- lower the baseline deliberately.")
    sys.exit(1)

print(f"test_private_access_gate: PASS ({ctot} accesses across {len(cur)} members, none new)")
PYEOF
