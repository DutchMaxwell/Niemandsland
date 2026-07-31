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
