extends GdUnitTestSuite
## PLAN H, the refusal tail: a rule NAME leaves the deny list (`deny_names` of assets/solo/core_slice_deny.json) once its probe reads table and core
## EQUAL on the dice, the end state of BOTH units and the rule's battle-log lines, 16 seeds per fixture. Each lifted name adds a row to CASES;
## the suite is the probe the lift's PR names (ds/h_probe_*.md). H-12: Hazardous (the 5-seed sweep showed the shooter's wounds differing on a
## natural 1, DS-N2 G9; the sweep dump never carried them, the probe reads both units).
## RED: put the name back into `deny_names` -> the unit is refused (`deny` reads the reason) and the first assertion fails. The control leg (one
## core face swapped) must read UNEQUAL, so the comparison can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://hazardous_door_dice"
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


func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


func _named(lines: Array, prefix: String) -> Array:
	return lines.filter(func(l: String) -> bool: return l.begins_with("COMBAT|" + prefix))


## 16 seeds of `shooter` at `target` on both halves; returns {"differing": seeds whose dice, end state or `prefix` lines differ,
## "lines": seeds with such a line on the table, "deny": the pair's deny-slice reasons (read on seed 0)}.
func _compare(shooter: Dictionary, target: Dictionary, prefix: String, swap_face := -1) -> Dictionary:
	var dice := ProjectSettings.globalize_path(DICE)
	var differing := 0
	var with_line := 0
	var deny: Array = []
	for s in SEEDS:
		var opts := {} if swap_face < 0 else {"core_swap_face": swap_face}
		var t := await RosterSweep.volley(_main, shooter, target, s, false, dice, opts)
		var c := await RosterSweep.volley(_main, shooter, target, s, true, dice, opts)
		if s == 0:
			deny = t["deny"]
		if not _named(t["lines"], prefix).is_empty():
			with_line += 1
		if _faces(t["rolls"]) != _faces(c["rolls"]) or RosterSweep.first_state_diff(t["state"], c["state"]) != "" \
				or _named(t["lines"], prefix) != _named(c["lines"], prefix):
			differing += 1
	return {"differing": differing, "lines": with_line, "deny": deny}


func _aof(entry: Dictionary) -> Dictionary:
	return _sys(entry, "aof")


func _sys(entry: Dictionary, system: String) -> Dictionary:
	(entry["unit"] as OPRApiClient.OPRUnit).game_system = system
	entry["system"] = system
	return entry


## H-14: an AP(2) volley at a target that holds Fortified through an aura (aofs / gff: a Fortified-primitive entry; gf / aof: an Aura Channel).
func _rifles(system: String, faction: String) -> Dictionary:
	return _sys(DoorLines.entry("Rifles AP", 10, [], ["AP(2)"], faction, 10), system)


func _squad(system: String, faction: String, rules: Array, size := 10) -> Dictionary:
	return _sys(DoorLines.entry("Squad", size, rules, [], faction, 0), system)


## [label, shooter, target, line prefix that proves the rule acted]
func _cases() -> Array:
	var plain := DoorLines.entry("Plain", 10, [], [], "battle_brothers", 0)
	var plain_aof := _aof(DoorLines.entry("Plain", 10, [], [], "human_empire", 0))
	var rifles := DoorLines.entry("Rifles", 10, [], [], "battle_brothers", 10)
	return [
		# H-12 Hazardous: the wound goes to the SHOOTING unit on an unmodified 1 to hit, line `Hazardous: <U> model N takes 1 wound (<weapon>)`.
		["Hazardous gf carbines", DoorLines.entry("Carbines", 5, [], ["Hazardous"], "ratmen_clans", 5), plain, "Hazardous"],
		["Hazardous gf lone bearer", DoorLines.entry("Bearer", 1, [], ["Hazardous"], "ratmen_clans", 1), plain, "Hazardous"],
		["Hazardous aof carbines", _aof(DoorLines.entry("Carbines", 5, [], ["Hazardous"], "ratmen", 5)), plain_aof, "Hazardous"],
		# H-13 Relentless Aura ("this model and its unit get Relentless": an unmodified 6 to hit from over 9 in is one extra hit, line
		# `Relentless: +N hits`). DS-N2 G14 was the sweep harness missing the import's aura pass (ds/h_probe_aura_names.md); `spawn` runs it now.
		["Relentless Aura gf shooters", DoorLines.entry("Auras", 10, ["Relentless Aura"], [], "robot_legions", 5), plain, "Relentless:"],
		["Relentless Aura aof shooters", _aof(DoorLines.entry("Auras", 10, ["Relentless Aura"], [], "high_elves", 5)), plain_aof, "Relentless:"],
		# H-15 Experimental Tinctures (an item whose content is `Unpredictable Shooter Aura`: the unit gets Unpredictable Shooter through the aura pass; the die's line is
		# said since #3133). The target row compares EVERY combat line of the volley. The die bearer as a SHOOTER is taken since the epoch 95 lift (the
		# guard `unpredictable_die_without_weapon_in_reach` left the file; UPR_NEEDS_SHOT fixed the cause); unpredictable_die_door_test.gd holds the below-95 difference.
		["Experimental Tinctures aof target", _aof(DoorLines.entry("Gunners", 10, [], [], "human_empire", 5)), _aof(DoorLines.entry("Alchemists", 10, ["Experimental Tinctures", "Unpredictable Shooter Aura"], [], "duchies_of_vinci", 0)), ""],
		# H-14 Fortified Aura / Guardian Boost Aura / Gleaming Armour (an item whose content is Fortified Aura), a LIVE bearer (ds/h14_probe_fortified_aura.md): dice,
		# end state and the `Fortified:` / `Guardian Boost[ Aura]:` line are equal in every system. The fallen-bearer state is refused by the slice, see below.
		["Fortified Aura aofs", _rifles("aofs", "duchies_of_vinci"), _squad("aofs", "duchies_of_vinci", ["Fortified Aura"]), "Fortified:"],
		["Fortified Aura gff", _rifles("gff", "blessed_sisters"), _squad("gff", "blessed_sisters", ["Fortified Aura"]), "Fortified:"],
		["Guardian Boost Aura aofs", _rifles("aofs", "hired_guards"), _squad("aofs", "hired_guards", ["Guardian Boost Aura"]), "Guardian Boost"],
		["Guardian Boost Aura gff", _rifles("gff", "custodian_brothers"), _squad("gff", "custodian_brothers", ["Guardian Boost Aura"]), "Guardian Boost"],
		["Fortified Aura aof channel", _rifles("aof", "mummified_undead"), _squad("aof", "mummified_undead", ["Fortified Aura"]), "Fortified:"],
		["Gleaming Armour aof bearer", _rifles("aof", "mummified_undead"), _squad("aof", "mummified_undead", ["Hero", "Gleaming Armour", "Fortified Aura"], 1), "Fortified:"],
		# H-9a: a pre-attack beat is the bearer's own act, so a bearer SHOT AT is taken (the group's side is the shooter); every combat line of the volley compared.
		["Furious Buff target", rifles, DoorLines.entry("Squad", 10, ["Furious Buff"], [], "alien_hives", 0), ""],
		["Precision Fighter Buff target", rifles, DoorLines.entry("Squad", 10, ["Precision Fighter Buff"], [], "blessed_sisters", 0), ""],
		["Speed Debuff target", rifles, DoorLines.entry("Squad", 10, ["Speed Debuff"], [], "dwarf_guilds", 0), ""],
		["Breath Attack target", rifles, DoorLines.entry("Squad", 10, ["Breath Attack"], [], "alien_hives", 0), ""],
		["Re-Position Artillery target", rifles, DoorLines.entry("Squad", 10, ["Re-Position Artillery"], [], "battle_brothers", 0), ""],
		["Mend target", rifles, DoorLines.entry("Squad", 10, ["Mend"], [], "battle_brothers", 0), ""],
		["Regeneration Buff target", rifles, DoorLines.entry("Squad", 10, ["Regeneration Buff"], [], "dark_elf_raiders", 0), ""],
		# A vs-target Mark on the SHOOTER: the bearer marks the target, its own volley gets Rending against it once,
		# the pick / record / spend lines name the Mark (#3190).
		["Rending Mark gf shooter", DoorLines.entry("Markers", 5, ["Rending Mark"], [], "orc_marauders", 5), plain, "Rending Mark"],
		["Rending Mark aof shooter", _aof(DoorLines.entry("Markers", 5, ["Rending Mark"], [], "orcs", 5)), plain_aof, "Rending Mark"],
	]


func test_a_lifted_name_is_taken_and_equal_on_both_paths() -> void:
	for c in _cases():
		var r := await _compare(c[1], c[2], c[3])
		assert_array(r["deny"]).override_failure_message("%s: the deny slice still refuses %s" % [c[0], r["deny"]]).is_empty()
		assert_int(int(r["lines"])).override_failure_message("%s: the rule never acted in 16 seeds, the check proved nothing" % c[0]).is_greater(0)
		assert_int(int(r["differing"])).override_failure_message("%s: %d of 16 seeds differ" % [c[0], r["differing"]]).is_equal(0)


## The comparison can fail: one recorded core face swapped makes every seed unequal.
func test_the_comparison_reads_a_planted_fault() -> void:
	var c: Array = _cases()[0]
	var r := await _compare(c[1], c[2], c[3], 0)
	assert_int(int(r["differing"])).override_failure_message("the planted fault was not seen").is_greater(0)


## The check the lift rests on can fail without editing the committed file: a COPY of the deny file with the name put back refuses the same
## unit (the reason the sweep reported before the lift), the committed file does not.
func _unit_with(unit_rules: Array, weapon_rules: Array, faction: String) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties["special_rules"] = unit_rules
	gu.unit_properties["game_system"] = "gf"
	gu.unit_properties["faction_folder"] = faction
	var src := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.special_rules.assign(weapon_rules)
	src.weapons.append(w)
	gu.source_type = "opr"
	gu.source_data = src
	return gu


func test_putting_the_name_back_into_the_deny_list_refuses_the_unit() -> void:
	for row in [["Hazardous", [], ["Hazardous"], "ratmen_clans", "weapon_rule:Hazardous"],
			["Relentless Aura", ["Relentless Aura"], [], "robot_legions", "unit_rule:Relentless Aura"],
			["Rending Mark", ["Rending Mark"], [], "orc_marauders", "unit_rule:Rending Mark"]]:
		var bearer := _unit_with(row[1], row[2], row[3])
		var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
		assert_array(CoreSlice.refusals_in(CoreSlice.DENY_PATH, bearer)).override_failure_message("the committed deny file refuses %s" % row[0]).is_empty()
		(committed["deny_names"] as Dictionary)[row[0]] = "put back for the check"
		var tmp := "user://deny_with_%s.json" % str(row[0]).replace(" ", "_").to_lower()
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		f.store_string(JSON.stringify(committed))
		f.close()
		assert_array(CoreSlice.refusals_in(tmp, bearer)).override_failure_message("the copy with %s does not refuse it: the check cannot fail" % row[0]).is_equal([row[4]])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
