extends GdUnitTestSuite
## Solo/AI activation-selector strategy (Phase 0). The trivial base picks the first eligible unit
## deterministically; a test-local subclass proves the strategy is overridable for Phase 1.

const SelectorScript := preload("res://scripts/solo/activation_selector.gd")


## A Phase-1-style subclass to prove select() is overridable (picks the LAST unit here).
class LastSelector:
	extends ActivationSelector
	func select(eligible: Array, _rng: RandomNumberGenerator) -> Variant:
		return eligible[-1] if not eligible.is_empty() else null


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 42
	return r


# === trivial base ===

func test_trivial_picks_first() -> void:
	var sel: ActivationSelector = SelectorScript.new()
	assert_str(str(sel.select(["a", "b", "c"], _rng()))).is_equal("a")


func test_trivial_empty_is_null() -> void:
	var sel: ActivationSelector = SelectorScript.new()
	assert_object(sel.select([], _rng())).is_null()


func test_trivial_is_deterministic() -> void:
	var sel: ActivationSelector = SelectorScript.new()
	var pool := ["x", "y", "z"]
	assert_str(str(sel.select(pool, _rng()))).is_equal(str(sel.select(pool, _rng())))


# === strategy is overridable ===

func test_subclass_overrides_policy() -> void:
	var sel: ActivationSelector = LastSelector.new()
	assert_str(str(sel.select(["a", "b", "c"], _rng()))).is_equal("c")
	assert_object(sel.select([], _rng())).is_null()
