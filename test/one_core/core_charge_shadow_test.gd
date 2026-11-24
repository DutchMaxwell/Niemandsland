extends GdUnitTestSuite
## Plan E (melee shadow): with the charge door OFF the table fights the AI charge; NML_CORE_SHADOW_MELEE=1 replays every
## charge the door's slice would take through the core's step path (CoreShadow.melee_*) and records whether rolls, end
## state, positions and lines agree. Real: main scene, NmlCore, the planner's charge move, `_run_ai_melee`.
## Constructed: OPR units (ParityTable) at both seats AI. Planted faults: the table board changed after the fight.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.3, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const BLADE := {"name": "Blade", "range_in": 0, "attacks": 2, "count": 10, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _shadow_env_before: String


func before_test() -> void:
	_shadow_env_before = OS.get_environment("NML_CORE_SHADOW_MELEE")
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [1, 2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	SoloHarness.auto_saves(_main)
	SoloHarness.fast(_main)
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	CoreActivation._charge_env = 0
	CoreShadow._melee_env = 1
	CoreShadow.melee_records = []
	CoreActivation.ai_charges = 0


func after_test() -> void:
	CoreActivation._charge_landing = false
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreActivation._charge_env = -1
	OS.set_environment("NML_CORE_SHADOW_MELEE", _shadow_env_before)
	CoreShadow._melee_env = -1
	CoreShadow.melee_records = []
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


## One shadowed AI charge (door off): the shadow board before the planner's charge move, the table's melee between
## `melee_begin` and `melee_compare`. `fault` runs on the table's board after the fight, before the compare (a planted fault).
func _shadow(s: int, models: int, foe_models: int, gap_in: float, foe_rules := [], fault := Callable(),
		att_rules := [], att_weapon_rules := [], foe_weapon_rules := []) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": models, "x_in": 0.0, "rules": att_rules}, true),
		BLADE.merged({"count": models, "rules": att_weapon_rules}, true))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": foe_models, "x_in": gap_in, "z_step_in": 1.4, "rules": foe_rules}, true),
		BLADE.merged({"count": foe_models, "attacks": 1, "rules": foe_weapon_rules}, true))
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	_main.seed_tray_rng(s)
	var sc: SoloController = _main.solo_controller
	_main._solo_core_shadow_h = CoreShadow.capture(_main, att)
	var from_in: float = sc.charge_from_in(att, foe, MoveIntent.distance_inches(sc.unit_centre(att), sc.unit_centre(foe)))
	sc._charge_move(att, foe, 12.0)
	att.unit_properties["moved_round"] = 1
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "charge_from_in": from_in, "moved": true}
	CoreShadow.melee_begin(_main, att, report)
	await _main._run_ai_melee(report)
	if fault.is_valid():
		fault.call(att, foe)
	CoreShadow.melee_compare(_main, att, report)
	CoreShadow.release(_main)
	_free([att, foe])
	await _main.get_tree().process_frame
	return CoreShadow.melee_records.back() if not CoreShadow.melee_records.is_empty() else {}


func _sweep_shadow(models: int, foe_models: int, gap_in: float) -> void:
	var bad: Array = []
	var separate := 0
	for s in 8:
		var rec := await _shadow(s, models, foe_models, gap_in)
		# Ticket SEPARATE-1IN (lead ruling 22.11., docs/one_core/PARITY_RULING.md item 4): the charger's 1" step back ends short of
		# 1" from the defender on BOTH sides - illegal by the book, so the honest reading is `core_illegal` (enemy_within_1in only),
		# not equal. It is counted, not hidden; any other difference or illegal kind still fails. Fixed after the shoot deletion.
		var sep := _separate_1in(rec)
		separate += 1 if sep else 0
		if not rec["taken"] or not (bool(rec["equal"]) or sep):
			bad.append("seed %d: %s" % [s, rec])
	print("MELEE_SHADOW %dv%d seeds=8 unequal=%d separate_1in=%d" % [models, foe_models, bad.size(), separate])
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 4))).is_empty()


## Ticket SEPARATE-1IN: the record's only difference is an illegal core end of kind `enemy_within_1in` (the 1" step back short).
func _separate_1in(rec: Dictionary) -> bool:
	return str(rec.get("first_diff", "")) == "core_illegal" and not (rec.get("core_illegal", []) as Array).is_empty() \
		and (rec["core_illegal"] as Array).all(func(i: Dictionary) -> bool: return str(i["kind"]) == "enemy_within_1in")


## Taken and equal: both sides standing (5 v 8) and the defender wiped out (8 v 2), 8 seeds each.
func test_a_taken_charge_replays_equal() -> void:
	await _sweep_shadow(5, 8, 7.0)
	await _sweep_shadow(8, 2, 6.0)


## Not taken: a Fear defender and a 10-model charger are recorded with their reasons and not replayed.
func test_a_charge_the_slice_refuses_is_recorded_not_replayed() -> void:
	var fear := await _shadow(0, 5, 8, 7.0, ["Fear(1)"])
	assert_bool(fear["taken"]).is_false()
	assert_array(fear["why"]).contains(["target_unit_rule:Fear"])
	var big := await _shadow(0, 10, 2, 6.0)
	assert_array(big["why"]).contains(["size"])
	assert_str(str(big["first_diff"])).is_empty()


## RED (planted on the table's board after the fight): a charger model nudged 1" -> reported as `free_position` (PLAN_FIRST_DELETION
## 3d: where a model stands is a free choice under docs/one_core/PARITY_RULING.md, not a mismatch); a defender's Shaken flipped -> a
## state field; the compare can fail.
func test_the_compare_sees_a_planted_difference() -> void:
	var nudge := func(att: GameUnit, _foe: GameUnit) -> void: (att.get_alive_models()[0] as ModelInstance).node.global_position.x += 0.0254
	var moved := await _shadow(0, 5, 8, 7.0, [], nudge)
	assert_bool((moved.get("free_position", {}) as Dictionary).is_empty()).override_failure_message("the nudge went unreported: %s" % [moved]).is_false()
	assert_array(["", "core_illegal"]).override_failure_message("a free position read as a mismatch: %s" % [moved]).contains([str(moved["first_diff"])])
	var shaken := func(_att: GameUnit, foe: GameUnit) -> void: foe.is_shaken = not foe.is_shaken
	var flipped := await _shadow(0, 5, 8, 7.0, [], shaken)
	assert_str(str(flipped["first_diff"])).is_equal("shaken")


## Plan E step 3: NML_CORE_SHADOW_MELEE=deny reads the melee deny file so a planted AP(1) charger is compared (not refused),
## the record carries `deny`, both unit names, their rule labels and the full core roll stream, and the live charge door is untouched.
func test_deny_view_compares_an_ap_charger_and_leaves_the_door_untouched() -> void:
	# Allow view (=1): AP(1) is refused by the live allow file, while `deny` already records [] (the deny file would take it).
	OS.set_environment("NML_CORE_SHADOW_MELEE", "1")
	CoreShadow._melee_env = -1
	var allow_rec := await _shadow(0, 5, 8, 7.0, [], Callable(), [], ["AP(1)"])
	assert_bool(allow_rec.get("taken", true)).is_false()
	assert_array(allow_rec.get("why", [])).contains(["weapon_rule:AP"])
	assert_bool(allow_rec.has("deny")).override_failure_message("record must carry `deny`").is_true()
	assert_array(allow_rec.get("deny", ["missing"])).is_empty()
	assert_str(str(allow_rec.get("charger", ""))).is_equal("Att")
	assert_str(str(allow_rec.get("target", ""))).is_equal("Def")
	assert_dict(allow_rec.get("rules", {})).contains_key_value("charger", ["AP"]).contains_key_value("target", [])
	assert_bool(allow_rec.has("core_rolls")).override_failure_message("record must carry `core_rolls`").is_true()
	assert_array(allow_rec.get("core_rolls", ["missing"])).is_empty()

	# Deny view (=deny): the same AP(1) charger is taken, replayed equal, and records the full core roll stream.
	OS.set_environment("NML_CORE_SHADOW_MELEE", "deny")
	CoreShadow._melee_env = -1
	assert_bool(CoreShadow.melee_enabled()).override_failure_message("NML_CORE_SHADOW_MELEE=deny must enable melee shadow").is_true()
	for s in 4:
		var rec := await _shadow(s, 5, 8, 7.0, [], Callable(), [], ["AP(1)"])
		assert_bool(rec.get("taken", false)).override_failure_message("seed %d: AP charger refused in deny view: %s" % [s, rec]).is_true()
		assert_array(rec.get("why", ["missing"])).is_empty()
		assert_array(rec.get("deny", ["missing"])).is_empty()
		# equal, or only the known SEPARATE-1IN reading (see `_sweep_shadow`)
		assert_bool(bool(rec.get("equal", false)) or _separate_1in(rec)).override_failure_message("seed %d: %s" % [s, rec]).is_true()
		assert_str(str(rec.get("charger", ""))).is_equal("Att")
		assert_str(str(rec.get("target", ""))).is_equal("Def")
		assert_dict(rec.get("rules", {})).contains_key_value("charger", ["AP"]).contains_key_value("target", [])
		var rolls: Array = rec.get("core_rolls", [])
		assert_int(rolls.size()).override_failure_message("seed %d: core_rolls empty" % s).is_greater_equal(2)
		if not rolls.is_empty():
			assert_dict(rolls[0]).contains_key_value("kind", "attack").contains_key_value("owner", "Att")
			for entry in rolls:
				assert_dict(entry).contains_keys(["kind", "count", "target", "owner", "faces"])

	# Planted fault on the AP charger in deny view is caught and keeps the full core roll stream.
	var nudge := func(att: GameUnit, _foe: GameUnit) -> void: (att.get_alive_models()[0] as ModelInstance).node.global_position.x += 0.0254
	var bad := await _shadow(0, 5, 8, 7.0, [], nudge, [], ["AP(1)"])
	assert_bool(bad.get("taken", false)).is_true()
	# PLAN_FIRST_DELETION 3d: a position difference is a free choice - reported in `free_position`, not a mismatch.
	assert_bool((bad.get("free_position", {}) as Dictionary).is_empty()).override_failure_message("the nudge went unreported: %s" % [bad]).is_false()
	assert_array(["", "core_illegal"]).contains([str(bad.get("first_diff", ""))])
	assert_int((bad.get("core_rolls", []) as Array).size()).is_greater_equal(2)

	# Door untouched: even with the charge door on and shadow in deny view, takes_ai_charge still reads the allow file.
	CoreActivation._charge_env = 1
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": 0.0}, true),
		BLADE.merged({"count": 5, "rules": ["AP(1)"]}, true))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 8, "x_in": 7.0}, true),
		BLADE.merged({"count": 8, "attacks": 1}, true))
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "moved": true}
	assert_array(CoreActivation.charge_refusals(_main, att, report)).contains(["weapon_rule:AP"])
	assert_bool(CoreActivation.takes_ai_charge(_main, att, report)).is_false()
	_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	_free([att, foe])


## Plan E step 3: deny view still refuses structural guards (`size`), records both units' rule labels, and on a roll
## mismatch keeps every core roll emitted up to and including the diverging roll.
func test_deny_view_refuses_size_and_keeps_core_rolls_through_mismatch() -> void:
	OS.set_environment("NML_CORE_SHADOW_MELEE", "deny")
	CoreShadow._melee_env = -1
	var big := await _shadow(0, 10, 2, 6.0, ["Fear(1)"], Callable(), [], ["AP(1)"])
	assert_bool(big.get("taken", true)).is_false()
	assert_array(big.get("deny", [])).is_equal(["size"])
	assert_array(big.get("why", [])).is_equal(["size"])
	assert_dict(big.get("rules", {})).contains_key_value("charger", ["AP"]).contains_key_value("target", ["Fear"])
	assert_array(big.get("core_rolls", ["nonempty"])).is_empty()

	# Tamper the second table roll (defense count) before compare: roll #0 matches, roll #1 diverges, both sit in core_rolls.
	var tamper := func(_att: GameUnit, _foe: GameUnit) -> void:
		if CoreShadow.tap.size() >= 2:
			CoreShadow.tap[1]["count"] = 99
	var mis := await _shadow(0, 5, 8, 7.0, [], tamper, [], ["AP(1)"])
	assert_bool(mis.get("taken", false)).is_true()
	assert_str(str(mis.get("first_diff", ""))).is_equal("rolls")
	var rolls: Array = mis.get("core_rolls", [])
	assert_int(rolls.size()).is_equal(2)
	if rolls.size() >= 2:
		assert_dict(rolls[0]).contains_key_value("kind", "attack")
		assert_dict(rolls[1]).contains_key_value("kind", "defense")
