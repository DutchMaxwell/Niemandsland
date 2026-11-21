extends GdUnitTestSuite
## COVERAGE LEDGER, AI shoot door (lane covfix-lines, 21.11.): the label and line classes between the table and the door that the ledger
## (ds/coverage/ledger_shoot_m1.md) found among its constructed volleys. Lines and labels only: every check compares the roll records (kind,
## count, target, faces, owner), the end state and the battle-log lines of a volley on the table and through the door, over 16 seeds.
## Each case names one `probe` line the TABLE said on at least one seed, so a check on lines proves something. Fixtures are the ledger's legs
## (unit rules on both units, 5 shooters with a Rifle of two attacks, AP(1), a target of five Tough(3) models 14 inches away).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://ledger_lines_dice"
const SEEDS := 16

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(uname: String, system: String, faction: String, rules: Array, rifle_rules := ["AP(1)"]) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = 5
	ou.quality = 4
	ou.defense = 4
	ou.game_system = system
	ou.special_rules.assign(rules)
	if uname == "Cov Shooter":
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Rifle"
		w.range_value = 24
		w.attacks = 2
		w.count = 5
		w.special_rules.assign(rifle_rules)
		ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": system}


## One ledger leg: `rule` on both units (the target also Tough(3), and Regeneration when `regen`), the shooter's rifle rules as given.
func _leg(system: String, faction: String, rule: String, regen := false, rifle_rules := ["AP(1)"]) -> Array:
	var att_rules: Array = [rule] if not rule.is_empty() else []
	var tgt_rules: Array = ["Tough(3)"] + (["Regeneration"] if regen else []) + att_rules
	return [_unit("Cov Shooter", system, faction, att_rules, rifle_rules), _unit("Cov Target", system, faction, tgt_rules)]


## The lead's ruled label class (21.11.): a save target past 6+ is recorded and printed as 7+ .. 9+ by the table and clamped to 6+ by the core (a natural
## 6 always saves, both sides follow the book), so a defense roll's target and the number of a "defends:" line are compared as min(target, 6).
func _kinds(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%d:%s:%s" % [r["kind"], int(r["count"]),
		mini(int(r["target"]), 6) if str(r["kind"]) == "defense" else int(r["target"]), r["owner"], r["faces"]])


func _lines(lines: Array) -> Array:
	var re := RegEx.create_from_string("\\((\\d+)\\+\\)")
	return lines.map(func(l: String) -> String:
		var m := re.search(l)
		if l.contains("defends:") and m != null and int(m.get_string(1)) > 6:
			return l.replace("(%s+)" % m.get_string(1), "(6+)")
		return l)


## Seeds (of 16) whose roll records, end state or battle-log lines differ between the table and the door, and the seeds where the table
## said a line that begins with `probe` ("COMBAT|" + text) or a roll of kind `probe_kind`.
func _differing(leg: Array, probe: String, probe_kind := "") -> Dictionary:
	var dice := ProjectSettings.globalize_path(DICE)
	var bad := 0
	var said := 0
	for s in SEEDS:
		var t := await RosterSweep.volley(_main, leg[0], leg[1], s, false, dice)
		var c := await RosterSweep.volley(_main, leg[0], leg[1], s, true, dice)
		if t["lines"].any(func(l: String) -> bool: return not probe.is_empty() and l.begins_with("COMBAT|" + probe)) \
				or t["rolls"].any(func(r: Dictionary) -> bool: return not probe_kind.is_empty() and str(r["kind"]) == probe_kind):
			said += 1
		if _kinds(t["rolls"]) != _kinds(c["rolls"]) or RosterSweep.first_state_diff(t["state"], c["state"]) != "" or _lines(t["lines"]) != _lines(c["lines"]):
			bad += 1
	return {"bad": bad, "said": said}


func _expect_equal(name: String, leg: Array, probe: String, probe_kind := "") -> void:
	var r: Dictionary = await _differing(leg, probe, probe_kind)
	assert_int(int(r["said"])).override_failure_message("%s: the table never said / rolled the probe, the check proved nothing" % name).is_greater(0)
	assert_int(int(r["bad"])).override_failure_message("%s: %d of %d seeds differ in the roll records, the end state or the lines" % [name, r["bad"], SEEDS]).is_equal(0)


## Ledger 1 (101 cells): the table asks every wound-ignore die as `regeneration`; the door's step called it `attack`, so the roll record's label
## differed, and the door's own volley beats read the die as a hit roll. A target with Regeneration, Tough(3), 16 seeds, the kinds compared.
func test_a_regeneration_die_carries_the_tables_kind() -> void:
	await _expect_equal("Regeneration", _leg("gf", "battle_brothers", "", true), "", "regeneration")


## Ledger 2 (21 cells): the pick line names the book rule the bearer carries, whatever its spelling.
func test_the_versatile_pick_names_the_rule_the_bearer_carries() -> void:
	for c in [["Versatile Warrior", "aof", "human_empire"], ["Enhanced Watchborn", "gf", "watch_brothers"], ["Enhanced Vinci Tech", "aof", "duchies_of_vinci"]]:
		await _expect_equal(c[0], _leg(c[1], c[2], c[0]), "%s: Cov Shooter picks" % c[0])


## Ledger 3 (20 cells): the Regeneration bypass names the unit-level rule that cuts through it (and "Rending (granted)" for a unit-level Rending).
func test_a_regeneration_bypass_names_its_rule() -> void:
	for c in [["Bane when Shooting", "aof", "human_empire", "Bane when Shooting: Regeneration ignored"],
			["Anti-Regen", "gf", "battle_brothers", "Anti-Regen: Regeneration ignored"],
			["Unstoppable when Shooting", "aof", "human_empire", "Unstoppable when Shooting: Regeneration ignored"],
			["Rending when Shooting", "gf", "battle_brothers", "Rending (granted): Regeneration ignored"]]:
		await _expect_equal(c[0], _leg(c[1], c[2], c[0], true), c[3])


## Ledger 4 (16 cells): the over-9" Defense line of Guarded / Sturdy / Versatile Defense stands before "<unit> fires at <target>".
func test_the_over_nine_defense_line_stands_before_the_announce() -> void:
	for c in [["Guarded", "aof", "deep_sea_elves"], ["Sturdy", "gf", "dwarf_guilds"], ["Versatile Defense", "aof", "change_disciples"]]:
		await _expect_equal(c[0], _leg(c[1], c[2], c[0]), "Cov Target (%s): shot from over 9" % c[0])
