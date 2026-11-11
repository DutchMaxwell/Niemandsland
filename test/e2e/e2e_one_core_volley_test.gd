extends GdUnitTestSuite
## One-core Phase 0 spike gate: a plain shooting volley (no special rules) resolved by the
## Rust core on the TABLE's own tray faces (CoreExchange.drive) lands what the table's own
## resolver (`_run_ai_shooting`) lands from the same seed: same survivors, same Shaken
## flag and the same number of tray draws, seed for seed.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEEDS := 1000

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true   # tray faces from the seeded tray RNG, no physics settle


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _armed(pid: int, unit_name: String, models: int, x_in: float) -> GameUnit:
	var pos: Array = []
	for i in range(models):
		pos.append(Vector3(x_in * INCH, 0.0, i * 1.0 * INCH))
	var u: GameUnit = E2EBoot.make_unit(_main, pid, unit_name, pos)
	u.unit_properties["special_rules"] = []
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 1
	w.count = models
	ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_core_volley_equals_table_volley(
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "needs the NmlCore extension",
		timeout := 600000) -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var bad: Array = []
	var total_us := 0
	var total_steps := 0
	var max_us := 0
	for s in range(SEEDS):
		_main.opr_army_manager.game_units.clear()
		var shooter := _armed(1, "Shooter%d" % s, 10, 0.0)
		var foe := _armed(2, "Foe%d" % s, 5, 12.0)
		var state := BattleSim.capture(_main.opr_army_manager, func() -> Array: return [], Callable(), 1, 4)
		var plain := BattleSim.state_to_plain(state)
		AiActRecorder._stamp_gate_reads(state, plain)
		var h: int = core.capture_plain(plain)
		assert_int(h).override_failure_message("capture_plain: " + str(core.last_error())).is_not_equal(0)
		_main.seed_tray_rng(s)
		var got: Dictionary = await CoreExchange.drive(_main, core,
			h, {"kind": AiDecision.Action.HOLD, "unit": shooter.unit_id, "shoot": foe.unit_id})
		var core_draws: int = _main._tray_rng.state
		if str(got.get("step", "")) != "done":
			bad.append("seed %d: %s" % [s, str(got)])
			continue
		var cu: Dictionary = core.plain_of(int(got["handle"]))["units"][foe.unit_id]
		var core_alive: int = int(cu.get("alive", -1))
		var core_shaken := bool(cu.get("shaken", false))
		total_us += int(got["core_us"])
		total_steps += int(got["steps"])
		max_us = maxi(max_us, int(got["core_us"]))
		_main.seed_tray_rng(s)
		await _main._run_ai_shooting({"unit": shooter, "moved": false})
		var table_draws: int = _main._tray_rng.state
		if foe.get_alive_count() != core_alive or foe.is_shaken != core_shaken or table_draws != core_draws:
			bad.append("seed %d: table alive %d shaken %s | core alive %d shaken %s | draws equal %s | faces %s" % [
				s, foe.get_alive_count(), foe.is_shaken, core_alive, core_shaken, table_draws == core_draws, got["faces"]])
		core.release_all()
	print("ONE_CORE_VOLLEY seeds=%d mismatches=%d core_us_total=%d steps_total=%d mean_us_per_exchange=%.1f max_us=%d" % [
		SEEDS, bad.size(), total_us, total_steps, float(total_us) / SEEDS, max_us])
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()
