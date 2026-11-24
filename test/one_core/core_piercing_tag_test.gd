extends GdUnitTestSuite
## One core P4.D-30b1: a volley the core resolves at a target that carries Piercing Tag markers. The core spends and applies
## the pool in its own copy; the table's pool and the spend line used to stay behind (the next volley then spent the same
## marker again). The door now runs the table's own spend (`CoreActivation._spend_tag`), so the table's pool, the MP sync and
## the line are what a table volley leaves. Seed for seed against the table's volley: the pool, the survivors, Shaken, the tray
## RNG after, and the battle-log lines (as a multiset: the core's declaration line stands where the table's sight line does).
## Real: the main scene, NmlCore, both doors (`_run_ai_shooting`, `_run_human_attack`), the table's volley and spend.
## Constructed: plain units (ParityTable), the pool written onto the target's properties. NML_ONE_CORE_SEEDS overrides 20.
## PLAN_FIRST_DELETION 34 FT-C4: the table arm left before step 31 (the AI table resolver retires); door values are pinned as
## literals read on main af5c83610.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
## The target's alive models per seed (0-4), read on main from the table volley.
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_SPEND := [0, 0, 3, 3, 1, 2, 2, 2, 3, 4, 2, 5, 4, 3, 0, 3, 1, 3, 2, 2]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_STANDING := [0, 0, 3, 3, 1, 2, 2, 2, 3, 4, 2, 5, 4, 3, 0, 3, 1, 3, 2, 2]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_NO_POOL := [0, 2, 3, 5, 3, 3, 3, 2, 4, 4, 2, 5, 5, 4, 1, 3, 1, 4, 3, 2]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_BELOW_73 := [0, 0, 1, 2, 0, 0, 0, 0, 2, 4, 2, 4, 3, 3, 0, 2, 1, 3, 2, 0]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
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
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
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


## One volley (10 Rifles at 5 models 12" away; both plain, the target carries a profile) on tray seed `s`, the target's pool
## `markers` of `source`. `door` "ai" = `_run_ai_shooting` (seat 2 shoots seat 1), "human" = `_run_human_attack` (seat 1
## shoots seat 2). `core_run`: the door goes to the core. Returns what the comparison reads.
func _volley(door: String, s: int, markers: int, source: String, core_run: bool) -> Dictionary:
	var ai := door == "ai"
	_main.solo_ai_slots = {2: true} if not ai else {1: true, 2: true}
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2 if ai else 1, "name": "Att", "models": 10, "x_in": 0.0}), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1 if ai else 2, "name": "Def", "models": 5, "x_in": 12.0}),
		RIFLE.merged({"count": 5}))
	if markers > 0:
		foe.unit_properties["piercing_tag_markers"] = markers
		foe.unit_properties["piercing_tag_source"] = source
	foe.is_activated = true
	var spare := ParityTable._make_unit(_main, SIDE.merged({"player": 1 if not ai else 2, "name": "Spare", "models": 1, "x_in": 40.0}), {}) \
		if not ai else null
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	var h := 0
	if ai:
		h = CoreActivation.capture(_main) if core_run else 0
		_main._solo_core_ai_h = h
		await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
		_main._solo_core_ai_h = 0
		if h != 0:
			(_main.solo_controller as SoloController)._core_node_ready().release(h)
	else:
		CoreActivation._env = 1 if core_run else 0
		if core_run:
			assert_bool(_main.core_activation_start(att)).override_failure_message("seed %d: no Start" % s).is_true()
		await _main._run_human_attack(att, foe, false)
		CoreActivation.close_session(_main, att.unit_id)
		CoreActivation._env = 1
	_main.battle_log.entry_added.disconnect(tap)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	var spent := lines.filter(func(l: String) -> bool: return l.begins_with("Piercing Tag") or l.begins_with("Piercing Target"))
	# Not compared: the declaration line pair (the core's announce against the table's sight line), the Start door's line (core
	# run only) and the AI's opening line of a game (said once, by whichever run is first).
	var rest := lines.filter(func(l: String) -> bool: return not (l.begins_with("Att fires at ") or l.contains("with line of sight + range")
		or l == "Att begins its activation." or l.begins_with("NACHTMAHR")))
	rest.sort()
	var out := {"alive": foe.get_alive_count(), "survivors": survivors, "shaken": foe.is_shaken, "rng": _main._tray_rng.state, "lines": rest,
		"spent": spent, "pool": int(foe.unit_properties.get("piercing_tag_markers", 0)),
		"core": (CoreActivation.ai_runs - runs) if ai else lines.has("Att fires at Def")}
	_free([att, foe] + ([spare] if spare != null else []))
	return out


func _sweep(door: String, markers: int, source: String, want_pool: int, want_spent: int, want_alive: Array = []) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var compare := door == "human"
	var bad: Array = []
	var hurt := 0
	if not compare and seeds > want_alive.size():
		bad.append("%d seeds exceed the %d pinned values" % [seeds, want_alive.size()])
	for s in seeds:
		var table: Dictionary = {}
		if compare:
			table = await _volley(door, s, markers, source, false)
		var core := await _volley(door, s, markers, source, true)
		hurt += 5 - (core["survivors"] as Array).size()
		if not core["core"]:
			bad.append("seed %d: the core door did not take the volley" % s)
		if compare and table["core"]:
			bad.append("seed %d: the table run took the volley too" % s)
		if compare:
			for k in ["survivors" if AiActRecorder.rules_epoch >= 73 else "alive", "shaken", "rng", "pool", "lines"]:   # below 73 the table and the core pick different casualties
				if table[k] != core[k]:
					bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
		else:
			if s < want_alive.size() and int(core["alive"]) != int(want_alive[s]):
				bad.append("seed %d: alive %d (want %d)" % [s, core["alive"], int(want_alive[s])])
		if int(core["pool"]) != want_pool or (core["spent"] as Array).size() != want_spent:
			bad.append("seed %d: pool %d (want %d), spend lines %s (want %d)" % [s, core["pool"], want_pool, core["spent"], want_spent])
	print("PIERCING_TAG door=%s markers=%d %s seeds=%d hurt=%d mismatches=%d" % [door, markers, source, seeds, hurt, bad.size()])
	assert_int(hurt).override_failure_message("no seed hurt the target: the sweep compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("the door run:\n" + "\n".join(bad.slice(0, 10))).is_empty()


## The 3.6 rule (epoch 73+): one token per volley, +1 AP. RED: remove the `_spend_tag` calls -> the pool stays 2 and no line.
func test_the_ai_door_spends_one_token(timeout := 600000) -> void:
	await _sweep("ai", 2, "", 1, 1, WANT_ALIVE_SPEND)


func test_the_human_door_spends_one_token(timeout := 600000) -> void:
	await _sweep("human", 2, "", 1, 1)


## "Piercing Target" stands while its bearer lives: the pool is read, never spent; the line says so.
func test_a_standing_piercing_target_is_not_spent(timeout := 600000) -> void:
	await _sweep("ai", 2, "Piercing Target", 2, 1, WANT_ALIVE_STANDING)


## No pool: no line, nothing written.
func test_no_pool_no_line(timeout := 600000) -> void:
	await _sweep("ai", 0, "", 0, 0, WANT_ALIVE_NO_POOL)


## Before the 3.6 epoch the whole pool is spent at once (+AP per marker).
func test_below_epoch_73_the_whole_pool_is_spent(timeout := 600000) -> void:
	AiActRecorder.rules_epoch = 72
	await _sweep("ai", 2, "", 0, 1, WANT_ALIVE_BELOW_73)
