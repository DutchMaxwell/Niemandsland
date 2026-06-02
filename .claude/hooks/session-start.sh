#!/bin/bash
# =============================================================================
# Niemandsland — SessionStart hook for Claude Code on the web
# =============================================================================
# Provisions the ephemeral web container so code can be validated without a
# local machine:
#   1. Godot 4.6 (headless)          -> compile-check + gdUnit4 tests (test/)
#   2. Python test dependencies      -> relay/ and tools/model_forge/ pytest
#   3. Project import                -> generates .godot/, doubles as a
#                                       GDScript compile-check
#
# Mirrors .github/workflows/build.yml (same Godot version + test invocation).
# Runs ONLY in the remote web environment; local setups are left untouched.
# Safe to run repeatedly (idempotent); heavy state is cached between sessions.
#
# Runs ASYNCHRONOUSLY: the session opens immediately while this provisions in
# the background. Trade-off — on a cold container Godot/tests may not be ready
# the instant the session starts (the first cold import takes a few minutes).
# =============================================================================
set -euo pipefail

# --- Resolve harness vars with fallbacks so the script also runs by hand -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
ENV_FILE="${CLAUDE_ENV_FILE:-/dev/null}"

# Only provision the remote web environment; the user's laptop already has Godot.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Run in the background so the session starts immediately. Must be the first
# line written to stdout. Timeout is generous to cover a cold first import.
echo '{"async": true, "asyncTimeout": 900000}'

GODOT_VERSION="4.6-stable"
GODOT_HOME="$HOME/.local/share/godot"
GODOT_BIN="$GODOT_HOME/godot"
GODOT_ASSET="Godot_v${GODOT_VERSION}_linux.x86_64"
GODOT_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${GODOT_ASSET}.zip"

echo "[niemandsland-hook] Provisioning web environment ..."

# === 1. Godot 4.6 headless (idempotent) ======================================
if [ ! -x "$GODOT_BIN" ]; then
  echo "[niemandsland-hook] Downloading Godot ${GODOT_VERSION} ..."
  mkdir -p "$GODOT_HOME"
  tmp_zip="$(mktemp "${TMPDIR:-/tmp}/godot.XXXXXX.zip")"
  curl -fL --retry 4 --retry-delay 2 -o "$tmp_zip" "$GODOT_URL"
  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "$tmp_zip" -d "$GODOT_HOME"
  else
    python3 -m zipfile -e "$tmp_zip" "$GODOT_HOME"
  fi
  rm -f "$tmp_zip"
  extracted="$(find "$GODOT_HOME" -maxdepth 1 -type f -name 'Godot_v*_linux.x86_64' | head -1)"
  if [ -z "$extracted" ]; then
    echo "[niemandsland-hook] ERROR: Godot binary not found after extraction." >&2
    exit 1
  fi
  mv -f "$extracted" "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
  echo "[niemandsland-hook] Installed Godot to $GODOT_BIN"
else
  echo "[niemandsland-hook] Godot already present at $GODOT_BIN"
fi

# Persist for the session: GODOT_BIN is read by addons/gdUnit4/runtest.sh,
# PATH puts `godot` on the command line.
{
  echo "export GODOT_BIN=\"$GODOT_BIN\""
  echo "export PATH=\"$GODOT_HOME:\$PATH\""
} >> "$ENV_FILE"
export PATH="$GODOT_HOME:$PATH"
export GODOT_BIN

"$GODOT_BIN" --version || true

# === 2. Python test dependencies =============================================
PIP_OPTS=(--quiet --root-user-action=ignore)

# relay/ tests are lightweight and required (websockets + pytest-asyncio).
echo "[niemandsland-hook] Installing relay/ test dependencies ..."
python3 -m pip install "${PIP_OPTS[@]}" pytest pytest-asyncio -r "$PROJECT_DIR/relay/requirements.txt"

# tools/model_forge/ tests pull heavier libs in via their source modules
# (image_generator -> google-genai, gradio_client; prompt_engine -> pyyaml;
#  glb_optimizer -> Pillow). Best-effort: never block setup on these.
echo "[niemandsland-hook] Installing model_forge test dependencies (best-effort) ..."
python3 -m pip install "${PIP_OPTS[@]}" pyyaml Pillow google-genai gradio_client \
  || echo "[niemandsland-hook] WARN: could not install all model_forge test deps."
# The base image ships cffi without its compiled backend, which breaks
# 'from google import genai'. Repair only when needed (idempotent).
python3 -c "import _cffi_backend" 2>/dev/null \
  || python3 -m pip install "${PIP_OPTS[@]}" --force-reinstall --no-cache-dir cffi \
  || echo "[niemandsland-hook] WARN: cffi repair failed; image_generator tests may not collect."

# === 3. Import project — generates .godot/, doubles as GDScript compile-check =
# Mirrors build.yml. Bounded so a stuck import cannot stall session start, and
# non-fatal (|| true) exactly like CI. Output goes to a log to keep the session
# context clean; only parse errors are surfaced.
echo "[niemandsland-hook] Importing project (this is slow on a cold container) ..."
import_log="${TMPDIR:-/tmp}/niemandsland-godot-import.log"
timeout 900 "$GODOT_BIN" --headless --editor --quit --path "$PROJECT_DIR" >"$import_log" 2>&1 || true
if grep -qiE "SCRIPT ERROR|Parse Error|Failed to load script" "$import_log"; then
  echo "[niemandsland-hook] WARN: GDScript parse errors during import (see $import_log):"
  grep -iE "SCRIPT ERROR|Parse Error|Failed to load script" "$import_log" | head -20
else
  echo "[niemandsland-hook] Project import complete (no GDScript parse errors)."
fi

# === Done ====================================================================
echo "[niemandsland-hook] Ready. Useful commands:"
echo "  GDScript tests : \"\$GODOT_BIN\" --headless --path \"$PROJECT_DIR\" \\"
echo "                     -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \\"
echo "                     --ignoreHeadlessMode -a res://test"
echo "  relay tests    : python3 -m pytest relay/"
echo "  model_forge    : python3 -m pytest tools/model_forge/tests/"
