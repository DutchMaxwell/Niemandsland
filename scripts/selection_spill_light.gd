class_name SelectionSpillLight
extends OmniLight3D
## A green point light cast from a selected miniature, so the selection visibly
## EMITS light onto the ground, neighbouring minis, and the volumetric mist — a real
## light source, replacing the old flat ground-ring halo.
##
## Parented under the selected wrapper (identity scale, origin on the ground), so it
## follows the mini when dragged at zero per-frame cost. Shadows are off (this is a
## soft accent, never a key light), and its energy is kept dimmer than the mini's
## emissive overlay so the model stays the brightest thing in frame and the spill
## reads as light radiating FROM it. Overbright stacking in dense units is bounded by
## the low energy + steep attenuation here and a per-preset light-count cap in
## object_manager.

# === Constants ===

## Selection green — shared with the model emissive overlay so the on-model glow and
## the off-model spill can never drift apart.
const GREEN_SELECTION: Color = Color(0.25, 1.0, 0.4)
## Child node name so object_manager can find/free the light on deselect.
const NODE_NAME: StringName = &"SelectionSpillLight"
## Group every spill light joins, so the live count is read from the tree (immune to
## counter desync when a selected object is freed without going through deselect).
const GROUP: StringName = &"selection_spill_light"
## Height above the wrapper origin (metres) — a bit above the mini so the spill is a
## soft, even green wash on the ground, not a hot inverse-square spot right under it.
## (Safe now that fog scattering is off, so a raised light no longer makes a mid-air orb.)
const Y_OFFSET: float = 0.06
## Radiant energy; deliberately low (OmniLight is physical/inverse-square at this tiny
## scale) so the spill reads as a soft green wash and overlapping lights stay bounded.
const ENERGY: float = 0.05
## Minimum spill radius (metres); larger bases scale up via RANGE_FOOTPRINT_K.
const MIN_RANGE_M: float = 0.16
const RANGE_FOOTPRINT_K: float = 3.0
## Gentle falloff for a broad, soft pool rather than a peaked hotspot.
const ATTENUATION: float = 1.0
## Specular contribution — the green reflection on glossy spots, kept below a bloom.
const SPECULAR: float = 0.5
## No volumetric-fog scattering: the light must read as light ON surfaces, not as a
## glowing orb in the mist (the fog scatter turned the point light into a bright ball).
const VOLUMETRIC_FOG_ENERGY: float = 0.0

# === Public API ===

## Configure the light for an object of the given horizontal footprint radius (metres).
func setup(footprint_radius: float) -> void:
	name = NODE_NAME
	add_to_group(GROUP)
	light_color = GREEN_SELECTION
	light_energy = ENERGY
	light_specular = SPECULAR
	light_volumetric_fog_energy = VOLUMETRIC_FOG_ENERGY
	omni_range = maxf(footprint_radius * RANGE_FOOTPRINT_K, MIN_RANGE_M)
	omni_attenuation = ATTENUATION
	shadow_enabled = false
	position.y = Y_OFFSET
