extends GdUnitTestSuite
## Wave 3 S4-U2 / S4-U4 — the Godot seam must fold the table's per-unit LEDGER into the Rust core's state.
## `AiActRecorder._stamp_gate_reads` stamps `ledger` on every unit of the live plain state
## (solo_controller.gd:3533), but the state reader never read it: a once-per-game ability the table had
## already spent looked fresh to the in-game search, and a live spell buff was invisible.
##
## THE BEHAVIOUR. Second Wind (Inquisitorial Agent): once per GAME, when the round would close, an already
## activated carrier activates again (`sim::second_wind_candidate`, fired inside `resolve`). A carrier whose
## ledger says `second_wind_used` must stay activated. The control proves the scene really fires it.
##
## THE PAIRING (S4-U4). The live header is `AiActRecorder._header_line`, which carries `books`; the core must
## then read the recorded bands as prefolded (`acts::header_of`'s rule), or the grants fold twice.
##
## WHAT IS REAL vs CONSTRUCTED. Real: scenes/main.tscn, BattleSim.capture / state_to_plain, the recorder's
## `_stamp_gate_reads` / `_ledger_of` / `_header_line`, the rules registry, the NmlCore extension. Constructed:
## three bare units and their flags. The spell record carries FLOAT numbers, the shape a unit has after a
## save/load (`JSON.parse_string` reads every number as float).

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
	OS.set_environment("NML_CORE", _env_core)
	BattleSim._core_env = _core_env
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## battle_sim_capture_test.gd:10-24 (copy, don't import), plus the registry keys the core's statics read.
func _unit(pid: int, pos: Vector3, uid: String, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "human_inquisition"}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	return u


## Agent (Second Wind carrier) and Foe have activated; Other is the last unit that can still activate.
func _state(spent: bool) -> Dictionary:
	var agent := _unit(1, Vector3.ZERO, "Agent", ["Inquisitorial Agent"])
	agent.is_activated = true
	agent.unit_properties["spell_records"] = [{"hit_mod": 1.0, "spell": "X", "duration": "once",
		"scope": "", "beneficiary": ""}]
	if spent:
		agent.unit_properties["second_wind_used"] = true
	var other := _unit(1, Vector3(3.0 * IN2M, 0, 0), "Other", [])
	var foe := _unit(2, Vector3(30.0 * IN2M, 0, 0), "Foe", [])
	foe.is_activated = true
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Agent": agent, "Other": other, "Foe": foe}
	return BattleSim.capture(army, func() -> Array: return [], Callable(), 2, 4)


## The live seam's plain form (solo_controller.gd:3532-3533) with the static profile spliced in.
func _plain(state: Dictionary) -> Dictionary:
	var plain := BattleSim.state_to_plain(state)
	AiActRecorder._stamp_gate_reads(state, plain)
	return plain


## Other holds, the round would close, the core decides Second Wind; answers Agent's `activated` after it.
func _agent_activated_after_last_hold(core: Object, spent: bool) -> bool:
	var plain := _plain(_state(spent))
	var h: int = core.capture_plain(plain)
	assert_int(h).override_failure_message("capture_plain: " + str(core.last_error())).is_not_equal(0)
	var h2: int = core.resolve(h, {"kind": AiDecision.Action.HOLD, "unit": "Other"})
	assert_int(h2).override_failure_message("resolve: " + str(core.last_error())).is_not_equal(0)
	var got: Dictionary = core.plain_of(h2)
	core.release_all()
	return bool((got["units"]["Agent"] as Dictionary).get("activated", false))


func test_a_fresh_carrier_gets_second_wind() -> void:
	assert_bool(ClassDB.class_exists("NmlCore")).override_failure_message(
		"NmlCore extension not loaded — run core/install_gdextension.sh").is_true()
	var core: Object = ClassDB.instantiate("NmlCore")
	assert_bool(_agent_activated_after_last_hold(core, false)).override_failure_message(
		"control: an unspent carrier must be re-activated by Second Wind").is_false()


func test_a_spent_second_wind_stays_spent_in_the_core() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var plain := _plain(_state(true))
	assert_bool(bool(plain["units"]["Agent"]["ledger"].get("second_wind_used", false))).is_true()
	assert_bool(_agent_activated_after_last_hold(core, true)).override_failure_message(
		"the core re-granted a Second Wind the table already spent (ledger not folded)").is_true()
	assert_bool(Array(core.dropped_keys()).has("ledger")).override_failure_message(
		"the ledger failed to parse").is_false()


func test_the_live_header_marks_the_bands_prefolded() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var state := _state(false)
	var head: Dictionary = AiActRecorder._header_line(state, Callable())
	assert_bool(head.has("books")).is_true()
	assert_bool(core.set_game_header(head)).override_failure_message(
		"set_game_header: " + str(core.last_error())).is_true()
	assert_bool(bool((core.seams() as Dictionary).get("bands_prefolded", false))).override_failure_message(
		"a header carrying books must read its bands as prefolded").is_true()
