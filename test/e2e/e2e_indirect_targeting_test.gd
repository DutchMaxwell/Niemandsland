extends GdUnitTestSuite
## #182 — Indirect targets without line of sight (GF v3.5.1: "May target enemies that
## are not in line of sight as if in line of sight"). Community case: a Dwarf Artillery
## Gun behind a forest could not even SELECT its target. Drives the REAL legality gate
## (_solo_validate_target) over the real main.tscn with a container wall between the
## units: an Indirect weapon passes, a plain weapon still refuses with the LOS reason.

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
	_main._ensure_solo_controller()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A unit whose OPR source carries ONE ranged weapon with the given special rules —
## the shape _solo_all_weapons/has_indirect_ranged read.
func _armed_unit(pid: int, unit_name: String, pos: Vector3, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Launcher"
	w.range_value = 36
	w.attacks = 2
	var sr: Array[String] = []
	for r in rules:
		sr.append(str(r))
	w.special_rules = sr
	var src := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	return u


## A solid container wall painted across the line between x=-0.3 and x=+0.3.
func _wall_between(o: Node3D) -> void:
	for i in range(41):
		var t := float(i) / 40.0
		if t < 0.4 or t > 0.6:
			continue
		var p := Vector3(-0.3, 0, 0).lerp(Vector3(0.3, 0, 0), t)
		o.grid_cells[o.world_to_cell(p)] = o.TerrainType.CONTAINER


func test_indirect_may_target_without_los_plain_weapon_may_not() -> void:
	_wall_between(_main.terrain_overlay)
	var target := E2EBoot.make_unit(_main, 2, "Hidden", [Vector3(0.3, 0, 0)])
	(target.models[0] as ModelInstance).model_index = 0
	# The plain gun still refuses with the LOS reason (no over-grant). #205 appends a
	# blocker detail ("— nearest lane blocked by ...") — that wave has its own suite,
	# here only the refusal itself is the claim.
	var plain := _armed_unit(1, "PlainGun", Vector3(-0.3, 0, 0), ["AP(1)"])
	assert_str(_main._solo_validate_target(plain, target, false)).contains("no model has line of sight")
	# ...the Indirect gun may target as if in line of sight (#182, the community case).
	var arty := _armed_unit(1, "Arty", Vector3(-0.3, 0, 0), ["Indirect", "Blast(3)"])
	assert_str(_main._solo_validate_target(arty, target, false)).is_equal("")


# =====================================================================================
# NML-971 D2 (elevation program, Phase A / W3.13) — the aimed CAST line.
# =====================================================================================
# A spell has its own printed range. The cast candidates are built once, from the SPELL's
# range (flat, G3) plus the sight truth — but the line drawn under the cursor while the cast
# is being aimed asked a completely different question: AiArchetype.max_range_inches of the
# caster's WEAPONS. A caster with a 12" gun casting an 18" spell therefore dragged a red
# "0/1 sight" line over a target the cast gate had already accepted, and every reported
# instance of that read as "the game says I cannot cast this".
#
# The fix is not a second opinion but ONE query: while a cast is aimed, the line reads the
# candidate set the cast gate produced.

const CAST_INCH := 0.0254


## A unit with one SHORT-ranged gun, registered with the army manager (spell_candidates walks
## the manager's per-player pools).
func _short_gun_unit(pid: int, unit_name: String, pos: Vector3, range_in: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Hand Cannon"
	w.range_value = range_in
	w.attacks = 1
	var src := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_a_cast_target_outside_the_weapon_range_is_legal_and_the_line_agrees() -> void:
	# Open table, 14" apart: only the two RANGES can decide anything here.
	var caster := _short_gun_unit(1, "Sorcerer", Vector3.ZERO, 12)
	var target := _short_gun_unit(2, "Warlord", Vector3(14.0 * CAST_INCH, 0.0, 0.0), 12)
	var entry := {"name": "Hex", "range_in": 18, "target": {"side": "enemy"}}

	# HALF ONE — the cast gate itself measures the SPELL's 18" (flat, base edge to base edge).
	var cands: Array = _main.solo_controller.spell_candidates(caster, entry, 1, 2)
	assert_bool(cands.has(target)) \
		.override_failure_message("the cast gate must accept a target inside the spell's 18\" (candidates: %d)" % cands.size()) \
		.is_true()
	# PRECONDITION — the caster's GUN cannot reach it. That is the question the line was asking.
	assert_int(_main._solo_sighted_count(caster, target, 12)) \
		.override_failure_message("precondition: the 12\" gun must NOT reach 14\", or this proves nothing") \
		.is_equal(0)

	# HALF TWO — with the cast aimed, the line must report the same verdict as the gate.
	_main._solo_target_mode = {"unit": caster, "cast_entry": entry, "cast_valid": cands, "cast_picked": []}
	var shown: int = _main._solo_hover_sighted_count(caster, target)
	_main._solo_target_mode = {}
	assert_int(shown) \
		.override_failure_message("NML-971 D2 — the aimed cast line draws RED over a legal spell target: " +
			"_solo_hover_sighted_count still answers with the caster's WEAPON range (12\") instead of " +
			"reading the candidate set the cast gate built from the spell's 18\".") \
		.is_greater(0)
