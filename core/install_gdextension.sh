#!/usr/bin/env bash
# NML-1073 R1 — install the GDExtension manifest only when its library exists.
# Run this after `cargo build --release --manifest-path core/nml-core-godot/Cargo.toml`.
#
# LIB_PATH is the linux.x86_64 entry of core/nml_core.gdextension.in — keep the
# two in sync by hand if that entry ever changes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

LIB_PATH="nml-core-godot/target/release/libnml_core_godot.so"

# NML-1073 M2-5: a build with CARGO_TARGET_DIR set (the shared cache the
# milestone builds with) leaves the library outside the crate. The manifest can
# only name ONE res:// path, so the library is copied to the path it names
# instead of the manifest learning a second one.
if [[ -n "${CARGO_TARGET_DIR:-}" && -f "$CARGO_TARGET_DIR/release/libnml_core_godot.so" ]]; then
	mkdir -p "$(dirname "$LIB_PATH")"
	cp -u "$CARGO_TARGET_DIR/release/libnml_core_godot.so" "$LIB_PATH"
	echo "nml_core: library copied from CARGO_TARGET_DIR"
fi

if [[ -f "$LIB_PATH" ]]; then
	cp nml_core.gdextension.in nml_core.gdextension
	echo "nml_core: library found — extension installed"
else
	rm -f nml_core.gdextension
	echo "nml_core: library not built — extension not installed (GDScript fallback)"
fi
