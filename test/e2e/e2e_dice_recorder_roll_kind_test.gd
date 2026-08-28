extends GdUnitTestSuite
## NML-1104 — RED-GREEN for the dice recorder's `roll_kind` field.
##
## `_solo_tray_roll`'s `roll_kind` parameter defaulted to "attack" (main.gd ~:7107) and most call
## sites never passed it, so dice.jsonl filed morale tests, Fearless recovery dice, No Retreat,
## Regeneration, Ravage, Battleborn and the dangerous-terrain test all under "attack" — the gates
## themselves are position-keyed and never depended on the value (NOT a correctness bug), but a
## per-rule gate breakdown was impossible. This suite drives the REAL rule call sites over main.tscn
## (E2EBoot pattern, same as e2e_reanimation_test.gd) with `AiDiceRecorder` pointed at a temp dir
## (the same NML_DICE_DUMP seam ai_shot_recorder_test.gd exercises for AiShotRecorder), then reads
## dice.jsonl back and checks the LAST recorded line's `roll_kind`.
##
## The "still combat" half below drives Reanimation (main.gd:4629/:4657) rather than a shooting
## volley: both are a single unlabeled `_solo_tray_roll(..., "attack", ...)` call reached through
## `AiDiceRecorder.record()` the identical way, and Reanimation needs far less rigging than a full
## volley's shot list / LOS / save prompt (see e2e_volley_morale_test.gd) to prove the same point —
## this ticket touched named rule call sites only, and an untouched one must still read "attack".

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const _DUMP_DIR := "user://dice_recorder_roll_kind_test_tmp"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	# Batch dice: _solo_tray_roll draws faces from the RNG instead of awaiting the physics tray,
	# which headless would never settle.
	_main._solo_batch = true
	# AiDiceRecorder's env check + open stream are cached STATIC state (dice_recorder.gd) — reset
	# per test so two test_ functions in this suite do not share one stream (ai_shot_recorder_test.gd's
	# idiom for its AiShotRecorder sibling).
	DirAccess.make_dir_recursive_absolute(_DUMP_DIR)
	AiDiceRecorder._checked = false
	AiDiceRecorder._stream = null
	AiDiceRecorder._count = 0
	OS.set_environment("NML_DICE_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))


func after_test() -> void:
	AiDiceRecorder.close()
	OS.set_environment("NML_DICE_DUMP", "")
	var d := DirAccess.open(_DUMP_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_DUMP_DIR)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _dump_lines() -> Array:
	var f := FileAccess.open(_DUMP_DIR.path_join("dice.jsonl"), FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			out.append(line)
	f.close()
	return out


func _last_roll_kind() -> String:
	var lines := _dump_lines()
	assert_int(lines.size()) \
		.override_failure_message("expected at least one recorded roll in dice.jsonl") \
		.is_greater(0)
	var rec: Dictionary = JSON.parse_string(lines[lines.size() - 1])
	return str(rec.get("roll_kind", ""))


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A plain unit: no Fearless / No Retreat / Banner, so `_solo_morale_test` takes exactly the one
## tray roll at main.gd ~8301.
func _squad(unit_name: String, count: int) -> GameUnit:
	var spots: Array = []
	for i in count:
		spots.append(Vector3(float(i) * 0.5 * INCH, 0, 0))
	return _reg(E2EBoot.make_unit(_main, 2, unit_name, spots))


## Reanimation fixture, copied from e2e_reanimation_test.gd's `_bots()`: `count` models, the
## trailing `dead` of them fallen, so the activation has a pool to roll for.
func _bots(unit_name: String, count: int, dead: int) -> GameUnit:
	var spots: Array = []
	for i in count:
		spots.append(Vector3(float(i) * 0.5 * INCH, 0, 0))
	var u := _reg(E2EBoot.make_unit(_main, 2, unit_name, spots))
	u.unit_properties["special_rules"] = ["Reanimation"]
	u.unit_properties["faction_folder"] = "robot_legions"
	for i in count:
		var m := u.models[i] as ModelInstance
		m.model_index = i
		if i >= count - dead:
			m.wounds_current = 0
			m.is_alive = false
	return u


## RED on main: the morale test call site passed no `roll_kind`, so the recorder filed it "attack"
## like every other unlabeled roll. GREEN here: it must file "morale".
func test_morale_test_records_roll_kind_morale() -> void:
	var u := _squad("Squad", 4)
	await _main._solo_morale_test(u, "AI (Squad)", false)
	assert_str(_last_roll_kind()).is_equal("morale")


## An untouched rule call site (Reanimation, main.gd:4657) must still record "attack" — proof the
## fix touched only the seven named rule call sites and left every other `_solo_tray_roll` alone.
func test_an_untouched_rule_roll_still_records_roll_kind_attack() -> void:
	var u := _bots("Bots", 4, 2)
	await _main._solo_try_reanimation(u)
	assert_str(_last_roll_kind()).is_equal("attack")
