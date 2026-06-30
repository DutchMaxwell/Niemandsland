class_name ActivationSelector
extends RefCounted
## Strategy for choosing WHICH eligible unit a side activates next. The SoloController asks the
## selector for its next unit each AI activation (and it could drive a randomised human/co-op pick
## too). Pluggable so the policy can evolve without touching the turn engine.
##
## This base class is the **Phase 0 trivial selector**: the first eligible unit (fully
## deterministic). Phase 1 subclasses override select() for the official OPR rule — split the table
## into 2 sections (D6), pick a random eligible unit in the rolled section, with Shaken units last
## and Counter units after non-Counter ones. A seeded RandomNumberGenerator is threaded through so
## a solo game can be made reproducible (helps tests/replay).

## Pick the next unit from `eligible`, or null if there is none. `rng` is unused by the trivial
## default but is part of the contract for randomised subclasses (seed it for reproducibility).
func select(eligible: Array, _rng: RandomNumberGenerator) -> Variant:
	return eligible[0] if not eligible.is_empty() else null
