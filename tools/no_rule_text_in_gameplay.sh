#!/usr/bin/env bash
# NML-1115: OPR rule TEXT must never reach a gameplay decision again.
#
# Rule descriptions arrive from the live Army Forge API at import time. The Godot-free
# trainer (core/nml-core-py) and the Rust core have none of them, and no recording pins
# which text produced a reading — so anything that turns prose into a die, a distance or a
# decision is a silent table/trainer split, and an upstream book edit changes what the
# table plays with no commit of ours. Gameplay reads the mechanics registry instead
# (assets/solo/rules_mechanics_<system>.json: rule NAMES + our own primitives/params).
#
# DISPLAY consumers stay allowed and are deliberately not checked: unit_dock, unit_card,
# casts_dialog, the buff-token palette, and the save/network carriers all show or ship the
# same texts without deciding anything. equipment_distributor.gd likewise only PACKAGES a
# unit's effective descriptions into unit_properties for those consumers.
#
# Run locally: bash tools/no_rule_text_in_gameplay.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

# The AI layer, whole. Comment lines are skipped: they explain, they do not read.
solo=$(grep -rn 'rule_descriptions' scripts/solo/ | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
if [ -n "$solo" ]; then
	echo "::error::scripts/solo/ reads OPR rule TEXT — the AI must read the mechanics registry (NML-1115)"
	echo "$solo"
	fail=1
fi

# The move bands, the one gameplay path that used to parse prose (move_modifier_from_description).
bands=$(awk '/^static func move_bands_for_props\(/{inside=1;next} inside && /^(static )?func /{inside=0} inside' \
	scripts/movement_range_controller.gd | grep -n 'descriptions' || true)
if [ -n "$bands" ]; then
	echo "::error::move_bands_for_props reads a descriptions key — the bands are rule NAME + registry data (NML-1115)"
	echo "$bands"
	fail=1
fi

if [ "$fail" -eq 0 ]; then
	echo "rule-text hygiene: no gameplay path reads OPR rule text"
fi
exit "$fail"
