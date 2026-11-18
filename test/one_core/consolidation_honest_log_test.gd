extends GdUnitTestSuite
## The table's Consolidation Moves (GF v3.5.1 p.9) write the battle-log line of what REALLY happened.
##
## `_solo_consolidate_melee` used to log "moves back 1\"" / "consolidates up to 3\"" whenever the move executor
## published a route, even when the placement gate then handed every model back to its start (a dense 10-model
## rank has no legal end spot for the planner's per-model flow): the line claimed a move that never happened, and
## the models glided out and back on screen. The core writes its consolidation line only for a move that moved.
## The boards are the melee golden's own (test/parity/parity_table_melee.gd): the attacker in base contact after
## its charge, the defender beside it, one lone enemy far down the table as the winner's goal.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityMelee := preload("res://test/parity/parity_table_melee.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

const BYSTANDER := {"key": "by", "player": 2, "name": "By", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 20.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "robot_legions",
	"rules": []}
const HERO := {"key": "att_hero", "player": 1, "name": "AttHero", "models": 1, "quality": 3, "defense": 4,
	"tough": 3, "x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": ["Hero"], "stand_x_in": 6.74, "stand_z_in": -1.2,
	"weapon": {"name": "Hero Blade", "range_in": 0, "attacks": 3, "count": 1, "rules": []}}
const MOVED_EPS_IN := 0.01

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _saved_flag: String


func before_test() -> void:
	BattleSim._core_env = 0   # pinned to the GDScript AI, like the golden witness suites
	_saved_flag = OS.get_environment("NML_ONE_CORE_ACTIVATION")
	OS.set_environment("NML_ONE_CORE_ACTIVATION", "0")
	CoreActivation._env = -1
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	assert_bool(Harness.configure(_main)).override_failure_message(
		"the kill switch is on: this suite must run the old table path").is_true()


func after_test() -> void:
	BattleSim._core_env = -1
	OS.set_environment("NML_ONE_CORE_ACTIVATION", _saved_flag)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## What one consolidation did: the battle-log lines, and how many models of the chain (host + joined hero) stand
## somewhere else afterwards.
func _consolidate(attacker_models: int, z_step_in: float, kill_defender: bool, hero: bool = false) -> Dictionary:
	var sc := {"attacker": Harness._with(Harness.MELEE_ATTACKER, {"models": attacker_models, "z_step_in": z_step_in}),
		"defender": Harness.MELEE_DEFENDER, "charge": Harness.CHARGE, "weapon": Harness.BLADE,
		"defender_weapon": Harness.DEF_BLADE}
	var pair: Array = ParityMelee._units(_main, sc, {})
	var att := pair[0] as GameUnit
	var dfn := pair[1] as GameUnit
	var chain: Array = [att, dfn]
	chain.append(ParityTable._make_unit(_main, BYSTANDER, {}))   # the survivor's "next target"; never fights
	if hero:
		chain.append(_join_hero(att))
	if kill_defender:
		Harness._kill_models(dfn, dfn.models.size())
	var seats: Dictionary = (_main.solo_ai_slots as Dictionary).duplicate()
	_main.solo_ai_slots = {1: true, 2: true}   # an AI-owned charger: the back-step is automatic, no board prompt
	var lines: Array = []
	var tap := Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	var before := _spots(att, hero)
	await _main._solo_consolidate_melee(att, dfn, true)
	_main.battle_log.entry_added.disconnect(tap)
	_main.solo_ai_slots = seats
	var after := _spots(att, hero)
	var moved := 0
	for i in before.size():
		if (before[i] as Vector2).distance_to(after[i] as Vector2) > MOVED_EPS_IN:
			moved += 1
	Harness._free_units(_main, chain)
	await _main.get_tree().process_frame
	return {"lines": lines, "moved": moved, "models": before.size()}


## The host's models, then its joined hero's, in inches.
func _spots(host: GameUnit, with_hero: bool) -> Array:
	var out: Array = []
	var units: Array = [host]
	if with_hero:
		units.append_array(host.get_attached_heroes())
	for u in units:
		for m in (u as GameUnit).models:
			var nd := (m as ModelInstance).node as Node3D
			out.append(Vector2(nd.global_position.x, nd.global_position.z) / 0.0254)
	return out


## A hero standing in base contact beside its host's first model, joined the way the army import does it.
func _join_hero(host: GameUnit) -> GameUnit:
	var weapon: Dictionary = (HERO["weapon"] as Dictionary).duplicate(true)
	var hero := ParityTable._make_unit(_main, HERO, weapon)
	hero.unit_properties["base_size_round"] = roundi(float(HERO["base_radius_in"]) * 50.8)
	var nd := (hero.models[0] as ModelInstance).node as Node3D
	nd.global_position = Vector3(float(HERO["stand_x_in"]) * 0.0254, 0.0, float(HERO["stand_z_in"]) * 0.0254)
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	return hero


static func _count(lines: Array, needle: String) -> int:
	var n := 0
	for l in lines:
		if str(l).contains(needle):
			n += 1
	return n


func _report(r: Dictionary) -> String:
	return "moved %d of %d models, lines: %s" % [r["moved"], r["models"], str(r["lines"])]


# --- neither side destroyed: the charger backs off 1" (if possible) --------------------------------------------------

func test_a_back_step_that_moves_nothing_is_not_logged_as_a_move() -> void:
	# A 10-model rank (hero joined or not) in base contact has no legal end spot for the planner: nothing moves.
	for hero in [false, true]:
		var r := await _consolidate(10, 1.3, false, hero)
		assert_int(int(r["moved"])).override_failure_message(
			"premise: this board is a pinned no-move case (hero=%s) - %s" % [hero, _report(r)]).is_equal(0)
		assert_int(_count(r["lines"], "moves back 1")).override_failure_message(
			"the log claims a back-step that did not happen (hero=%s) - %s" % [hero, _report(r)]).is_equal(0)
		assert_int(_count(r["lines"], "Consolidation:")).override_failure_message(
			"the rule was applied, so it must still log a line (hero=%s) - %s" % [hero, _report(r)]).is_equal(1)
		assert_int(_count(r["lines"], "stays put")).override_failure_message(
			"the held ground is named (hero=%s) - %s" % [hero, _report(r)]).is_equal(1)


func test_a_back_step_that_moves_is_logged_as_a_move() -> void:
	var r := await _consolidate(3, 1.2, false)
	assert_bool(int(r["moved"]) > 0).override_failure_message(
		"premise: a 3-model charger backs off on this board - %s" % _report(r)).is_true()
	assert_int(_count(r["lines"], "moves back 1")).override_failure_message(_report(r)).is_equal(1)
	assert_int(_count(r["lines"], "stays put")).override_failure_message(_report(r)).is_equal(0)


# --- one side destroyed: the survivor may move up to 3" ---------------------------------------------------------------

func test_a_winner_that_moves_nothing_does_not_log_a_consolidation_move() -> void:
	var r := await _consolidate(10, 1.3, true)
	assert_int(int(r["moved"])).override_failure_message(
		"premise: this board is a pinned no-move case - %s" % _report(r)).is_equal(0)
	assert_int(_count(r["lines"], "consolidates up to 3")).override_failure_message(
		"the log claims a consolidation move that did not happen - %s" % _report(r)).is_equal(0)
	assert_int(_count(r["lines"], "holds its ground")).override_failure_message(
		"the held ground is named - %s" % _report(r)).is_equal(1)


func test_a_winner_that_moves_is_logged_as_a_move() -> void:
	var r := await _consolidate(3, 1.2, true)
	assert_bool(int(r["moved"]) > 0).override_failure_message(
		"premise: a 3-model winner consolidates on this board - %s" % _report(r)).is_true()
	assert_int(_count(r["lines"], "consolidates up to 3")).override_failure_message(_report(r)).is_equal(1)
	assert_int(_count(r["lines"], "holds its ground")).override_failure_message(_report(r)).is_equal(0)
