extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-07d: the Bloodthirsty Fighter follow-up strike is its own strike, so
## the defender's Parry(X) event fires for it too, with the same dice count as the strike it
## continues. Below epoch 73 (the core's EPOCH_73_V36) no Parry die is drawn, and a carrier
## without Bloodthirsty keeps exactly one Parry event. The core's twin is
## core/nml-core/src/tests/dice/v36_melee_rows/mel_07d.rs.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 214

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	_main._solo_dice_trace_enabled = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `models` models at `x` inches with one melee weapon, `rules` and Defense `defense`; Tough(9)
## keeps every model alive so the saves never decide the strike.
func _unit(pid: int, unit_name: String, x: float, models: int, rules: Array, attacks: int,
		quality: int = 4, defense: int = 4, system: String = "gf", faction: String = "") -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = attacks
	w.count = 1
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["special_rules"] = rules + ["Tough(9)"]
	u.unit_properties["defense"] = defense
	u.unit_properties["quality"] = quality
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	for m in u.models:
		(m as ModelInstance).wounds_max = 9
		(m as ModelInstance).wounds_current = 9
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Battle-log index of the first line holding `needle`, -1 when none does.
func _line_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


## How many battle-log lines hold `needle`.
func _count_lines(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


## One 12-attack Quality 4 strike at 2 models; seed 214 draws [5,2,6,1,5,5,4,2,2,6,5,1] (7
## hits), the first Parry cuts one, the six saves hold two unmodified 1s, and the two
## Bloodthirsty follow-up dice both hit.
func _strike(epoch: int, attacker_rules: Array, defender_rules: Array) -> Array:
	AiActRecorder.rules_epoch = epoch
	var attacker := _unit(1, "Charger", 0.0, 1, attacker_rules, 12, 4, 4, "aof", "war_disciples")
	var defender := _unit(2, "Defender", 0.5, 2, defender_rules, 1, 4, 4)
	_main.solo_controller.decision_log.clear()
	_main.seed_tray_rng(SEED)
	await _main._solo_melee_strike_phase(attacker, defender, false, 0)   # 0 = SoloStrike.ALL
	var rolls: Array = []
	for rec in _main.solo_controller.decision_log:
		if str((rec as Dictionary).get("kind", "")) == "dice":
			rolls.append([str(rec["roll_kind"]), Array(rec["faces"])])
	await E2EBoot.settle(get_tree())
	return rolls


static func _kinds(rolls: Array) -> Array:
	var kinds: Array = []
	for r in rolls:
		kinds.append(str((r as Array)[0]))
	return kinds


func test_the_follow_up_strike_keeps_its_parry_event_at_epoch_73(timeout := 90000) -> void:
	var rolls: Array = await _strike(AiActRecorder.EPOCH_73_V36,
		["Bloodthirsty Fighter"], ["Parry(1)"])
	assert_str(str(_kinds(rolls))) \
		.override_failure_message("strike hits, Parry, saves, then the follow-up hits, Parry, saves: %s" % str(rolls)) \
		.is_equal(str(["attack", "parry", "defense", "attack", "parry", "defense"]))
	assert_int((rolls[1] as Array)[1].size()) \
		.override_failure_message("the strike's Parry rolls one die per Parry(1) model: %s" % str(rolls)) \
		.is_equal(2)
	assert_int((rolls[4] as Array)[1].size()) \
		.override_failure_message("the follow-up keeps the strike's Parry dice count: %s" % str(rolls)) \
		.is_equal(2)
	assert_int(_count_lines("Parry: Defender rolls 2 dice")) \
		.override_failure_message("both Parry events are named in the battle log") \
		.is_equal(2)
	assert_int(_line_of("Bloodthirsty Fighter")) \
		.override_failure_message("the blocked 1s paid a follow-up strike") \
		.is_greater_equal(0)


func test_a_carrier_without_bloodthirsty_gets_one_parry_event() -> void:
	var rolls: Array = await _strike(AiActRecorder.EPOCH_73_V36, [], ["Parry(1)"])
	var parries := 0
	for k in _kinds(rolls):
		if str(k) == "parry":
			parries += 1
	assert_int(parries) \
		.override_failure_message("no follow-up, so one Parry event: %s" % str(rolls)) \
		.is_equal(1)
	assert_int(_line_of("Bloodthirsty Fighter")).is_equal(-1)


func test_no_parry_event_is_drawn_at_epoch_72() -> void:
	var rolls: Array = await _strike(AiActRecorder.EPOCH_72_PLAYTEST_RULES,
		["Bloodthirsty Fighter"], ["Parry(1)"])
	assert_bool(_kinds(rolls).has("parry")) \
		.override_failure_message("epoch 72 draws no Parry dice: %s" % str(rolls)) \
		.is_false()
	assert_int(_line_of("Bloodthirsty Fighter")) \
		.override_failure_message("the follow-up itself still fires below 73") \
		.is_greater_equal(0)
