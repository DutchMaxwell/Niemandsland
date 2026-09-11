#!/usr/bin/env bash
# NML-1073 R1 — install the GDExtension manifest only when a library exists.
# Run this after the core build, e.g.
#   cargo build --release --manifest-path core/nml-core-godot/Cargo.toml
#   cargo build --release --target x86_64-pc-windows-gnu --manifest-path core/nml-core-godot/Cargo.toml
#
# SO_PATH / DLL_PATH are the library entries of core/nml_core.gdextension.in —
# keep them in sync by hand if those entries ever change.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SO_PATH="target/release/libnml_core_godot.so"
DLL_PATH="target/x86_64-pc-windows-gnu/release/nml_core_godot.dll"

# NML-1073 M2-5: a build with CARGO_TARGET_DIR set (the shared cache the
# milestone builds with) leaves the linux library outside core/target (F7). The
# manifest can only name ONE res:// path, so the library is copied to the path
# it names instead of the manifest learning a second one.
if [[ -n "${CARGO_TARGET_DIR:-}" && -f "$CARGO_TARGET_DIR/release/libnml_core_godot.so" ]]; then
	mkdir -p "$(dirname "$SO_PATH")"
	cp -u "$CARGO_TARGET_DIR/release/libnml_core_godot.so" "$SO_PATH"
	echo "nml_core: library copied from CARGO_TARGET_DIR"
fi

if [[ -f "$SO_PATH" || -f "$DLL_PATH" ]]; then
	cp nml_core.gdextension.in nml_core.gdextension
	echo "nml_core: library found — extension installed"
else
	rm -f nml_core.gdextension
	echo "nml_core: library not built — extension not installed (GDScript fallback)"
fi
