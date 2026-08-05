extends GdUnitTestSuite
## E2E — #231: the Aircraft -12" range penalty (GF Advanced Rules v3.5.1) on the HUMAN pick path.
##
## The hover note already NAMED the shrink (e2e_negative_lines_test) — a label is not a rule. This
## suite drives the MECHANIC over the real scenes/main.tscn:
##   • the legality gate (_solo_validate_target) refuses an aircraft outside the SHRUNK reach;
##   • the human volley's per-weapon gate (_solo_attack_groups — the profile list _run_human_shooting
##     and the split-fire ask both roll) drops the profiles the -12" puts out of reach, and scales the
##     surviving profile by the models that reach at the SHRUNK range;
##   • the counter-probe: a close aircraft is shot normally, and a ground unit at the same distance
##     is untouched by any of it (the refusal is the penalty, never the geometry).
##
## The AI path has measured this since the rule landed (main.gd's AI volley folds
## SoloController.effective_shoot_reach_in into its per-model sighting) — these cases exist so the
## human path can never drift away from it again.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const IN2M := 0.0254
## Both fixture units sit on the default base (VolumetricLos.DEFAULT_BASE_RADIUS_M = 0.016 m), and every
## range gate measures base-EDGE to base-edge (B11), so a centre offset carries both radii on top.
const EDGE_SLACK_IN := 2.0 * 0.016 / IN2M

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


## A player unit whose OPR source carries the given ranged weapons — the shape _solo_all_weapons and
## _solo_attack_groups read. `weapons` entries: {name, range, attacks, count}.
func _armed(pid: int, unit_name: String, positions: Array, weapons: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var i := 0
	for m in u.models:
		(m as ModelInstance).model_index = i
		i += 1
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wd in weapons:
		var d := wd as Dictionary
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(d.get("name", "Gun"))
		w.range_value = int(d.get("range", 24))
		w.attacks = int(d.get("attacks", 2))
		w.count = int(d.get("count", 1))
		ws.append(w)
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## X offset (metres) that puts a single-model unit at `gap_in` base-edge-to-base-edge from origin.
func _x_for_gap(gap_in: float) -> float:
	return (gap_in + EDGE_SLACK_IN) * IN2M


## The profile names of a human volley against `target` at the measured gap — exactly the list
## _run_human_shooting rolls dice for.
func _volley_weapons(attacker: GameUnit, target: GameUnit) -> Array:
	var dist: float = _main.solo_controller.nearest_melee_gap_in(attacker, target)
	var out: Array = []
	for grp in _main._solo_attack_groups(attacker, dist, false, target):
		for p in (grp as Dictionary).get("profiles", []):
			out.append(str((p as Dictionary).get("name", "")))
	return out


## Attacks the named profile rolls in that same volley (0 when it never fires).
func _volley_attacks(attacker: GameUnit, target: GameUnit, weapon: String) -> int:
	var dist: float = _main.solo_controller.nearest_melee_gap_in(attacker, target)
	for grp in _main._solo_attack_groups(attacker, dist, false, target):
		for p in (grp as Dictionary).get("profiles", []):
			if str((p as Dictionary).get("name", "")) == weapon:
				return int((p as Dictionary).get("attacks", 0))
	return 0


func test_validate_refuses_an_aircraft_beyond_the_shrunk_reach(timeout := 120000) -> void:
	# 24" rifle, aircraft 20" away: without the rule a trivially legal shot, with it 20" > 12".
	var gunner := _armed(1, "Gunner", [Vector3.ZERO], [{"name": "Rifle", "range": 24, "attacks": 2}])
	var flyer := _armed(2, "Flyer", [Vector3(_x_for_gap(20.0), 0, 0)], [])
	flyer.unit_properties["special_rules"] = ["Aircraft"]
	assert_bool(SoloController.is_aircraft(flyer)) \
		.override_failure_message("fixture broken: the Aircraft rule did not resolve for the target") \
		.is_true()
	var refusal: String = _main._solo_validate_target(gunner, flyer, false)
	assert_str(refusal) \
		.override_failure_message("#231 — the 24\" rifle was allowed to target an Aircraft 20\" away (verdict: '%s')" % refusal) \
		.contains("out of range")
	# rules-must-log's sibling: the refusal NAMES the rule that shrank the reach.
	assert_str(refusal).contains("Aircraft -12")
	# Counter-probe A: the same distance against a GROUND unit is a perfectly legal shot.
	var grunts := _armed(2, "Grunts", [Vector3(0, 0, _x_for_gap(20.0))], [])
	assert_str(_main._solo_validate_target(gunner, grunts, false)).is_equal("")
	# Counter-probe B: the same aircraft at 8" is inside the shrunk 12" — the shot stands.
	E2EBoot.place_unit_at(flyer, Vector3(_x_for_gap(8.0), 0, 0))
	assert_str(_main._solo_validate_target(gunner, flyer, false)).is_equal("")


func test_human_volley_drops_the_weapons_the_penalty_puts_out_of_reach(timeout := 120000) -> void:
	# A two-weapon shooter 20" from an aircraft: the 36" cannon still reaches (36-12 = 24"), the 24"
	# rifle does NOT (24-12 = 12"). The target is legal BECAUSE of the cannon, so the legality gate
	# waves the volley through — only the per-weapon gate can stop the rifle from rolling dice.
	var gunner := _armed(1, "Gunner", [Vector3.ZERO],
		[{"name": "Cannon", "range": 36, "attacks": 2}, {"name": "Rifle", "range": 24, "attacks": 2}])
	var flyer := _armed(2, "Flyer", [Vector3(_x_for_gap(20.0), 0, 0)], [])
	flyer.unit_properties["special_rules"] = ["Aircraft"]
	assert_float(_main.solo_controller.nearest_melee_gap_in(gunner, flyer)) \
		.override_failure_message("fixture broken: the shooter is not 20\" from the aircraft") \
		.is_equal_approx(20.0, 0.5)
	assert_str(_main._solo_validate_target(gunner, flyer, false)) \
		.override_failure_message("fixture broken: the cannon should keep the aircraft a legal target") \
		.is_equal("")
	var fired := _volley_weapons(gunner, flyer)
	assert_array(fired) \
		.override_failure_message("#231 — the 24\" rifle rolled dice at an Aircraft 20\" away (fired: %s)" % str(fired)) \
		.not_contains(["Rifle"])
	assert_array(fired) \
		.override_failure_message("#231 — the 36\" cannon (36-12 = 24\") must still fire (fired: %s)" % str(fired)) \
		.contains(["Cannon"])
	# Counter-probe: the SAME shooter against a ground unit at the same range fires both weapons —
	# the exclusion is the Aircraft rule, not the geometry.
	var grunts := _armed(2, "Grunts", [Vector3(0, 0, _x_for_gap(20.0))], [])
	assert_array(_volley_weapons(gunner, grunts)).contains(["Cannon", "Rifle"])
	# Counter-probe: an aircraft at 8" is inside both shrunk reaches — the whole volley fires.
	E2EBoot.place_unit_at(flyer, Vector3(_x_for_gap(8.0), 0, 0))
	assert_array(_volley_weapons(gunner, flyer)).contains(["Cannon", "Rifle"])


func test_per_model_attack_count_uses_the_shrunk_reach(timeout := 120000) -> void:
	# Per-model shooting (GF v3.5.1 p.8) at the SHRUNK reach: a spread unit's rear model is 30" from
	# the aircraft, so the 36" cannon (effective 24") fires with the front model only — half the dice.
	var gunner := _armed(1, "Gunner", [Vector3.ZERO, Vector3(-10.0 * IN2M, 0, 0)],
		[{"name": "Cannon", "range": 36, "attacks": 2, "count": 2}])
	var flyer := _armed(2, "Flyer", [Vector3(_x_for_gap(20.0), 0, 0)], [])
	flyer.unit_properties["special_rules"] = ["Aircraft"]
	# Against a GROUND unit at the same spot both models reach: the full 2x2 = 4 attacks.
	var grunts := _armed(2, "Grunts", [Vector3(0, 0, _x_for_gap(20.0))], [])
	assert_int(_volley_attacks(gunner, grunts, "Cannon")) \
		.override_failure_message("fixture broken: both models should reach a ground target 20\"/30\" away") \
		.is_equal(4)
	# Against the AIRCRAFT only the front model is inside the 24" effective reach.
	assert_int(_volley_attacks(gunner, flyer, "Cannon")) \
		.override_failure_message("#231 — the rear model (30\" away, effective reach 24\") still rolled its dice at an Aircraft") \
		.is_equal(2)


func test_battle_log_names_the_weapon_the_penalty_locks_out(timeout := 120000) -> void:
	# rules-must-log: a weapon that silently stops firing reads as a bug. The volley's Aircraft line
	# is followed by the NAMES of the profiles the -12" locked out.
	var gunner := _armed(1, "Gunner", [Vector3.ZERO],
		[{"name": "Cannon", "range": 36, "attacks": 2}, {"name": "Rifle", "range": 24, "attacks": 2}])
	var flyer := _armed(2, "Flyer", [Vector3(_x_for_gap(20.0), 0, 0)], [])
	flyer.unit_properties["special_rules"] = ["Aircraft"]
	_main._solo_log_reach_shrink(gunner, flyer)
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text) \
		.override_failure_message("#231 — the Aircraft volley never named the locked-out weapon (log: %s)" % text.strip_edges()) \
		.contains("Rifle")
	assert_str(text).contains("Aircraft")
	# The cannon still fires, so it is never listed as locked out.
	assert_str(text.substr(text.find("out of reach"))).not_contains("Cannon")
