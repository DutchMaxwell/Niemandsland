extends GdUnitTestSuite
## One core P4.D-37b: the human door lets the core strike for a Strafing bearer. Until now the player's drop was struck on the
## table (`_solo_human_strafing`, at the drop); a core unit with an open activation now holds its trails in the session, and the
## activation's FIRST resolution (Fire, or End when nothing is shot) carries the move-through volley: the strike moves from the
## drop to that resolution, the dice and the casualties do not change. Seed for seed against the table's own run (flag off, the
## strike at the drop): survivors, Shaken, the tray RNG after and the battle-log lines (as a multiset).
## Real: the main scene, NmlCore, the window door `_run_human_attack`, the End door, `attacked_unit_drag_refused` (the drop door).
## Constructed: a Strafing bearer of seat 1 (human) against 20 defenders of seat 2 (AI), the Rifle volley after an Advance; the
## shipped slice. Not compared: the table's models-in-sight line and the core's announce line (the Q17 pair).
## NML_ONE_CORE_SEEDS overrides 20.
## PLAN_FIRST_DELETION 34 FT-C4: the table arm left before step 31 (the AI table resolver retires); door values are pinned as
## literals read on main af5c83610.

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
const STRAFE_GUN := {"name": "Strafe Gun", "range_in": 24, "attacks": 2, "count": 10, "rules": ["Crossing Strike"]}
## The defender's alive models per seed (0-19), read on main from the table run's survivors.
const WANT_ALIVE_FIRE := [12, 10, 14, 11, 10, 8, 10, 13, 14, 11, 12, 14, 12, 11, 13, 12, 13, 16, 7, 13]
const WANT_ALIVE_END := [14, 14, 16, 15, 13, 13, 12, 14, 16, 14, 14, 16, 16, 14, 14, 15, 18, 18, 12, 15]
## The wounded models in all, from the `HUMAN_STRAFE ... hurt=` line read on main.
const WANT_HURT_FIRE := 164
const WANT_HURT_END := 107

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
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main._solo_fast = true
	_main._autosave_controller.set_lesson_paused(true)


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One run on fresh units. `rifle`: the bearer also carries a Rifle and shoots after the Advance (Fire), else it ends its
## activation (End). `core_run`: flag on, the Start/drop/Fire/End doors; else the table's own path. Returns what the comparison
## reads plus how many strike sentences stood before the Fire/End and in all.
func _run(s: int, rifle: bool, core_run: bool, foe_rules := []) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Att", "models": 10, "x_in": 0.0}), STRAFE_GUN)
	if rifle:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Rifle"
		w.range_value = 24
		w.attacks = 1
		w.count = 10
		(att.source_data as OPRApiClient.OPRUnit).weapons.append(w)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 20, "x_in": 3.0, "rules": foe_rules}, true), RIFLE.merged({"count": 20}, true))
	for i in foe.models.size():   # a uniform lattice ties the casualty order on a float's last bit: nudge each model
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	foe.is_activated = true   # the AI has nothing left to do: no reply, in either run
	var spare := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Spare", "models": 1, "x_in": 40.0}), {})
	for m in att.models:
		m.node.set_meta("network_id", 901 + att.models.find(m))
		m.node.set_meta("model_instance", m)
	CoreActivation._env = 1 if core_run else 0
	if core_run:
		assert_bool(_main.core_activation_start(att)).override_failure_message("seed %d: no Start" % s).is_true()
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var moves: Array = []
	for m in att.get_alive_models():   # every model 6" toward and through the defender line: the player's drop
		var from: Vector3 = (m as ModelInstance).node.global_position
		var to := Vector3(from.x + 6.0 * INCH, from.y, from.z)
		(m as ModelInstance).node.global_position = to
		moves.append({"node": (m as ModelInstance).node, "inches": 6.0, "path": PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])})
	att.unit_properties["moved_round"] = 1   # what the drop door stamps (`_on_units_dropped`)
	if core_run:
		assert_bool(_main.attacked_unit_drag_refused(att, 6.0)).override_failure_message("seed %d: the drop was refused" % s).is_false()
	await _main._solo_human_strafing(moves)   # the drop door's strike: the table's, unless the core holds the activation
	var at_drop := lines.filter(func(l: String) -> bool: return l.contains("passes over Def")).size()
	if rifle:
		await _main._run_human_attack(att, foe, false)
	elif core_run:
		assert_bool(await CoreActivation.end(_main, att)).override_failure_message("seed %d: the End stayed open" % s).is_false()
	_main.battle_log.entry_added.disconnect(tap)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	# The strike's attack dice: the table rolls them under the AI label ("AI (Att): ..."), the core under the player's own ("You: ...");
	# the faces and the hits that follow are compared as they stand.
	var rest := lines.filter(func(l: String) -> bool: return not (l.contains("with line of sight + range") or l.begins_with("Att fires at ")
		or l == "Att begins its activation.")).map(func(l: String) -> String: return l.replace("AI (Att): ", "<attacker>: ").replace("You: ", "<attacker>: "))
	rest.sort()
	var out := {"survivors": survivors, "shaken": foe.is_shaken, "rng": _main._tray_rng.state, "lines": rest, "at_drop": at_drop,
		"strikes": lines.filter(func(l: String) -> bool: return l.contains("passes over Def")).size(),
		"core_unit": CoreActivation.is_core_unit(_main, att), "table_struck": CoreActivation.table_struck(att)}
	CoreActivation.close_session(_main, att.unit_id)
	for u in [att, foe, spare]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	return out


func _sweep(name: String, rifle: bool, foe_rules := [], want_alive: Array = [], want_hurt := -1) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 20
	var table_strikes: bool = not foe_rules.is_empty()   # a crossed enemy that is no plain target: the drop hands the strike to the table
	var bad: Array = []
	var hurt := 0
	if not table_strikes and seeds > want_alive.size():
		bad.append("%d seeds exceed the %d pinned values" % [seeds, want_alive.size()])
	for s in seeds:
		var core := await _run(s, rifle, true, foe_rules)
		hurt += 20 - (core["survivors"] as Array).size()
		if not core["core_unit"]:
			bad.append("seed %d: the bearer is no core unit in the door run" % s)
		# The strike moved from the drop to the Fire / End: none at the drop (one when the drop hands it to the table), one in all.
		if int(core["at_drop"]) != (1 if table_strikes else 0) or int(core["strikes"]) != 1:
			bad.append("seed %d: strikes at the drop / in all: core %d/%d" % [s, core["at_drop"], core["strikes"]])
		if core["table_struck"] != table_strikes:
			bad.append("seed %d: the drop handed the strike to the table: %s (want %s)" % [s, core["table_struck"], table_strikes])
		if not table_strikes:
			if s < want_alive.size() and (core["survivors"] as Array).size() != int(want_alive[s]):
				bad.append("seed %d: survivors %d (want %d)" % [s, (core["survivors"] as Array).size(), int(want_alive[s])])
	print("HUMAN_STRAFE %s seeds=%d hurt=%d mismatches=%d" % [name, seeds, hurt, bad.size()])
	if not table_strikes:
		# Nothing about hurt in the crossed case: the strike the drop hands to the table is held at step 31.
		var want := want_hurt
		if seeds != want_alive.size():
			want = 0
			for alive in want_alive.slice(0, seeds):
				want += 20 - int(alive)
		assert_int(hurt).override_failure_message("the defender's losses moved: want %d" % want).is_equal(want)
	assert_array(bad).override_failure_message("the door run:\n" + "\n".join(bad.slice(0, 10))).is_empty()


## Advance through the defender, then Fire with a Rifle: the strike and the volley in the core's one call. RED: put `not
## moves_through` back into `is_core_unit` (the bearer is no core unit) -> `core_unit` false and the strike stays at the drop.
func test_a_human_strafe_bearer_strikes_with_its_fire() -> void:
	await _sweep("fire", true, [], WANT_ALIVE_FIRE, WANT_HURT_FIRE)


## No shot: the End door's call carries the strike. RED: drop the `continue` in `_solo_human_strafing` -> the table strikes at
## the drop AND the core at the End (two strike sentences).
func test_a_human_strafe_bearer_strikes_with_its_end() -> void:
	await _sweep("end", false, [], WANT_ALIVE_END, WANT_HURT_END)


## P4.D-37c: every enemy the drop's legs cross must be a plain target. A crossed Grounded Protection unit (the deny slice refuses
## the name, H-30) hands the strike to the table at the drop, and the activation's End is the table's too: ONE strike, at the
## drop. RED (the flag dropped from `drop_refused`): the core strikes the Grounded Protection unit at the End, after the table's
## strike at the drop; or without the table's strike, a strike the table never made.
func test_a_crossed_enemy_with_an_unsupported_rule_hands_the_strike_to_the_table() -> void:
	await _sweep("end, crossed Grounded Protection", false, ["Grounded Protection"])
