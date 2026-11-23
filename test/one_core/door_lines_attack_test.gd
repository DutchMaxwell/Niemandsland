extends GdUnitTestSuite
## One core, door lines (lane dlines3, train 3): the rule lines an ATTACKER's rules add, in the table's words - the Shred family's pay line
## (`<rule>: N Defense rolls of 1 -> +N wounds`), the widened window's line and the once-per-volley announcement of the widening. Each part of the
## train lifts its deny entry in the same commit; this suite proves the lines equal (`door_lines.gd`: seeded volleys on the table and on the
## door, the lines that name the rule compared).
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_attack_dice"


## The door's rule lines per seed, read on main (where the table still shoots and equals the door).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SHRED_WEAPON := [
	["COMBAT|Shred: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 1 Defense roll of 1 → +1 wound"],
	["COMBAT|Shred: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred: 1 Defense roll of 1 → +1 wound"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SHRED_UNIT := [
	["COMBAT|Shred: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 1 Defense roll of 1 → +1 wound"],
	["COMBAT|Shred: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred: 1 Defense roll of 1 → +1 wound"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SHRED_WHEN_SHOOTING := [
	["COMBAT|Shred when Shooting: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred when Shooting: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred when Shooting: 1 Defense roll of 1 → +1 wound"],
	["COMBAT|Shred when Shooting: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Shred when Shooting: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred when Shooting: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Shred when Shooting: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred when Shooting: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred when Shooting: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Shred when Shooting: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred when Shooting: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Shred when Shooting: 1 Defense roll of 1 → +1 wound"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_WARBOUND := [
	["COMBAT|Warbound: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Warbound: 1 Defense roll of 1 → +1 wound"],
	["COMBAT|Warbound: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Warbound: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Warbound: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Warbound: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Warbound: 1 Defense roll of 1 → +1 wound"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ENHANCED_WARBOUND := [
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 1 Defense roll of 1 → +1 wound"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Warbound: 1 Defense roll of 1 → +1 wound"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_INFECTED := [
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 1 Defense roll of 1 → +1 wound"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 4 Defense rolls of 1 → +4 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 2 Defense rolls of 1 → +2 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 3 Defense rolls of 1 → +3 wounds"],
	["COMBAT|Enhanced Infected: unmodified 1s to block deal an extra wound at any distance on Ranks","COMBAT|Enhanced Infected: 1 Defense roll of 1 → +1 wound"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_WARBOUND_BOOST := [
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 5 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 3 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 1 extra wound"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 4 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 5 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 4 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 5 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 3 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 2 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 4 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 4 extra wounds"],
	["COMBAT|Warbound Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 2 extra wounds"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_DESTROYER_BOOST := [
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 5 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 3 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 1 extra wound"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 4 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 5 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 4 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 5 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 3 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 2 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 4 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 4 extra wounds"],
	["COMBAT|Destroyer Boost: failed saves of 1-2 count as wounds on Ranks","COMBAT|Destroyer Boost: Shred on failed saves of 1-2 (over 9\") — 2 extra wounds"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_DEADLY_VS_REGENERATION := [
	["COMBAT|Deadly(3): 22 unsaved ×3, no carry-over → 35 wounds dealt (Gun)","COMBAT|Deadly(3): 16 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 24 unsaved ×3, no carry-over → 45 wounds dealt (Gun)","COMBAT|Deadly(3): 16 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 29 unsaved ×3, no carry-over → 56 wounds dealt (Gun)","COMBAT|Deadly(3): 18 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 19 unsaved ×3, no carry-over → 39 wounds dealt (Gun)","COMBAT|Deadly(3): 12 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 31 unsaved ×3, no carry-over → 50 wounds dealt (Gun)","COMBAT|Deadly(3): 22 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 30 unsaved ×3, no carry-over → 56 wounds dealt (Gun)","COMBAT|Deadly(3): 20 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 25 unsaved ×3, no carry-over → 50 wounds dealt (Gun)","COMBAT|Deadly(3): 16 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 30 unsaved ×3, no carry-over → 55 wounds dealt (Gun)","COMBAT|Deadly(3): 19 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 24 unsaved ×3, no carry-over → 44 wounds dealt (Gun)","COMBAT|Deadly(3): 16 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 26 unsaved ×3, no carry-over → 45 wounds dealt (Gun)","COMBAT|Deadly(3): 18 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 28 unsaved ×3, no carry-over → 55 wounds dealt (Gun)","COMBAT|Deadly(3): 18 wounds finish the already-wounded Tough model first (GF 3.6)"],
	["COMBAT|Deadly(3): 23 unsaved ×3, no carry-over → 42 wounds dealt (Gun)","COMBAT|Deadly(3): 15 wounds finish the already-wounded Tough model first (GF 3.6)"]]

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


func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, want: Array, min_fired := 6, opts := {}) -> void:
	var dice := ProjectSettings.globalize_path(DICE)
	var got: Array = []
	var fired := 0
	for s in SEEDS:
		var door := await RosterSweep.volley(_main, shooter, target, s, true, dice, opts)
		var lines := DoorLines.named(door["lines"], prefix)
		got.append(lines)
		fired += 1 if not lines.is_empty() else 0
	print("DOOR_LINES %s fired=%d/%d" % [label, fired, SEEDS])
	assert_int(fired).override_failure_message("%s: the rule never fired through the door, nothing is pinned" % label).is_greater_equal(min_fired)
	assert_array(got).override_failure_message("%s: the door's rule lines moved from the pinned values" % label).is_equal(want)


func _striker(rules: Array, weapon_rules: Array, faction := "battle_brothers", system := "gf", size := 10) -> Dictionary:
	var e := DoorLines.entry("Strikers", size, rules, weapon_rules, faction, size)
	(e["unit"] as OPRApiClient.OPRUnit).game_system = system
	e["system"] = system
	return e


func _ranks(defense := 5) -> Dictionary:
	var e := DoorLines.entry("Ranks", 10, [], [], "battle_brothers", 0)
	(e["unit"] as OPRApiClient.OPRUnit).defense = defense
	return e


## The Shred family: a weapon's own Shred, the unit-level rule, a data alias (Warbound), the Enhanced form (pays at any distance, announces it).
func test_the_shred_family_names_its_pay_line() -> void:
	await _same("shred weapon", _striker([], ["Shred"]), _ranks(), "Shred:", WANT_SHRED_WEAPON)
	await _same("shred unit", _striker(["Shred"], []), _ranks(), "Shred:", WANT_SHRED_UNIT)
	await _same("shred when shooting", _striker(["Shred when Shooting"], []), _ranks(), "Shred when Shooting:", WANT_SHRED_WHEN_SHOOTING)
	await _same("warbound", _striker(["Warbound"], [], "war_disciples"), _ranks(), "Warbound:", WANT_WARBOUND)
	await _same("enhanced warbound", _striker(["Warbound", "Enhanced Warbound"], [], "war_disciples"), _ranks(), "Enhanced Warbound:", WANT_ENHANCED_WARBOUND)
	await _same("infected", _striker(["Infected", "Enhanced Infected"], [], "infected_colonies"), _ranks(), "Enhanced Infected:", WANT_INFECTED)


## The 3.5 Boost widens the window of failed saves to 1-2 past 9": its announcement once per volley and its pay line (aofr: Warbound Boost).
func test_the_shred_boost_names_its_window() -> void:
	await _same("warbound boost", _striker(["Warbound", "Warbound Boost"], [], "war_disciples", "aofr"), _ranks(), "Warbound Boost:", WANT_WARBOUND_BOOST, 6, {"distance_in": 14.0})
	await _same("destroyer boost", _striker(["Destroyer", "Destroyer Boost"], [], "ogres", "aofr"), _ranks(), "Destroyer Boost:", WANT_DESTROYER_BOOST, 6, {"distance_in": 14.0})


## Deadly at a Tough target that has an ignore group: every unsaved Deadly wound takes its pick BEFORE the ignore roll (the table's `deadly_pick`), so
## the "finish the already-wounded Tough model first" count includes a wound whose X were all ignored; the core dropped such a wound and counted one
## forced pick too few. Many shooters and a Defense 6+ target make all-ignored wounds (three 5+ dice) turn up within the seeds.
func test_deadly_counts_the_picks_of_ignored_wounds() -> void:
	var target := DoorLines.entry("Ranks", 10, ["Regeneration", "Tough(6)"], [], "battle_brothers", 0)
	(target["unit"] as OPRApiClient.OPRUnit).defense = 6
	await _same("deadly vs regeneration", _striker([], ["Deadly(3)"], "battle_brothers", "gf", 30), target, "Deadly(3):", WANT_DEADLY_VS_REGENERATION, 6)
