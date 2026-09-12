#!/usr/bin/env bash
# post_edit_gate.sh -- the verification a PostToolUse hook runs after every file edit.
#
# Reads the hook payload on stdin, picks the edited path, and runs the cheapest
# check that can actually fail for that file type. Measured 12.09.2026 on this
# repo: Godot project check ~1 s, warm `cargo check` ~1 s. Anything slower than
# that belongs in CI, not on the edit path.
#
# Exit 0 = nothing to say. Exit 2 = blocking error, message on stdout.
#
# GDScript: the check is the PROJECT-wide load, not `--check-only --script <file>`.
#   Measured: the per-file form reports "Identifier not found: GraphicsSettings"
#   on a healthy file (autoloads are not loaded for a single script) AND exits 0
#   while doing so -- a false alarm and a silent pass in one. The project load
#   sees autoloads, and a deliberate syntax error in an autoload produced two
#   error lines (RED proven), so this form can fail.
#   Godot reports in the system locale: match the German strings too.
#
# Rust: `cargo check --workspace` over the three core crates. Absolute path to
#   cargo -- a hook shell is non-login and does not source the profile, so a
#   bare `cargo` is "command not found" (and a check that cannot run is a check
#   that always passes).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-$HOME/bin/godot}"
CARGO="${CARGO:-$(command -v cargo || echo "$HOME/.cargo/bin/cargo")}"

payload="$(cat)"
file="$(printf '%s' "$payload" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); raise SystemExit
ti=d.get("tool_input") or {}
tr=d.get("tool_response") or {}
p=tr.get("filePath") or ti.get("file_path") or ""
print(p if isinstance(p,str) else "")' 2>/dev/null)"
[ -n "$file" ] || exit 0

case "$file" in
  *.gd)
    [ -x "$GODOT" ] || { echo "post_edit_gate: godot not at $GODOT -- GDScript unchecked"; exit 0; }
    out="$(cd "$ROOT" && timeout 120 "$GODOT" --headless --quit --path . 2>&1 \
            | grep -iE "SCRIPT ERROR|Parse Error|Compile Error|Skript-?fehler|Parser-?Fehler")"
    if [ -n "$out" ]; then
      echo "post_edit_gate: the Godot project no longer loads cleanly after editing $file"
      printf '%s\n' "$out" | head -20
      exit 2
    fi
    ;;
  *.rs)
    case "$file" in *"/core/"*) ;; *) exit 0 ;; esac
    [ -x "$CARGO" ] || { echo "post_edit_gate: cargo not at $CARGO -- Rust unchecked"; exit 0; }
    out="$(cd "$ROOT/core" && CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/nml-check}" \
            timeout 300 "$CARGO" check --workspace --offline --message-format short 2>&1 \
            | grep -E "^[^ ]+: error|^error(\[|:)")"
    if [ -n "$out" ]; then
      echo "post_edit_gate: the core workspace no longer compiles after editing $file"
      printf '%s\n' "$out" | head -20
      exit 2
    fi
    ;;
esac
exit 0
