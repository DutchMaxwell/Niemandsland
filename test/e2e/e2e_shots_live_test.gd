extends GdUnitTestSuite
## The shots live in the game (maintainer look verdicts: chaotic fire, weapon types, then shots GO): a real volley
## cue carries the weapon family from its name and rules, its Blast and the target's height, and the shot show on
## every peer draws it - a heavy machine gun stutters, a Blast weapon blasts; a malformed peer payload draws without
## an error.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ShotScript = preload("res://scripts/vfx/shot_show.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _heard: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_heard = []
	var show: Variant = _main.get("shot_show")
	if show != null:
		show.force_for_tests = true
		show.enabled = true
		show.sound_cue.connect(func(f: int, moment: String, _at: Vector3) -> void: _heard.append([f, moment]))


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _count(family: int, moment: String) -> int:
	return _heard.filter(func(h: Array) -> bool: return h[0] == family and h[1] == moment).size()


func test_a_real_volley_cue_carries_its_weapon_family(timeout := 30000) -> void:
	assert_bool(_main.get("shot_show") is ShotShow).override_failure_message("main.tscn has no ShotShow").is_true()
	var gunners := E2EBoot.make_unit(_main, 1, "Gunners", [Vector3(0, 0, 0), Vector3(0.03, 0, 0)])
	var target := E2EBoot.make_unit(_main, 2, "Targets", [Vector3(0, 0, 0.3)])
	_main._vfx_volley(gunners, target, {"name": "Heavy Machinegun", "attacks": 8, "count": 2, "blast": 0},
		[[Vector3(0, 0, 0), Vector3(0, 0, 0.3)], [Vector3(0.03, 0, 0), Vector3(0, 0, 0.3)]], false)
	await get_tree().create_timer(1.5).timeout
	assert_int(_count(VolleyCue.Family.AUTO, "launch")).override_failure_message("a machine gun stutters") \
		.is_equal(2 * ShotScript.AUTO_ROUNDS)


func test_a_peer_blast_volley_blasts_and_bad_payloads_raise_nothing(timeout := 30000) -> void:
	var pair := [Vector3(0, 0.03, 0), Vector3(0, 0.03, 0.3)]
	_main._vfx_draw({"k": "volley", "pairs": [pair], "f": int(VolleyCue.Family.ARTILLERY), "b": 3, "h": 0.03,
		"s": 9, "id": 1}, 2)
	var next_id := 2   # every cue its own id: a repeated id is a duplicate the draw path drops
	for bad: Dictionary in [{"f": []}, {"b": []}, {"b": "big"}, {"h": {}}, {"f": "auto", "b": {}, "h": []}]:
		var cue := {"k": "volley", "pairs": [pair], "f": 1, "b": 0, "h": 0.0, "s": 9, "id": next_id}
		next_id += 1
		cue.merge(bad, true)
		_main._vfx_draw(cue, 2)
	await get_tree().create_timer(2.0).timeout
	assert_int(_count(VolleyCue.Family.ARTILLERY, "blast")).override_failure_message("the peer's shell blasts").is_equal(1)


## Indirect fire tested no sight line: no chalk line (it would cross the wall), but the shell arcs over it.
func test_indirect_fire_lobs_its_shell_and_draws_no_chalk_line(timeout := 30000) -> void:
	_main.volley_cue.force_for_tests = true   # the chalk line must be able to draw, or its absence proves nothing
	_main.volley_cue.enabled = true
	var crew := E2EBoot.make_unit(_main, 1, "Mortar Crew", [Vector3(0, 0, 0)])
	var target := E2EBoot.make_unit(_main, 2, "Targets", [Vector3(0, 0, 0.4)])
	_main._vfx_volley(crew, target, {"name": "Heavy Rifle", "attacks": 1, "count": 1, "blast": 0},
		[[Vector3(0, 0, 0), Vector3(0, 0, 0.4)]], true)
	assert_int(_main.volley_cue.get_child_count()).override_failure_message("no chalk line without a tested line").is_zero()
	await get_tree().create_timer(1.5).timeout
	assert_int(_count(VolleyCue.Family.ARTILLERY, "launch")).override_failure_message("the shell is lobbed").is_equal(1)
	assert_int(_count(VolleyCue.Family.BALLISTIC, "launch")).override_failure_message("never a straight round").is_zero()


## The player's own Indirect volley: its pairs come from range alone (no sight test), and it lobs too.
func test_a_players_indirect_volley_lobs_from_range_alone(timeout := 30000) -> void:
	var crew := E2EBoot.make_unit(_main, 1, "Mortar Crew", [Vector3(0, 0, 0)])
	var target := E2EBoot.make_unit(_main, 2, "Targets", [Vector3(0, 0, 0.4)])
	_main._vfx_player_volley(crew, target, {"name": "Mortar", "range": 30, "attacks": 1, "count": 1, "blast": 3}, true)
	await get_tree().create_timer(1.5).timeout
	assert_int(_count(VolleyCue.Family.ARTILLERY, "launch")).override_failure_message("the player's mortar lobs").is_equal(1)
