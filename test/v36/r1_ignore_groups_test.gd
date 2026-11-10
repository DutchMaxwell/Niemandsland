extends GdUnitTestSuite

const Boot := preload("res://test/e2e/e2e_boot.gd")
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "rule_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 2,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


## Forms of ONE rule share a key; differently named rules keep their own.
func test_the_group_key_folds_only_forms_of_one_rule() -> void:
	var cases := [
		["Plaguebound Boost", {"upgrades": "Plaguebound"}, "Plaguebound"],
		["Enhanced Plaguebound", {}, "Plaguebound"],
		["Angelic Blessing Boost", {}, "Angelic Blessing"],
		["Enhanced Angelic Blessing", {}, "Angelic Blessing"],
		["Enhanced Knightborn", {}, "Knightborn"],
		["Self-Repair Boost", {}, "Self-Repair"],
		["Enhanced Self-Repair", {}, "Self-Repair"],
		["self-repair", {}, "Self-Repair"],
		["Regeneration Aura", {}, "Regeneration"],
		["Regeneration Buff", {}, "Regeneration"],
		["regeneration", {}, "Regeneration"],
		["Medical Training", {}, "Regeneration"],
		["resistance", {}, "Resistance"],
		["Spell Resistance", {}, "Spell Resistance"],
		["Protection Feat", {}, "Protection Feat"],
		["Protected", {}, "Protected"],
		["Grounded Protection", {}, "Grounded Protection"],
	]
	for c in cases:
		assert_str(_main._solo_ignore_group_key(str(c[0]), c[1])).is_equal(str(c[2]))


func _pick(rules: Array, faction: String, system: String = "gf") -> Dictionary:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	return _main._solo_regen_pick(_unit(rules, system, faction))


## Regeneration and a differently named rule are two groups, Regeneration first; the top-level verdict
## (the single best target and its name) is what it always was.
func test_two_named_rules_make_two_groups_and_the_top_level_is_unchanged() -> void:
	var pick := _pick(["Regeneration", "Plaguebound"], "plague_disciples")
	var groups: Array = pick["groups"]
	assert_int(groups.size()).is_equal(2)
	assert_str(str(groups[0]["group"])).is_equal("Regeneration")
	assert_str(str(groups[0]["name"])).is_equal("regeneration")
	assert_int(int(groups[0]["target"])).is_equal(5)
	assert_bool(bool(groups[0]["regen"])).is_true()
	assert_str(str(groups[1]["group"])).is_equal("Plaguebound")
	assert_int(int(groups[1]["target"])).is_equal(6)
	assert_bool(bool(groups[1]["regen"])).is_false()
	assert_int(int(pick["target"])).is_equal(5)
	assert_str(str(pick["name"])).is_equal("regeneration")


func test_forms_of_one_rule_make_one_group_at_the_best_target() -> void:
	var pick := _pick(["Plaguebound", "Enhanced Plaguebound"], "plague_disciples")
	var groups: Array = pick["groups"]
	assert_int(groups.size()).is_equal(1)
	assert_str(str(groups[0]["group"])).is_equal("Plaguebound")
	assert_int(int(groups[0]["target"])).is_equal(5)
	assert_int(int(pick["target"])).is_equal(5)
	assert_str(str(pick["name"])).is_equal("Enhanced Plaguebound")


func test_self_repair_and_its_enhanced_form_make_one_group() -> void:
	var pick := _pick(["Self-Repair", "Enhanced Self-Repair"], "robot_legions")
	var groups: Array = pick["groups"]
	assert_int(groups.size()).is_equal(1)
	assert_str(str(groups[0]["group"])).is_equal("Self-Repair")
	assert_int(int(groups[0]["target"])).is_equal(5)


func test_a_lone_alias_is_one_group_and_not_the_regeneration_group() -> void:
	var pick := _pick(["Protected"], "human_inquisition")
	var groups: Array = pick["groups"]
	assert_int(groups.size()).is_equal(1)
	assert_str(str(groups[0]["group"])).is_equal("Protected")
	assert_bool(bool(groups[0]["regen"])).is_false()


func test_a_unit_without_any_ignore_rule_has_no_groups() -> void:
	var pick := _pick([], "human_inquisition")
	assert_array(pick["groups"]).is_empty()
	assert_int(int(pick["target"])).is_equal(0)


## A gated rule (a distance gate on its 6+) that rolls beside Regeneration still explains itself: the pick's
## top-level gate line stays empty (another rule is the overall best), the group gate carries the verdict.
func test_a_gated_rule_beside_regeneration_still_explains_itself() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var unit := _unit(["Regeneration", "Knightborn"], "gf", "knight_brothers")
	var far: Dictionary = _main._solo_regen_pick(unit, false, 12.0)
	assert_str(str(far["gate"])).is_equal("")
	assert_str(str(far["group_gate"])).contains("Warding: ")
	assert_str(str(far["group_gate"])).contains("over 9")
	var near: Dictionary = _main._solo_regen_pick(unit, false, 5.0)
	assert_int((near["groups"] as Array).size()).is_equal(1)
	assert_str(str(near["group_gate"])).contains("no 6+")
