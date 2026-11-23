extends GdUnitTestSuite
## COVERAGE LEDGER, AI shoot door (lane covfix-lines, 21.11.): the label and line classes between the table and the door that the ledger
## (ds/coverage/ledger_shoot_m1.md) found among its constructed volleys. Lines and labels only: every check compares the roll records (kind,
## count, target, faces, owner), the end state and the battle-log lines of a volley on the table and through the door, over 16 seeds.
## Each case names one `probe` line the TABLE said on at least one seed, so a check on lines proves something. Fixtures are the ledger's legs
## (unit rules on both units, 5 shooters with a Rifle of two attacks, AP(1), a target of five Tough(3) models 14 inches away).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://ledger_lines_dice"
const SEEDS := 16

## The door's rule lines and roll kinds per seed, read on main (where the table still shoots and equals the door).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT := {
	"Regeneration": {"lines": [[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[]], "kinds": [1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1]},
	"Versatile Warrior": {"lines": [["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Versatile Warrior: Cov Shooter picks +1 to hit for this activation"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Enhanced Watchborn": {"lines": [["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Watchborn: Cov Shooter picks +1 to hit for this activation"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Enhanced Vinci Tech": {"lines": [["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"],["COMBAT|Enhanced Vinci Tech: Cov Shooter picks +1 to hit for this activation"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Bane when Shooting": {"lines": [["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"],["COMBAT|Bane when Shooting: Regeneration ignored"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Anti-Regen": {"lines": [["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"],["COMBAT|Anti-Regen: Regeneration ignored"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Unstoppable when Shooting": {"lines": [["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"],["COMBAT|Unstoppable when Shooting: Regeneration ignored"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Rending when Shooting": {"lines": [["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"],["COMBAT|Rending (granted): Regeneration ignored"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Guarded": {"lines": [["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Guarded): shot from over 9\" — +1 Defense (saves on 3+)"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Sturdy": {"lines": [["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Versatile Defense": {"lines": [["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"],["COMBAT|Cov Target (Versatile Defense): shot from over 9\" — +1 Defense (saves on 3+)"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},
	"Takedown": {"lines": [["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is killed"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is killed"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is wounded"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is wounded"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is killed"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is killed"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is killed"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is killed"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is wounded"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is wounded"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is killed"],[],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is wounded"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is wounded"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is killed"],["COMBAT|Takedown (Rifle): the Tough(3) model of Cov Target is wounded"]], "kinds": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}}


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


## The door's rule lines that begin with `probe` ("COMBAT|" + text) and its rolls of kind `probe_kind`, per seed, against the pinned values.
func _expect_equal(name: String, leg: Array, probe: String, probe_kind := "") -> void:
	var dice := ProjectSettings.globalize_path(DICE)
	var want: Dictionary = WANT[name]
	var got_lines: Array = []
	var got_kinds: Array = []
	var fired := 0
	for s in SEEDS:
		var door := await RosterSweep.volley(_main, leg[0], leg[1], s, true, dice)
		var lines: Array = door["lines"].filter(func(l: String) -> bool: return not probe.is_empty() and l.begins_with("COMBAT|" + probe))
		var kinds: int = door["rolls"].filter(func(r: Dictionary) -> bool: return not probe_kind.is_empty() and str(r["kind"]) == probe_kind).size()
		got_lines.append(lines)
		got_kinds.append(kinds)
		fired += 1 if (not lines.is_empty() or kinds > 0) else 0
	print("DOOR_LINES %s fired=%d/%d" % [name, fired, SEEDS])
	assert_int(fired).override_failure_message("%s: the door never said / rolled the probe, nothing is pinned" % name).is_greater(0)
	assert_array(got_lines).override_failure_message("%s: the door's rule lines moved from the pinned values" % name).is_equal(want["lines"])
	assert_array(got_kinds).override_failure_message("%s: the door's roll kinds moved from the pinned values" % name).is_equal(want["kinds"])


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


## Ledger 5 (6 cells): a lone Takedown weapon says the casualty ("loses a model") before its own Takedown line, as the table does.
func test_a_lone_takedown_says_the_casualty_before_its_line() -> void:
	await _expect_equal("Takedown", _leg("gf", "battle_brothers", "", false, ["AP(1)", "Takedown"]), "Takedown (Rifle): the")
