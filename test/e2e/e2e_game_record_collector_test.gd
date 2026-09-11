extends GdUnitTestSuite
## E2E — PR B1: the in-memory game record collector is fed by the real central seams on the real
## scenes/main.tscn, and its record matches the Battle Log's own activations. Also proves the dice
## faces come from the real tray and that the privacy allowlist strips every display name.
##
## Real: scenes/main.tscn with its real _ready() (which builds and wires the collector), the real
## BattleLog, the real DiceTray, the real SharedRecordBuilder allowlist. Constructed: the GameUnits
## and their model nodes (importing a real Army Forge list needs the network) at genuine table spots.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A real GameUnit with a stable identifier and a PRIVATE display name, registered on the real army
## manager. The collector must keep the identifier and never the name.
func _register(pid: int, unit_id: String, display_name: String, at: Vector3, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_id, positions)
	u.unit_id = unit_id
	u.unit_properties["name"] = display_name
	u.unit_properties["network_id"] = unit_id
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _activation_lines() -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains("activated ("):
			n += 1
	return n


func _recorded_actions(kind: String) -> Array:
	var out: Array = []
	var record: Dictionary = _main.game_record_collector.build_record()
	for a in record["actions"]:
		if str((a as Dictionary).get("kind", "")) == kind:
			out.append(a)
	return out


## The collector is built by the real _ready() and tapped by the SAME activation funnel the Battle
## Log uses, so both counts must move together — one record action per logged activation.
func test_record_actions_match_battle_log_activations(timeout := 120000) -> void:
	assert_that(_main.game_record_collector).override_failure_message("main built no game record collector").is_not_null()
	var before := _activation_lines()
	var before_actions: int = _main.game_record_collector.action_count()
	_main._log_battle_activation(_register(1, "unit-a", "Private Alpha", Vector3(-0.30, 0.0, 0.20)), false)
	_main._log_battle_activation(_register(2, "unit-b", "Private Beta", Vector3(0.30, 0.0, -0.20)), false)
	_main._log_battle_activation(_register(1, "unit-c", "Private Gamma", Vector3(-0.20, 0.0, 0.30)), false)
	var activation_actions := _recorded_actions("activate").size()
	assert_int(activation_actions) \
		.override_failure_message("collector recorded %d activations, Battle Log logged %d" % [activation_actions, _activation_lines() - before]) \
		.is_equal(_activation_lines() - before)
	assert_int(_main.game_record_collector.action_count() - before_actions).is_equal(_activation_lines() - before)
	await E2EBoot.settle(get_tree())


## Observed dice faces are read off the real tray; the collector must reproduce exactly the faces
## BattleLog reports for the same roll.
func test_recorded_dice_faces_equal_the_tray(timeout := 120000) -> void:
	var faces: Array[int] = [2, 5, 6]
	var no_tags: Array[int] = []
	_main.dice_roller_control.show_faces(faces)
	_main._add_dice_log_entry("You", faces, {DiceRules.CTX_TARGET: DiceRules.TARGET_NONE}, no_tags)
	var recorded: Array = []
	for a in _recorded_actions("roll"):
		recorded.append_array((a as Dictionary).get("dice_faces", []))
	var tray: Array = []
	var per: Dictionary = _main.dice_roller_control.per_dice_result()
	for i in range(faces.size()):
		tray.append(int(per["die_%d" % i]))
	assert_array(recorded).override_failure_message("recorded %s, tray reported %s" % [str(recorded), str(tray)]).is_equal(tray)
	await E2EBoot.settle(get_tree())


## The privacy boundary: the record may carry stable identifiers but the built payload must contain
## neither a unit display name nor a player name.
func test_payload_built_from_the_record_has_no_display_names(timeout := 120000) -> void:
	_main._log_battle_activation(_register(1, "unit-secret", "Very Secret Warband", Vector3(-0.30, 0.0, 0.20)), false)
	var faces: Array[int] = [1, 2]
	var no_tags: Array[int] = []
	_main.dice_roller_control.show_faces(faces)
	_main._add_dice_log_entry("Very Secret Player", faces, {DiceRules.CTX_TARGET: DiceRules.TARGET_NONE}, no_tags)
	var payload := SharedRecordBuilder.build(_main.game_record_collector.build_record()).get_string_from_utf8()
	assert_str(payload).not_contains("Very Secret Warband")
	assert_str(payload).not_contains("Very Secret Player")
	await E2EBoot.settle(get_tree())
