extends GdUnitTestSuite
## One core C-R1a (epoch 82, `EPOCH_82_IGNORE_BY_NAME`): the table tells wound-ignore rules apart by NAME (`_solo_ignore_wounds`, since
## 3.6: a bypass - Rending, Unstoppable, Bane - skips only the roll of the rule named Regeneration), the core folded the whole family into
## one roll the bypass skipped entirely (the soak's Self-Repair / Angelic Blessing vs Rending / Unstoppable volleys: "table rolled more").
## This is the soak's volley as a fixture: one unit with the bypass weapon fires at one unit with the ignore rule, `SEEDS` seeds, on the
## table (AI body) and on the core door (live capture + step driver, `RosterSweep.volley`), dice compared by parity_compare.py.
## RED at epoch 81 (the core never rolls the bypassed wounds), GREEN from 82; the control (a target whose rule IS Regeneration) is equal at both.
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the two OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const SEEDS := 16
const DICE := "user://ignore_by_name_dice"
const OUT := "user://ignore_by_name_out"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A list entry in the harness's shape: one OPR unit of `size` models, its rules, and `guns` weapons that carry `weapon_rules`.
func _entry(uname: String, size: int, rules: Array, weapon_rules: Array, faction: String, guns := 1) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 4
	ou.defense = 4
	ou.game_system = "gf"
	ou.special_rules.assign(rules)
	if guns > 0:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Gun"
		w.range_value = 24
		w.attacks = 2
		w.count = guns
		w.special_rules.assign(weapon_rules)
		ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": "gf"}


## `SEEDS` volleys of `shooter` at `target` on both paths at `epoch`; returns the compare (rolls by parity_compare.py, state here).
func _run(shooter: Dictionary, target: Dictionary, epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	var rows: Array = []
	for s in SEEDS:
		var table := await RosterSweep.volley(_main, shooter, target, s, false, ProjectSettings.globalize_path(DICE))
		var core := await RosterSweep.volley(_main, shooter, target, s, true, ProjectSettings.globalize_path(DICE))
		rows.append({"id": s, "pair": "fixture", "dir": 0, "seed": s, "att": (table["names"] as Array)[0], "tgt": (table["names"] as Array)[1],
			"table": table, "core": core})
	var cmp := RosterSweep.compare(rows, OUT)
	var fired := (cmp["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return bool(v["fired"])).size()
	var bad := (cmp["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return str(v["first_diff"]) != "").size()
	print("IGNORE_BY_NAME epoch=%d seeds=%d fired=%d mismatches=%d" % [epoch, SEEDS, fired, bad])
	assert_int(fired).override_failure_message("the fixture throws no die: nothing is compared").is_equal(SEEDS)
	return {"bad": bad, "problems": cmp["problems"]}


func _fixtures() -> Array:
	var self_repair := _entry("Walker", 10, ["Self-Repair"], [], "robot_legions", 0)
	return [
		["Self-Repair vs Rending", _entry("Gunners", 10, [], ["Rending"], "battle_brothers"), self_repair],
		["Self-Repair vs Unstoppable", _entry("Gunners", 10, [], ["Unstoppable"], "battle_brothers"), self_repair],
		["Self-Repair vs Bane", _entry("Gunners", 10, [], ["Bane"], "battle_brothers"), self_repair],
	]


func test_the_core_rolls_a_bypassed_wound_against_a_rule_not_named_regeneration_from_epoch_82() -> void:
	for f in _fixtures():
		var old := await _run(f[1], f[2], 81)
		assert_int(int(old["bad"])).override_failure_message("%s: epoch 81 must differ (the red leg)" % f[0]).is_greater(0)
		var now := await _run(f[1], f[2], 82)
		assert_int(int(now["bad"])).override_failure_message("%s: epoch 82 table and core differ" % f[0]).is_equal(0)


## CONTROL (the check can fail): the bypass still skips the roll of the rule really named Regeneration, at both epochs.
func test_a_bypass_still_skips_the_regeneration_rule_at_both_epochs() -> void:
	var regen := _entry("Medics", 10, ["Regeneration"], [], "battle_brothers", 0)
	var gun := _entry("Gunners", 10, [], ["Rending"], "battle_brothers")
	for epoch in [81, 82]:
		var r := await _run(gun, regen, epoch)
		assert_int(int(r["bad"])).override_failure_message("epoch %d: Regeneration vs Rending differs" % epoch).is_equal(0)
