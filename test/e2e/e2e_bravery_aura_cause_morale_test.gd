extends GdUnitTestSuite
## Bravery Aura keeps its +1 on a cause-named morale test; a real Banner does not (army data 3.6).

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int
var _seq := 0


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(models: int, rules: Array, nm: String = "U", x_in: float = 0.0, pid: int = 1) -> GameUnit:
	_seq += 1
	var spots: Array = []
	for i in range(models):
		spots.append(Vector3((x_in + 0.5 * i) * 0.0254, 0, 0))
	var u := Boot.make_unit(_main, pid, "%s%d" % [nm, _seq], spots)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _join(host: GameUnit, hero: GameUnit) -> void:
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]


func _log() -> String:
	var t := ""
	for e in _main.battle_log.entries():
		t += str(e["text"]) + "\n"
	return t


## Seed so the first tray dice come out as `want` (a prefix of 1-6 faces).
func _seed_faces(want: Array) -> void:
	for cand in range(5000):
		var rng := RandomNumberGenerator.new()
		rng.seed = cand
		var ok := true
		for w in want:
			if rng.randi_range(1, 6) != int(w):
				ok = false
				break
		if ok:
			_main.seed_tray_rng(cand)
			return
	fail("no seed for %s" % str(want))


func test_banner_gives_nothing_for_a_spell_caused_test() -> void:
	var u := _unit(1, ["Banner"])
	_seed_faces([3])
	var passed: bool = await _main._solo_morale_test(u, "t", false, "Spell Drain")
	assert_bool(passed).override_failure_message(_log()).is_false()


func test_bravery_aura_plus_one_also_on_a_spell_caused_test() -> void:
	var u := _unit(1, ["Bravery Aura"])
	_seed_faces([3])
	var passed: bool = await _main._solo_morale_test(u, "t", false, "Spell Drain")
	assert_bool(passed).override_failure_message("Bravery Aura lost its +1 on a spell-caused test:\n" + _log()).is_true()
