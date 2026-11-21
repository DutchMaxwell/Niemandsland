extends GdUnitTestSuite
## PLAN H, H-18 (`EPOCH_94_PARITY_BATCH` = 94, lead decision 20.11.): a Versatile Attack pick (+1 to hit or AP(+1), once per
## activation) is made on the number the first eligible weapon really rolls at. The table reads the MODIFIED to-hit (Stealth, Evasive, Artillery
## on the target; Artillery, Good Shot, the Unpredictable die on the shooter), the core latched it before the dice on the plain Quality. Q4 AP(1) at Defense 3+: plain, the
## two modes tie and the tie goes to AP(+1); at 5+ (the target's minus) the hit mode wins. From 94 the core's dice decide on the modified number.
## Real: the main scene, NmlCore, the importer's unit builder, the table's AI body. Constructed: the units.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://versatile_pick_dice"
const SEEDS := 16
const PENDING_EPOCH := 94
const PICK := "COMBAT|Versatile Attack:"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Five Versatile shooters, one rifle each at `ap`; `rules` rides the unit (the unit's own Artillery for the shooter-side case).
func _shooter(quality: int, ap: int, rules := [], system := "gf", faction := "battle_brothers", versatile := "Versatile Attack") -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Pickers"
	ou.size = 5
	ou.quality = quality
	ou.defense = 4
	ou.game_system = system
	ou.special_rules.assign([versatile] + rules)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 5
	w.special_rules.assign(["AP(%d)" % ap])
	ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": system}


func _target(rules: Array, system := "gf", faction := "battle_brothers") -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Targets"
	ou.size = 10
	ou.quality = 4
	ou.defense = 3
	ou.game_system = system
	ou.special_rules.assign(rules)
	return {"unit": ou, "faction": faction, "system": system}


func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


## EVERY battle-log line of the volley (H-18 lift: the door says what the table says), in a stable order.
func _sorted(lines: Array) -> Array:
	var out := lines.duplicate()
	out.sort()
	return out


func _picks(lines: Array) -> Array:
	return lines.filter(func(l: String) -> bool: return l.begins_with(PICK))


## Seeds (of 16) whose dice, end state or any battle-log line differ between the table and the core at `epoch`, and the table's first pick line.
func _differing(shooter: Dictionary, target: Dictionary, epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var dice := ProjectSettings.globalize_path(DICE)
	var bad := 0
	var first := ""
	for s in SEEDS:
		var t := await RosterSweep.volley(_main, shooter, target, s, false, dice)
		var c := await RosterSweep.volley(_main, shooter, target, s, true, dice)
		var tp := _picks(t["lines"])
		first = first if first != "" else (str(tp[0]) if not tp.is_empty() else "no pick line")
		if _faces(t["rolls"]) != _faces(c["rolls"]) or RosterSweep.first_state_diff(t["state"], c["state"]) != "" or tp != _picks(c["lines"]) \
				or _sorted(t["lines"]) != _sorted(c["lines"]):
			bad += 1
	return {"bad": bad, "pick": first}


## RED on main (the gate is off): the core picks AP(+1) on the plain Quality 4, the table +1 to hit on the 5+ the target's rule leaves.
func test_a_to_hit_minus_on_the_target_moves_the_pick_in_both_halves_from_94() -> void:
	for rule in ["Stealth", "Evasive", "Artillery"]:
		var tgt := _target([rule])
		var below: Dictionary = await _differing(_shooter(4, 1), tgt, 92)
		assert_int(int(below["bad"])).override_failure_message("%s: the fixture reads equal below 94, the check cannot fail" % rule).is_greater(0)
		var at_94: Dictionary = await _differing(_shooter(4, 1), tgt, PENDING_EPOCH)
		assert_str(str(at_94["pick"])).override_failure_message("%s: the table picks the hit mode on the modified number" % rule).contains("picks +1 to hit")
		assert_int(int(at_94["bad"])).override_failure_message("%s: %d of %d seeds still differ at 94" % [rule, at_94["bad"], SEEDS]).is_equal(0)


## The shooter's own plus: Artillery (held, target over 12") makes Quality 5 a 4+, where the plain 5+ picks the hit mode and the 4+ picks AP(+1).
func test_the_shooters_own_to_hit_plus_moves_the_pick_in_both_halves_from_94() -> void:
	var shooter := _shooter(5, 1, ["Artillery"])
	var below: Dictionary = await _differing(shooter, _target([]), 92)
	assert_int(int(below["bad"])).override_failure_message("the fixture reads equal below 94, the check cannot fail").is_greater(0)
	var at_94: Dictionary = await _differing(shooter, _target([]), PENDING_EPOCH)
	assert_str(str(at_94["pick"])).contains("picks AP(+1)")
	assert_int(int(at_94["bad"])).override_failure_message("%d of %d seeds still differ at 94" % [at_94["bad"], SEEDS]).is_equal(0)


## The rest of the shooter-side families (Vinci Tech is the Versatile Attack of its faction): the Unpredictable die's +1 (rolled inside the volley) and a
## Shot Modifier (Good Shot +1). Each differs below 94 on 5 to 15 of 16 seeds and is equal at 94.
func test_the_unpredictable_die_and_a_shot_modifier_move_the_pick_in_both_halves_from_94() -> void:
	var tgt := _target([], "aof", "duchies_of_vinci")
	for rule in ["Unpredictable Shooter", "Unpredictable", "Good Shot"]:
		var shooter := _shooter(5, 1, [rule], "aof", "duchies_of_vinci", "Vinci Tech")
		var below: Dictionary = await _differing(shooter, tgt, 92)
		assert_int(int(below["bad"])).override_failure_message("%s: the fixture reads equal below 94, the check cannot fail" % rule).is_greater(0)
		var at_94: Dictionary = await _differing(shooter, tgt, PENDING_EPOCH)
		assert_int(int(at_94["bad"])).override_failure_message("%s: %d of %d seeds still differ at 94" % [rule, at_94["bad"], SEEDS]).is_equal(0)


## Control (equal at both epochs): a target without a to-hit rule, the plain Quality IS the rolled number.
func test_a_plain_target_picks_alike_at_both_epochs() -> void:
	for epoch in [92, PENDING_EPOCH]:
		var r: Dictionary = await _differing(_shooter(4, 1), _target([]), epoch)
		assert_int(int(r["bad"])).override_failure_message("a plain pair differs on %d of %d seeds at %d" % [r["bad"], SEEDS, epoch]).is_equal(0)
		assert_str(str(r["pick"])).override_failure_message("the table picked on both").contains("picks AP(+1)")
