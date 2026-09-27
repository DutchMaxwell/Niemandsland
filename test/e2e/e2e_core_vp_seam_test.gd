extends GdUnitTestSuite
## Wave 3 S4-U1 / S4-U3 — the Godot seam must hand the Rust core the mission VP ledger and a unit's distinct
## charge band. The live search reads both (the playout's imagined round end books VP onto `State.vp`, the
## charge seams read `bands.charge`), but the state reader hard-coded vp/vp_flavour/vp_memo to None and dropped
## `bands.charge`: on every round_vp mission the shipped AI planned as if the score were 0:0.
##
## THE READ-BACK. `NmlCore.plain_of` writes the vp trio from the core's own `State` and a unit's `bands` from
## `State.bands` (masked: a unit whose plain form carried no `bands` gets none back — the node corpus predates
## the key), so what comes back is what the core holds, not an echo of the input.
##
## WHAT IS REAL vs CONSTRUCTED. Real: scenes/main.tscn, the real SoloController mission ledger, BattleSim.capture
## and state_to_plain, the NmlCore extension. Constructed: two bare units, the ledger values and one unit's bands.
## Skipped where the extension is not loaded (the CI gdUnit shards build no core), as e2e_core_reload_test does.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const IN2M := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _env_core := ""
var _core_env := -1


func before_test() -> void:
	_env_core = OS.get_environment("NML_CORE")
	_core_env = BattleSim._core_env
	OS.set_environment("NML_CORE", "1")
	BattleSim._core_env = -1
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	SoloController.mission_reset("end", {})   # statics: never leak this mission into the next suite
	OS.set_environment("NML_CORE", _env_core)
	BattleSim._core_env = _core_env
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## battle_sim_capture_test.gd:10-24 (copy, don't import).
func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## A round_vp state at 3:1 with Grunts carrying a distinct 16" charge band, Tank carrying no `bands` at all.
func _plain() -> Dictionary:
	SoloController.mission_reset("round_vp", {"majority": "end"})
	SoloController.mission_vp = [3, 1]
	var grunts := _unit(2, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0)], "Grunts")
	var tank := _unit(1, [Vector3(20.0 * IN2M, 0, 0)], "Tank")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Grunts": grunts, "Tank": tank}
	var objs := [Vector3(10.0 * IN2M, 0, 0)]
	var state := BattleSim.capture(army, func() -> Array: return objs, func(_i: int) -> int: return 0, 2, 4)
	var plain := BattleSim.state_to_plain(state)
	(plain["units"]["Grunts"] as Dictionary)["bands"] = {"advance": 6.0, "rush": 12.0, "charge": 16.0}
	(plain["units"]["Tank"] as Dictionary).erase("bands")
	return plain


func test_the_core_holds_the_vp_ledger_and_the_charge_band(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "needs the NmlCore extension") -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var plain := _plain()
	assert_that(plain.get("vp")).is_equal([3, 1])   # the fixture really sends the ledger
	var h: int = core.capture_plain(plain)
	assert_int(h).override_failure_message("capture_plain: " + str(core.last_error())).is_not_equal(0)
	var got: Dictionary = core.plain_of(h)
	assert_bool(got.has("vp")).override_failure_message("the core holds no VP ledger (vp = None)").is_true()
	assert_that(got.get("vp")).is_equal([3, 1])
	assert_str(str((got.get("vp_flavour", {}) as Dictionary).get("majority", ""))).is_equal("end")
	var bands: Dictionary = (got["units"]["Grunts"] as Dictionary).get("bands", {})
	assert_bool(bands.has("charge")).override_failure_message("the core dropped the distinct charge band").is_true()
	assert_float(float(bands.get("charge", -1.0))).is_equal(16.0)
	assert_float(float(bands.get("rush", -1.0))).is_equal(12.0)
	assert_bool((got["units"]["Tank"] as Dictionary).has("bands")).override_failure_message(
		"a unit sent without bands must come back without them (node-corpus key set)").is_false()
	core.release_all()
