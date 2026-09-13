extends GdUnitTestSuite
## #845 option (b) — an attackers-side Mark record lives on the TARGET after placement, and a
## friendly unit CHARGING that target gets the granted rule's effect. Rapid Charge's own registry
## entry carries `rush_mod` (4 in every core book): the charger's reach against THIS one target
## grows by that value, while an unmarked target and the marked unit's own reach stay at the
## plain band. The record shape written here is exactly what _solo_apply_vs_marks now writes
## through _solo_record_spell_mod (pinned end-to-end in e2e_vs_mark_los_test.gd).

const IN2M := 0.0254


func before_test() -> void:
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {
		"player_id": pid,
		"name": unit_name,
		"quality": 4,
		"defense": 4,
		"special_rules": [],
		"game_system": "aof",
		"faction_folder": "dark_elves",
		"base_is_oval": false,
		"base_width_mm": 32,
		"base_depth_mm": 32,
		"base_size_round": 32,
	}
	for position in positions:
		var model := ModelInstance.new()
		model.is_alive = true
		model.unit = unit
		var node := Node3D.new()
		add_child(node)
		node.global_position = position
		model.node = node
		unit.models.append(model)
	return unit


func _arm(unit: GameUnit) -> void:
	var source := OPRApiClient.OPRUnit.new()
	var weapon := OPRApiClient.OPRWeapon.new()
	weapon.name = "CCW"
	weapon.range_value = 0
	weapon.attacks = 3
	weapon.count = 1
	source.weapons.append(weapon)
	unit.source_type = "opr"
	unit.source_data = source


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for unit in units:
		army.game_units[(unit as GameUnit).unit_id] = unit
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return solo


## The exact record _solo_apply_vs_marks writes for a selected Mark: a once-grant on the
## TARGET with beneficiary "attackers" and no live overlay.
func _mark_with_rapid_charge(target: GameUnit) -> void:
	target.unit_properties["spell_records"] = [{
		"spell": "Rapid Charge Mark", "hit_mod": 0, "def_mod": 0, "casting_mod": 0,
		"morale_mod": 0, "range_in": 0, "advance_in": 0, "rush_in": 0,
		"grants_rule": "Rapid Charge", "scope": "", "beneficiary": "attackers",
		"duration": "once", "no_live_grant": true}]


## 15" centre distance on 32mm bases ≈ 13.7" base-edge gap: outside the plain 12" charge band,
## inside 12" + Rapid Charge's registry rush_mod (4) = 16".
const FAR_IN := 15.0


func test_a_marked_target_extends_the_friendly_chargers_reach() -> void:
	var charger := _unit(2, "Charger", [Vector3.ZERO])
	_arm(charger)
	var target := _unit(1, "Target", [Vector3(FAR_IN * IN2M, 0, 0)])
	_mark_with_rapid_charge(target)
	var solo := _controller([charger, target])
	var report := solo._act(charger)
	assert_int(int(report.get("action", -1))) \
		.override_failure_message("#845 option (b) — a charger against a target carrying the attackers-side " +
			"Rapid Charge record must reach the marked enemy (12\" band + the entry's rush_mod), got action %s" %
			str(report.get("action"))) \
		.is_equal(AiDecision.Action.CHARGE)


func test_an_unmarked_target_stays_at_the_plain_charge_band() -> void:
	var charger := _unit(2, "Charger", [Vector3.ZERO])
	_arm(charger)
	var target := _unit(1, "Target", [Vector3(FAR_IN * IN2M, 0, 0)])
	var solo := _controller([charger, target])
	var report := solo._act(charger)
	assert_int(int(report.get("action", -1))) \
		.override_failure_message("control fixture: a 13.7\" base gap must stay outside the plain 12\" band") \
		.is_not_equal(AiDecision.Action.CHARGE)


func test_the_marked_unit_gains_nothing_against_other_targets() -> void:
	var marked_unit := _unit(2, "Marked", [Vector3.ZERO])
	_arm(marked_unit)
	_mark_with_rapid_charge(marked_unit)
	var other := _unit(1, "Other", [Vector3(FAR_IN * IN2M, 0, 0)])
	var solo := _controller([marked_unit, other])
	var report := solo._act(marked_unit)
	assert_int(int(report.get("action", -1))) \
		.override_failure_message("#845 option (b) — an attackers-side record must never self-benefit its " +
			"bearer: the marked unit's own reach against an unmarked enemy stays at the plain 12\" band") \
		.is_not_equal(AiDecision.Action.CHARGE)
