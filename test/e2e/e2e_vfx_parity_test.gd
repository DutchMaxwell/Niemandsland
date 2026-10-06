extends GdUnitTestSuite
## E2E — the special-effects release gate: the same seeded dice give the same hits, wounds, casualties,
## battle log and RNG state with the combat effects ON and OFF. A real AI volley (tracers + result pips)
## and a real damage cast (seal + pips) run on a fresh boot per arm; the cues read the resolution and must
## never steer it. The first test records the OFF arm, the second replays the ON arm and compares — and it
## also proves the ON arm really drew (a parity check over an arm that drew nothing would prove nothing).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 4711

static var _off_arm := {}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}   # both AI: saves auto-roll, no prompt
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, n: int, z: float) -> GameUnit:
	var positions: Array = []
	for i in n:
		positions.append(Vector3(0.03 * i, 0.0, z))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _shots(attacker: GameUnit) -> Array:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Assault Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 5
	w.special_rules = ["AP(1)"] as Array[String]
	return [{"member": attacker, "quality": attacker.get_quality(), "alive": attacker.get_alive_count(),
		"max": attacker.models.size(), "reach": 24, "profile": AiShooting.profiles_in_range([w], 0.0)[0]}]


## One seeded volley + one seeded damage cast; returns everything the rules decided.
func _arm(effects_on: bool) -> Dictionary:
	for fx in [_main.result_pips, _main.volley_cue, _main.spell_seal, _main.casualty_show, _main.shot_show]:
		fx.force_for_tests = effects_on
		fx.enabled = effects_on
	var rounds := [0]   # the shot show's sound hook hears every round it draws
	var count_round := func(_family: int, _moment: String, _at: Vector3) -> void: rounds[0] += 1
	_main.shot_show.sound_cue.connect(count_round)
	var shooters := _unit(1, "Rifles", 5, 0.0)
	var target := _unit(2, "Grunts", 8, 10.0 * INCH)
	seed(SEED)
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(shooters, target, _shots(shooters), false)
	await _main._solo_resolve_one_cast({"caster": shooters, "caster_unit": shooters, "name": "Spark",
		"spell": {"range_in": 18, "effect": {"kind": "damage", "hits": 3, "ap": 1}}, "targets": [target],
		"boost": 0, "interference": 1, "base_target": 2, "threshold": 1})
	await get_tree().create_timer(ShotShow.CHAOS_S + 0.2).timeout   # every round leaves inside the chaos window
	_main.shot_show.sound_cue.disconnect(count_round)
	var log := ""
	for e in _main.battle_log.entries():
		log += str((e as Dictionary)["text"]) + "\n"
	var drawn: int = _main.result_pips.get_child_count() + _main.volley_cue.get_child_count() \
		+ _main.spell_seal.get_child_count()
	return {"wounds": target.models.map(func(m): return [m.is_alive, m.wounds_current]),
		"log": log, "tray": _main._tray_rng.state, "global": randi(), "drawn": drawn,
		"shown": _main.casualty_show.get_child_count(), "rounds": rounds[0]}


func test_the_off_arm_resolves(timeout := 240000) -> void:
	_off_arm = await _arm(false)
	assert_int(int(_off_arm["drawn"])).is_equal(0)
	assert_str(str(_off_arm["log"])).override_failure_message("fixture: the volley must roll").contains("Assault Rifle")
	assert_bool((_off_arm["wounds"] as Array).any(func(w): return not w[0])) \
		.override_failure_message("fixture: the seeded arm must kill at least one model:\n%s" % _off_arm["log"]).is_true()
	await E2EBoot.settle(get_tree())


func test_the_on_arm_resolves_identically(timeout := 240000) -> void:
	var on := await _arm(true)
	assert_int(int(on["drawn"])).override_failure_message("the ON arm drew no cue at all").is_greater(0)
	assert_int(int(on["shown"])).override_failure_message("the ON arm drew no fall at all").is_greater(0)
	assert_int(int(on["rounds"])).override_failure_message("the ON arm drew no round at all").is_greater(0)
	assert_array(on["wounds"]).is_equal(_off_arm.get("wounds", []))
	assert_str(str(on["log"])).is_equal(str(_off_arm.get("log", "")))
	assert_int(int(on["tray"])).is_equal(int(_off_arm.get("tray", -1)))
	assert_int(int(on["global"])).is_equal(int(_off_arm.get("global", -1)))
	await E2EBoot.settle(get_tree())
