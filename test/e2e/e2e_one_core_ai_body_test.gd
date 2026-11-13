extends GdUnitTestSuite
## One-core P3 step 43: the AI smoke. Flag on, batch: the real AI body (`_solo_activate_one_ai`) plays two plain armies of
## three units for 20 seeds. Every call activates a unit, the core resolves at least one volley per seed
## (`CoreActivation.ai_runs`), it refuses none (`ai_refusals`), and every capture is released again. A script error fails
## the case (gdUnit reports script errors as failures); the gate run greps the log for SCRIPT ERROR too.
## Real: the main scene, NmlCore, the AI's decision, move and volley code. Constructed: plain units (ParityTable), and no
## "Incoming fire!" card can wait for a click (R5): both seats AI, or this table's units roll their saves without it.
## NML_ONE_CORE_SEEDS overrides the 20 seeds.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}


## The REAL NetworkManager with its transport swapped out (core_activation_mp_test's WireNet): frames are recorded.
class WireNet extends "res://scripts/network_manager.gd":
	var wire: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		wire.append({"t": type, "p": payload, "to": target_peer})
		return true
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_my_peer_id() -> int:
		return 1
	func get_my_player_slot() -> int:
		return 1


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	if _main != null:
		_main.network_manager = _real_net
		_main.radial_menu_controller.network_manager = _real_net
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Seed `s`'s armies: three plain AI units (seat 2) and three plain units of seat 1, rifles at 24" (one AI unit 12").
func _armies(s: int) -> Array:
	var out: Array = []
	for u in [[2, "Att A", 10, -10.0, -18.0, 24], [2, "Att B", 5, -10.0, -3.0, 12], [2, "Att C", 5, -10.0, 12.0, 24],
			[1, "Def A", 5, 6.0 + s % 5, -18.0, 24], [1, "Def B", 5, 10.0, -3.0, 24], [1, "Def C", 5, 20.0, 12.0, 24]]:
		var gu := ParityTable._make_unit(_main, SIDE.merged({"player": u[0], "name": u[1], "models": u[2], "x_in": u[3]}),
			{"name": "Rifle", "range_in": u[5], "attacks": 1, "count": u[2], "rules": []})
		for m in gu.models:
			(m as ModelInstance).node.global_position.z += float(u[4]) * INCH
		out.append(gu)
	return out


## The seed's units off the table again (the next seed rebuilds them).
func _clear(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


## RED: `is_plain` false -> no capture, no core volley -> every seed "no volley went through the core".
func test_the_ai_body_shoots_plain_volleys_through_the_core(timeout := 900000) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var core: Object = (_main.solo_controller as SoloController)._core_node_ready()
	var live: int = core.live_handles()
	var bad: Array = []
	for s in seeds:
		var units := _armies(s)
		_main.seed_tray_rng(s)
		var runs_before := CoreActivation.ai_runs
		for i in 3:
			var u: GameUnit = await _main._solo_activate_one_ai()
			if u == null or not u.is_activated:
				bad.append("seed %d: call %d activated %s" % [s, i, u.get_name() if u != null else "no unit"])
		if CoreActivation.ai_runs == runs_before:
			bad.append("seed %d: no volley went through the core" % s)
		_clear(units)
	print("ONE_CORE_AI_BODY seeds=%d core_volleys=%d refusals=%d handles=%d/%d" % [seeds, CoreActivation.ai_runs,
		CoreActivation.ai_refusals, core.live_handles(), live])
	assert_int(CoreActivation.ai_refusals).override_failure_message("the core refused an AI volley").is_equal(0)
	assert_int(core.live_handles()).override_failure_message("a capture leaked").is_equal(live)
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 10))).is_empty()


## In an agreed Automatic room with an AI seat (a recording stub for the wire), every AI activation the core resolved
## sends exactly one `activation_check` for its unit, and one the core did not resolve sends none. Lane H's step 51 adds
## the `CoreActivation.announce` call to `run_ai`; until then this case is skipped (RED without that call).
func test_each_core_ai_activation_in_a_room_sends_one_check(timeout := 300000, do_skip := true,
		skip_reason := "step 51 adds CoreActivation.announce to run_ai; unskip this case then") -> void:
	var net: WireNet = auto_free(WireNet.new())
	net.is_host = true
	net.army_manager = _main.opr_army_manager
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.solo_ai_slots = {2: true}
	_main._solo_auto_saves = true   # seat 1's units are this table's: their saves roll without the card
	_main.network_manager = net
	_main.radial_menu_controller.network_manager = net
	var bad: Array = []
	var checks_sent := 0
	for s in 3:
		var units := _armies(s)
		_main.seed_tray_rng(s)
		for i in 3:
			var runs := CoreActivation.ai_runs
			net.wire.clear()
			var u: GameUnit = await _main._solo_activate_one_ai()
			var checks: Array = net.wire.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "activation_check")
			var want := 1 if CoreActivation.ai_runs > runs else 0
			checks_sent += checks.size()
			if checks.size() != want or (want == 1 and str(checks[0]["p"]["unit"]) != (u.unit_id if u != null else "")):
				bad.append("seed %d call %d: %d core volley(s), checks %s" % [s, i, want,
					checks.map(func(f: Dictionary) -> String: return str(f["p"]["unit"]))])
		_clear(units)
	assert_int(checks_sent).override_failure_message("no AI activation sent a check").is_greater(0)
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 10))).is_empty()
