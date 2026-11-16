#!/usr/bin/env bash
# Linux twin of export-macos' proof bundle (build.yml): an EXPORTED Linux build must play the shipped net.
# An export template ignores `-s <script>` and a scene argument, so this makes a SECOND export whose main scene
# is tools/core_ship_probe.tscn (executable and library must equal the shipping ones), runs it headless and lets
# tools/assert_ship_probe.py judge the log. Run from the repo root after the import; it edits project.godot.
# Usage: tools/ci/linux_ship_probe.sh <shipping export dir>
set -euo pipefail
SHIP="${1:?usage: linux_ship_probe.sh <shipping export dir>}"
PROBE=build/linux-probe
mkdir -p "$PROBE" build/logs
sed -i 's|^run/main_scene=.*|run/main_scene="res://tools/core_ship_probe.tscn"|' project.godot
grep -n '^run/main_scene' project.godot
godot --headless --verbose --export-release "Linux" "$PROBE/$EXPORT_NAME.x86_64"
cmp "$SHIP/$EXPORT_NAME.x86_64" "$PROBE/$EXPORT_NAME.x86_64"
cmp "$SHIP/libnml_core_godot.so" "$PROBE/libnml_core_godot.so"
echo "OK: the proof build carries the shipping build's executable and library byte for byte"
RC=0
timeout 300 "$PROBE/$EXPORT_NAME.x86_64" --headless > build/logs/probe_linux.log 2>&1 || RC=$?
echo "probe exit code: $RC"
cat build/logs/probe_linux.log
python3 tools/assert_ship_probe.py build/logs/probe_linux.log --os Linux --arch x86_64 --exit-code "$RC"
