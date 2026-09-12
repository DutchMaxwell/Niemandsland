#!/usr/bin/env bash
# clippy_gate.sh -- "no NEW clippy findings" gate for the core workspace.
#
# Why not `cargo clippy -- -D warnings`: measured 12.09.2026 on main b17b1501,
# the workspace emits 254 findings, two of them at deny level. One of those two
# asks for `deployment.rs`'s `0.70710678` to become `FRAC_1_SQRT_2` -- a DIFFERENT
# value. That literal deliberately mirrors the table's own constant, so the
# "fix" would move position-parity numbers. A blanket hard gate would push every
# agent toward exactly that class of well-meant, parity-breaking edit.
#
# So the gate is differential: it counts findings per lint code and fails only
# when a code's count RISES or a new code appears. Dropping counts are fine and
# are reported, so the baseline can be tightened deliberately.
#
# Usage:
#   tools/clippy_gate.sh            # compare against tools/clippy_baseline.txt
#   tools/clippy_gate.sh --record   # rewrite the baseline (deliberate act)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# A non-login shell (hook, CI step, detached wrapper) does NOT source the
# profile, so ~/.cargo/bin can be off PATH and a bare `cargo` is "command not
# found". Resolve it once, loudly.
CARGO="${CARGO:-$(command -v cargo || echo "$HOME/.cargo/bin/cargo")}"
[ -x "$CARGO" ] || { echo "clippy_gate: no cargo binary (looked at: $CARGO)"; exit 1; }
BASE="$ROOT/tools/clippy_baseline.txt"
MODE="${1:-check}"

cd "$ROOT/core" || { echo "clippy_gate: no core/ workspace"; exit 1; }

# cargo only re-emits diagnostics for crates it actually re-checks. On a warm
# target dir a second run prints NOTHING, which would look like "zero findings"
# -- the failure mode this gate exists to catch. Discard just the workspace
# members' artifacts (dependencies stay cached, so this costs seconds, not a
# full rebuild) and measure from a known state every time.
"$CARGO" clean -p nml-core -p nml-core-godot -p nml-core-py >/dev/null 2>&1

# `approx_constant` and `erasing_op` are correctness-group lints, deny by
# default. Uncapped, clippy therefore hard-errors after the first crate and the
# measurement covers only what job scheduling happened to finish first: measured
# 12.09.2026, the same tree read 98 findings (lib target only) on one runner and
# 355 (lib+tests) on another. Cap lint levels for the measurement so every
# target compiles; the parser counts capped findings identically, and the exit
# status then means exactly one thing -- a real compile error.
raw=$(mktemp)
"$CARGO" clippy --workspace --all-targets --message-format json -- --cap-lints warn \
  >"$raw" 2>/dev/null
clippy_rc=$?
current=$(python3 -c '
import json,sys,collections
c=collections.Counter()
for line in sys.stdin:
    line=line.strip()
    if not line.startswith("{"): continue
    try: m=json.loads(line)
    except Exception: continue
    msg=m.get("message")
    if not isinstance(msg,dict): continue
    if msg.get("level") not in ("warning","error"): continue
    code=(msg.get("code") or {}).get("code")
    if not code: continue
    c[code]+=1
for k in sorted(c): print(f"{k} {c[k]}")
' <"$raw")
rm -f "$raw"

# The JSON parser above sees whatever cargo managed to emit, so a failed clippy
# run yields a partial count -- which can only ever look BETTER than the truth.
# Refuse instead of comparing it.
if [ "$clippy_rc" -ne 0 ]; then
  echo "clippy_gate: cargo clippy exited $clippy_rc -- the workspace did not compile"
  echo "clippy_gate: cleanly, so the diagnostics are a partial measurement."
  echo "clippy_gate: refusing to compare."
  exit 1
fi

if [ -z "$current" ]; then
  echo "clippy_gate: clippy produced no parsable findings -- the INSTRUMENT is broken, not the code."
  echo "clippy_gate: refusing to pass on an empty measurement."
  exit 1
fi

if [ "$MODE" = "--record" ]; then
  printf '# clippy findings per lint code on this commit. Regenerate deliberately:\n#   tools/clippy_gate.sh --record\n%s\n' "$current" > "$BASE"
  echo "clippy_gate: baseline recorded ($(echo "$current" | wc -l) lint codes)"
  exit 0
fi

[ -f "$BASE" ] || { echo "clippy_gate: no baseline at $BASE -- run tools/clippy_gate.sh --record"; exit 1; }

python3 - "$BASE" <<PYEOF
import sys
base={}
for line in open(sys.argv[1]):
    line=line.strip()
    if not line or line.startswith("#"): continue
    k,v=line.rsplit(" ",1); base[k]=int(v)
cur={}
for line in """$current""".strip().split("\n"):
    k,v=line.rsplit(" ",1); cur[k]=int(v)
# A total that collapsed relative to the baseline cannot be a real cleanup of
# this size -- it means clippy measured only part of the workspace (warm target,
# aborted run). Counts can only go up from a partial read, never down, so a
# large drop is the one shape that can silently hide new findings.
btot=sum(base.values()); ctot=sum(cur.values())
if ctot * 10 < btot * 9:
    print(f"clippy_gate: measurement suspiciously small: {ctot} findings vs {btot} baseline")
    print("clippy_gate: (warm target/incomplete clippy run) -- re-run with a clean target dir,")
    print("clippy_gate: or --record if the drop is deliberate")
    sys.exit(3)
bad=[]
for k,v in sorted(cur.items()):
    b=base.get(k,0)
    if v>b: bad.append(f"  {k}: {b} -> {v}  (+{v-b})")
for k,v in sorted(base.items()):
    c=cur.get(k,0)
    if c<v: print(f"  improved: {k}: {v} -> {c}")
if bad:
    print("clippy_gate: NEW findings")
    print("\n".join(bad))
    print("Fix them, or -- if a finding is a false alarm on parity-critical code --")
    print("silence it locally with #[allow(...)] AND a comment saying why.")
    sys.exit(2)
print(f"clippy_gate: PASS ({sum(cur.values())} findings across {len(cur)} lint codes, none new)")
PYEOF
