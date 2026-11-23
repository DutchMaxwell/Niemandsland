extends GdUnitTestSuite
## meleefix drift guard: the table's consolidation goal (`SoloController.consolidation_goal_of`, the AI round planner's pick for a
## melee winner's "may move up to 3 in") and the core's port of it (`NmlCore.consolidation_goal` -> `sim::planned_consolidation_goal`,
## read from PENDING_EPOCH_CONSOLIDATE_PLAN on) are two copies of one decision until the table's melee path is deleted (ticket
## H-CONS-TWIN). Each board below is a post-fight board: the scene is built, `CoreActivation.capture` takes the core's state from it,
## and both copies are asked with the inputs the door sends (`consolidation_input`).
## - The goal points must be EQUAL, Y included: both copies do the same f32 / f64 steps, so no tolerance is needed.
## - Every row must have a goal (a row where both copies have none proves nothing), and the goal must be the one its kind claims
##   (`_expect`), so a row cannot pass by falling through to the nearest enemy.
## - The boards hold what a real fight leaves: a wiped unit, a joined hero, an Aircraft, a unit in reserve, a Shaken unit, each
##   standing ON a marker the winner could take, so every filter of the control count is read.
## RED (proven 22.11., each fault planted alone in the table copy, every seed of the named kind fails): the lane sign (seize_lane),
## the tier order (greedy_contested), the garrison's friend check (garrison_shared), and the Shaken (shaken_holder), reserve
## (reserve_holder), joined-hero (joined_holder) and Aircraft (aircraft_holder) filters of `_units_controlling`. Its `is_destroyed`
## filter cannot be planted: a wiped unit has no alive positions, so it holds nothing either way (dead_holder / dead_contester).
## RED 22.11. (review): the spread switch off on BOTH copies fails all 8 greedy_spread rows (the booked marker keeps its tier);
## a joined hero moved to its host fails all 8 joined_holder rows (the board could no longer read the filter).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "dark_elf_raiders", "rules": [], "models": 3, "x_in": 0.0}
const MARKERS := [Vector2(-16.0, 0.0), Vector2(0.0, 0.0), Vector2(16.0, 0.0)]
const KINDS := ["seize", "seize_lane", "seize_held", "garrison", "garrison_shared", "fight", "greedy", "greedy_contested",
	"greedy_spread", "no_planner", "defender", "shaken_holder", "dead_holder", "reserve_holder", "joined_holder", "aircraft_holder",
	"dead_contester"]
const SEEDS := 8

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _owners: Array = [0, 0, 0]
var _markers: Array = []
var _epoch_before := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 2
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	var sc: SoloController = _main.solo_controller
	sc.objectives_provider = func() -> Array: return _markers
	sc.objective_owner_of = func(i: int) -> int: return int(_owners[i])
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation.reset_all(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A unit of `player` with 3 models around (x, z) inches; `rules` are its special rules.
func _unit(player: int, name: String, x: float, z: float, rules: Array = []) -> GameUnit:
	var g := ParityTable._make_unit(_main, SIDE.merged({"player": player, "name": name, "rules": rules}, true), {})
	_place(g, Vector3(x * INCH, 0.0, z * INCH))
	return g


func _place(g: GameUnit, at: Vector3) -> void:
	for i in g.models.size():
		(g.models[i] as ModelInstance).node.global_position = at + Vector3(1.1 * i * INCH, 0.0, 0.7 * i * INCH)


func _marker_kind(kind: String) -> bool:
	return kind in ["shaken_holder", "dead_holder", "reserve_holder", "joined_holder", "aircraft_holder", "dead_contester", "greedy_contested"]


## One board: `kind` picks the branch, `rng` the spots, owners and runners. "" when both copies agree on the goal the kind claims.
func _board(kind: String, rng: RandomNumberGenerator) -> String:
	var sc: SoloController = _main.solo_controller
	var j := func() -> float: return rng.randf_range(-3.0, 3.0)
	_markers = MARKERS.map(func(m: Vector2) -> Vector3: return Vector3((m.x + j.call()) * INCH, 0.0, (m.y + j.call()) * INCH))
	_owners = [rng.randi_range(0, 2), rng.randi_range(0, 2), rng.randi_range(0, 2)]
	var side := 1 if kind == "defender" else 2
	var foe := 3 - side
	var mi := rng.randi_range(0, 2)
	var win := _unit(side, "Win", rng.randf_range(-14.0, 14.0), rng.randf_range(-8.0, 8.0))
	var enemy_a := _unit(foe, "EnemyA", rng.randf_range(-20.0, 20.0), rng.randf_range(14.0, 20.0))
	var enemy_b := _unit(foe, "EnemyB", rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, -14.0))
	var friend := _unit(side, "Friend", rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, -14.0),
		["Aircraft"] if kind == "aircraft_holder" else [])
	var units: Array = [win, enemy_a, enemy_b, friend]
	var m: Vector3 = _markers[mi]
	var unfit := ""   # a board that cannot prove its kind (set below), reported after the units are freed
	# The holder kinds: a unit that does NOT count stands on marker `mi`, the winner 4.5 in south of it, so `mi` is the nearest
	# marker and wins exactly when the filter drops the holder. `dead_contester`: a wiped ENEMY on `mi` contests nothing;
	# `greedy_contested`: a live enemy on `mi` makes it contested, so a farther holdable marker wins.
	if _marker_kind(kind):
		_owners = [0, 0, 0]
		_place(win, m + Vector3(0.0, 0.0, -4.5 * INCH))
		var holder: GameUnit = enemy_a if kind in ["dead_contester", "greedy_contested"] else friend
		_place(holder, m + Vector3(0.0, 0.0, 0.5 * INCH))
		match kind:
			"shaken_holder":
				holder.is_shaken = true
			"dead_holder", "dead_contester":
				for mm in holder.models:
					(mm as ModelInstance).is_alive = false
			"reserve_holder":
				holder.unit_properties["ambush_reserve"] = true
			"joined_holder":
				var host := _unit(side, "Host", -30.0, -30.0)
				units.append(host)
				EquipmentDistributor.attach_hero_to_unit(holder, host)
				# Review 22.11.: if attaching moved the hero to its host, the row would pass whatever the joined-hero filter does.
				var c: Vector3 = sc.unit_centre(holder)
				if Vector2(c.x - m.x, c.z - m.z).length() > 3.0 * INCH:
					unfit = "joined_holder: the attached hero left the marker (now %s) - the row cannot read the filter" % c
	if kind in ["seize_held", "garrison", "garrison_shared"]:
		_owners[mi] = 0
		var on: Array = {"seize_held": [friend], "garrison": [win], "garrison_shared": [win, friend]}[kind]
		for k in on.size():
			_place(on[k], m + Vector3((0.3 + 0.4 * k) * INCH, 0.0, 0.5 * INCH))
	# greedy_spread: no marker owned or contested, the winner 4.5 in south of `mi` (its nearest), `mi` booked below: the spread term
	# drops `mi` one tier, so the goal is another marker; without the term (on both copies) it would be `mi` (review 22.11.).
	if kind == "greedy_spread":
		_owners = [0, 0, 0]
		_place(win, m + Vector3(0.0, 0.0, -4.5 * INCH))
	if kind == "fight":
		_place(win, Vector3(rng.randf_range(-6.0, 6.0) * INCH, 0.0, 9.0 * INCH))   # no marker within 3 in: no garrison
	sc._round_plans = {}
	sc.difficulty_by_slot = {}
	sc._marker_runners = {}
	if kind != "no_planner":
		var diff := SoloDifficulty.for_grade(SoloDifficulty.grade_names()[0], 7)
		diff.endgame_convergence = kind == "greedy_spread"
		sc.difficulty_by_slot[side] = diff
		var task := {}
		match kind:
			"seize", "seize_held", "defender":
				task = {"kind": "seize", "marker": mi, "lane": 0}
			"seize_lane":
				task = {"kind": "seize", "marker": mi, "lane": 1}
			"garrison", "garrison_shared", "fight":
				task = {"kind": "fight"}
		sc._round_plans[side] = {"round": sc._current_round(), "tasks": {} if task.is_empty() else {win.unit_id: task}}
		if kind == "greedy_spread":
			sc.claim_marker(_markers[mi])
	CoreActivation.reset_all(_main)
	var h := CoreActivation.capture(_main)
	var plan: Dictionary = sc.consolidation_input(win)
	var core: Variant = sc._core_node_ready().consolidation_goal(h, win.unit_id, plan)
	var table: Vector3 = sc.consolidation_goal_of(win)
	var enemies: Array = [enemy_a, enemy_b].filter(func(u: GameUnit) -> bool: return not u.is_destroyed()).map(sc.unit_centre)
	RosterSweep.free_units(_main, units)
	var tag := "%s (marker %d, plan %s)" % [kind, mi, plan]
	if unfit != "":
		return unfit
	if table == SoloController.NO_OBJECTIVE or core == null:
		return "%s: no goal (table %s, core %s) - a row must have one" % [tag, table, core]
	if not (core is Vector3) or (core as Vector3) != table:
		return "%s: table %s, core %s" % [tag, table, core]
	var want := _expect(kind, table, m, enemies)
	return "" if want == "" else "%s: %s (goal %s)" % [tag, want, table]


## The branch a kind claims, checked on the agreed goal: "" when it holds.
func _expect(kind: String, goal: Vector3, m: Vector3, enemies: Array) -> String:
	var is_enemy := enemies.has(goal)
	var is_marker := _markers.has(goal)
	match kind:
		"seize", "defender", "garrison", "shaken_holder", "dead_holder", "reserve_holder", "joined_holder", "aircraft_holder", "dead_contester":
			return "" if goal == m else "not the marker the kind claims"
		"seize_lane":
			var off := Vector2(goal.x - m.x, goal.z - m.z).length()
			return "" if absf(off - 2.5 * INCH) < 1e-6 else "not 2.5 in beside the marker (%f m)" % off
		"seize_held", "garrison_shared", "fight":
			return "" if is_enemy else "not an enemy centre"
		"greedy_contested", "greedy_spread":
			return "" if is_marker and goal != m else "the marker the kind rules out (contested / booked), or no marker"
		"greedy", "no_planner":
			return "" if is_marker or is_enemy else "neither a marker nor an enemy"
	return "unknown kind"


func test_the_core_and_the_table_pick_the_same_consolidation_goal_on_every_branch() -> void:
	var bad: Array = []
	var rows := 0
	for s in SEEDS:
		for kind in KINDS:
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 * s + KINDS.find(kind)
			var why := _board(kind, rng)
			rows += 1
			if why != "":
				bad.append(why)
	assert_int(rows).is_equal(SEEDS * KINDS.size())
	assert_array(bad).override_failure_message("goals differ or miss their branch (%d of %d):\n%s" % [bad.size(), rows, "\n".join(bad.slice(0, 20))]).is_empty()


## Lead call 22.11.: a planned side without this round's plan cached gets no invented inputs - from the plan's epoch the door refuses
## the charge (`plan_uncached`) and the table resolves it. Below the epoch nothing changes.
func test_a_planned_side_without_its_round_plan_keeps_the_charge_on_the_table() -> void:
	var sc: SoloController = _main.solo_controller
	_markers = []
	var att := _unit(2, "Att", 0.0, 0.0)
	var foe := _unit(1, "Foe", 2.5, 0.0)
	sc.difficulty_by_slot = {1: SoloDifficulty.for_grade(SoloDifficulty.grade_names()[0], 7), 2: SoloDifficulty.for_grade(SoloDifficulty.grade_names()[0], 7)}
	sc._round_plans = {2: {"round": sc._current_round(), "tasks": {}}}
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE}
	AiActRecorder.rules_epoch = AiActRecorder.PENDING_EPOCH_CONSOLIDATE_PLAN
	assert_array(CoreActivation.charge_refusals(_main, att, report)).contains(["plan_uncached"])
	sc._round_plans[1] = {"round": sc._current_round(), "tasks": {}}
	assert_array(CoreActivation.charge_refusals(_main, att, report)).not_contains(["plan_uncached"])
	sc._round_plans.erase(1)
	AiActRecorder.rules_epoch = AiActRecorder.PENDING_EPOCH_CONSOLIDATE_PLAN - 1
	assert_array(CoreActivation.charge_refusals(_main, att, report)).not_contains(["plan_uncached"])
	RosterSweep.free_units(_main, [att, foe])
