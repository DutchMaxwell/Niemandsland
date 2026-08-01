extends GdUnitTestSuite
## NML-936 (BUG B1) — `requires_not_shaken` is written into the "Spell Accumulator" registry
## entry's params but read by nobody. scripts/solo/solo_controller.gd's _aura_casters (the
## spell-token lending pool builder) admits a battery via `is_battery` with NO `is_shaken`
## check at all — a SHAKEN battery still lends its stored tokens to foreign casters within its
## 12" reach, even though the rule's own params say it must not.
##
## Fixture style mirrors test/solo_controller_test.gd's _aura_casters coverage
## (test_aura_casters_counts_an_attached_hero_once, test_accumulator_joins_the_token_pool_within_12):
## a bare SoloController + OPRArmyManager, no scene boot. The registry is seeded via the same
## RulesRegistry._cache injection test/rules_registry_test.gd's _inject_gf_map uses, so the
## fixture is independent of any real faction's data.
##
## test_a_shaken_accumulator_battery_does_not_lend_tokens pins the fix: without
## _aura_casters honouring requires_not_shaken, a Shaken battery still joins the pool.
## test_an_unshaken_accumulator_battery_still_lends_tokens
## is the CONTROL: identical fixture minus Shaken, must stay green before and after the fix.

const INCH_M := 0.0254
const LEND_REACH_IN := 10.0   # inside SoloController.SPELL_ACCUMULATOR_REACH_IN (12")


func _unit(pid: int, positions: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## Synthetic map: "Spell Accumulator" carries requires_not_shaken true — the param the pool
## builder currently never reads.
func _inject_accumulator_map() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {"testfac": {
		"Spell Accumulator": {"primitive": "Spell Accumulator", "params": {"requires_not_shaken": true}},
	}}, "common": {}}


## A caster (pid 2) and a token-battery (pid 2) `LEND_REACH_IN` apart — well inside the
## battery's own 12" lend radius. `shaken` stamps the battery's is_shaken flag; the rating in
## "Spell Accumulator(2)" gives it tokens to lend (initialize_caster_points reads the rating,
## RulesRegistry.base_rule_name strips it back to "Spell Accumulator" for the map lookup).
func _caster_and_battery(shaken: bool) -> Dictionary:
	var caster := _unit(2, [Vector3.ZERO])
	caster.unit_id = "caster"
	caster.unit_properties["special_rules"] = ["Caster(2)"]
	caster.initialize_caster_points()
	var battery := _unit(2, [Vector3(LEND_REACH_IN * INCH_M, 0, 0)])
	battery.unit_id = "battery"
	battery.unit_properties["game_system"] = "gf"
	battery.unit_properties["faction_folder"] = "testfac"
	battery.unit_properties["special_rules"] = ["Spell Accumulator(2)"]
	battery.initialize_caster_points()
	battery.is_shaken = shaken
	return {"caster": caster, "battery": battery}


func _pool_names(solo: SoloController, caster: GameUnit) -> Array:
	var names: Array = []
	for h in solo._aura_casters(2, caster, null):
		names.append(((h as Dictionary)["unit"] as GameUnit).unit_id)
	return names


# NOTE ON ORDER: the control test is declared BEFORE the RED test below on purpose — measured on
# Godot 4.6.2 headless, gdUnit4's static test-discovery scanner silently drops whichever test is
# declared AFTER a RED test that fails here, reporting "Executed test cases: (1/1)" instead of
# (2/2) with the second test never even logging STARTED. Swapping the declaration order
# reproducibly restores (2/2); order otherwise carries no semantic meaning for gdUnit, so this is
# a harmless workaround for a tooling quirk, not a test-logic change (see the identical note in
# test/e2e/e2e_vs_mark_los_test.gd, where this was first diagnosed).
func test_an_unshaken_accumulator_battery_still_lends_tokens() -> void:
	# Control: identical fixture, battery NOT shaken — it must stay in the pool whether or not
	# the fix lands.
	_inject_accumulator_map()
	var fixture := _caster_and_battery(false)
	var caster: GameUnit = fixture["caster"]
	var battery: GameUnit = fixture["battery"]
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {caster.unit_id: caster, battery.unit_id: battery}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var names := _pool_names(solo, caster)
	assert_array(names) \
		.override_failure_message("control fixture: an UNSHAKEN battery within 12\" must lend its tokens (pool: %s)" %
			str(names)) \
		.contains(["battery"])
	RulesRegistry.reset_cache()


func test_a_shaken_accumulator_battery_does_not_lend_tokens() -> void:
	_inject_accumulator_map()
	var fixture := _caster_and_battery(true)
	var caster: GameUnit = fixture["caster"]
	var battery: GameUnit = fixture["battery"]
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {caster.unit_id: caster, battery.unit_id: battery}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var names := _pool_names(solo, caster)
	assert_array(names) \
		.override_failure_message("NML-936 — a SHAKEN Spell Accumulator battery still lent its tokens " +
			"(requires_not_shaken is set on the rule's params but _aura_casters never reads it; pool: %s)" %
			str(names)) \
		.not_contains(["battery"])
	RulesRegistry.reset_cache()
