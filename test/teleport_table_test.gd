extends GdUnitTestSuite
## Teleport / Ethereal — the table-side PR 1 (design #816, docs/plans/TELEPORT_DESIGN_2026-09-08.md).
## RED-GREEN without boxes: these tests are pushed FIRST (this commit) and must FAIL against a main
## that has no teleport seam; the handler commit turns them green.
## Covered (brief §6):
##   1. a Teleport bearer after an Advance can land within 3" but not at 3.5" (cap + candidate clamp);
##   2. after a Rush within 6";
##   3. Ethereal flat 6" regardless of band (keyed by the NAME, not its 0.0 bonus params);
##   4. a second reposition in the same activation is refused (latch);
##   5. a unit WITHOUT the name never repositions;
##   6. the recorder emits the landing centroid ({"used": true, "to": Vector2}).

const IN2M := 0.0254
const CONTROLLER := preload("res://scripts/solo/solo_controller.gd")


## A bare GameUnit with the given special-rule names — no map data (RulesRegistry answers from the
## unit's own rules when the system map is empty, the same read the band approximation uses).
func _bearer(rule_names: Array, props: Dictionary = {}) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"player_id": 1, "name": "Teleporter", "special_rules": rule_names}
	u.unit_properties.merge(props, true)
	return u


# --- 1. Advance cap: within 3", never 3.5" ---------------------------------------------------
func test_teleport_cap_advance_is_3_and_candidates_clamp_to_cap() -> void:
	assert_float(CONTROLLER.teleport_cap_in("Teleport", false)).is_equal(3.0)
	# An objective 3.5" beyond the post-move centre is a LAND AT 3"-TOWARD-IT candidate, never 3.5".
	var obj := Vector2(3.5, 0.0) * IN2M
	var cands: Array = CONTROLLER.teleport_candidates(Vector2.ZERO, 3.0 * IN2M, obj, true,
		Vector2.ZERO, false, Callable())
	var from: Vector2 = cands[0]
	for i in range(1, cands.size()):
		assert_float(from.distance_to(cands[i] as Vector2) / IN2M).is_less_equal(3.001)

func test_teleport_cap_rush_is_6() -> void:
	assert_float(CONTROLLER.teleport_cap_in("Teleport", true)).is_equal(6.0)

# --- 3. Ethereal: flat 6" regardless of band --------------------------------------------------
func test_ethereal_cap_is_flat_6() -> void:
	assert_float(CONTROLLER.teleport_cap_in("Ethereal", false)).is_equal(6.0)
	assert_float(CONTROLLER.teleport_cap_in("Ethereal", true)).is_equal(6.0)

# --- 4. second reposition in the same activation is refused -----------------------------------
func test_latch_refuses_second_reposition() -> void:
	var u := _bearer(["Teleport"], {"teleport_used_this_activation": true})
	var ctl: SoloController = auto_free(CONTROLLER.new())
	var dec: Dictionary = ctl.teleport_decision(u, false)
	assert_bool(bool(dec.get("used", true))).is_false()
	assert_str(str(dec.get("why", ""))).contains("once per activation")

# --- 5. a unit WITHOUT the name never repositions ---------------------------------------------
func test_unit_without_name_never_repositions() -> void:
	var u := _bearer([])
	var ctl: SoloController = auto_free(CONTROLLER.new())
	var dec: Dictionary = ctl.teleport_decision(u, false)
	assert_bool(bool(dec.get("used", true))).is_false()
	assert_str(str(dec.get("rule", "x"))).is_empty()

# --- 6. the recorder emits the landing centroid -----------------------------------------------
func test_recorder_ledger_carries_teleport_block() -> void:
	var u := _bearer(["Teleport"], {"teleport_used_this_activation": true,
		"teleport_to": Vector2(0.42, -0.17)})
	var ledger := AiActRecorder._ledger_of(u)
	assert_that(ledger.has("teleport")).is_true()
	var t: Dictionary = ledger.get("teleport", {})
	assert_bool(bool(t.get("used", false))).is_true()
	assert_vector((t.get("to", Vector2.INF) as Vector2)).is_equal_approx(Vector2(0.42, -0.17), Vector2(0.0001, 0.0001))
