extends GdUnitTestSuite
## AIG-G2 R4 (0.3.15): "Increased Shooting Range" on a JOINED HERO never extended the reach the shooting gates read.
## The gates ask `_gate_reach_in(host)`: the longest gun of the living chain plus the HOST's range bonus, so a hero
## carrying the rule (his own book rule, or the base an aura expansion wrote) printed "no shot - nearest enemy 17.2"
## away, weapon reach 12"" (aof_1000_net_031, ratmen Grenadiers + Getrie Veikasip). From EPOCH_73_V36 the gate reads
## each living member's own gun plus that member's own bonus, the same pairing the volley fires. The ratmen case is
## built through the real offline importer, the real joined-hero pass and the real aura expansion; the gf case is a
## hand-built host + hero because the importer fixture list is aof. Controls first (gdUnit drops cases declared after a
## failing one in a scene suite). Rust twin: `core/nml-core/src/tests/sim/range_grant_core.rs`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RATMEN := "res://test/fixtures/card_list_aof_ratmen_1500.json"
const INCH := 0.0254
const SEED := Vector3(0.03, 0.0, 0.03)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The real ratmen export with Getrie Veikasip re-joined to the Grenadiers (the gate's own pairing). `base_rule`
## true writes the Tinkering Inventor's content as the BASE rule (what the shipped AI list aof_ratmen_1000 carries:
## the hero alone has it, no aura expansion reaches the host); false keeps the Aura spelling of the fixture.
func _import_ratmen_getrie_with_grenadiers(base_rule: bool) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RATMEN))
	var grenadiers_sel := ""
	for u: Dictionary in data.get("units", []):
		if str(u.get("name", "")) == "Grenadiers":
			grenadiers_sel = str(u.get("selectionId", ""))
	for u: Dictionary in data.get("units", []):
		if str(u.get("name", "")) == "Getrie Veikasip":
			u["joinToUnit"] = grenadiers_sel
			if base_rule:
				for it: Dictionary in u.get("items", []):
					for c: Dictionary in it.get("content", []):
						c["name"] = "Increased Shooting Range"
	var client := OPRApiClient.new()
	var army := client.build_army_offline(data)
	army.player_id = 1
	var by_unit := {}
	for unit: OPRApiClient.OPRUnit in army.units:
		var nodes: Array[Node3D] = []
		for i in range(maxi(unit.size, 1)):
			var n := Node3D.new()
			_main.object_manager.add_child(n)
			nodes.append(n)
		var gu := EquipmentDistributor.create_from_opr_unit(unit, nodes, 1)
		gu.unit_properties["faction_folder"] = army.faction_folder
		by_unit[unit] = gu
	OPRArmyManager.attach_joined_heroes_of(army.units, by_unit)
	OPRArmyManager.expand_auras_of(army.units, by_unit)
	var out := {}
	for unit: OPRApiClient.OPRUnit in army.units:
		var gu: GameUnit = by_unit[unit]
		_main.opr_army_manager.unit_to_game_unit[unit] = gu
		_main.opr_army_manager.game_units[gu.unit_id] = gu
		out[unit.name] = gu
	client.free()
	return out


func _weapon(wname: String, range_in: int) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = range_in
	w.attacks = 1
	w.count = 1
	return w


func _armed(u: GameUnit, weapon: OPRApiClient.OPRWeapon, rules: Array) -> void:
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "alien_hives"
	u.unit_properties["special_rules"] = rules
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons.append(weapon)
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u


## A gf host with a 12" gun and a joined hero (gf alien_hives Grunt Veteran shape) with a 12" gun and `hero_rules`.
func _host_and_hero(hero_rules: Array) -> Array:
	var host := E2EBoot.make_unit(_main, 1, "Grunts", [SEED, SEED + Vector3(2.0 * INCH, 0.0, 0.0)])
	_armed(host, _weapon("Spitter", 12), [])
	var hero := E2EBoot.make_unit(_main, 1, "Grunt Veteran", [SEED + Vector3(0.0, 0.0, 2.0 * INCH)])
	_armed(hero, _weapon("Spike Rifle", 12), hero_rules)
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	return [host, hero]


# ===== controls (green before and after the fix) =====

## No rule anywhere: the chain's longest gun is the reach, as before.
func test_a_chain_without_the_rule_reaches_its_printed_range() -> void:
	var pair := _host_and_hero([])
	assert_int(_main.solo_controller._gate_reach_in(pair[0])).is_equal(12)


## The host's own rule still lifts the host's gun (no regression on the standalone carrier).
func test_a_host_carrying_the_rule_reaches_18() -> void:
	var host := E2EBoot.make_unit(_main, 1, "Grunts", [SEED])
	_armed(host, _weapon("Spitter", 12), ["Increased Shooting Range"])
	assert_int(_main.solo_controller._gate_reach_in(host)).is_equal(18)


## Below the 3.6 epoch the host-only bonus stands byte for byte.
func test_below_73_a_hero_rule_does_not_lift_the_gate() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var pair := _host_and_hero(["Increased Shooting Range"])
	assert_int(_main.solo_controller._gate_reach_in(pair[0])).is_equal(12)


## The Aura spelling (the 1500 fixture) already reached the host through the import's aura expansion: 18 before and after.
func test_the_aura_spelling_reaches_18_through_the_expansion() -> void:
	var units := _import_ratmen_getrie_with_grenadiers(false)
	assert_int(_main.solo_controller._gate_reach_in(units["Grenadiers"])).is_equal(18)


# ===== the fix (RED before) =====

## gf alien_hives: the hero carries the base rule itself; his 12" gun reaches 18", the host's stays 12".
func test_a_joined_hero_carrying_the_rule_lifts_the_gate_to_18_at_73() -> void:
	var pair := _host_and_hero(["Increased Shooting Range"])
	assert_int(SoloController.shooting_range_bonus(pair[1])).is_equal(6)
	assert_int(_main.solo_controller._gate_reach_in(pair[0])) \
		.override_failure_message("the hero's own +6\" never reached the gate (host-only bonus read)").is_equal(18)


## aof ratmen, the report's probe: Grenadiers (12" Toxin Bombs) + Getrie Veikasip (12" Artificer Bombs, the Tinkering
## Inventor's Increased Shooting Range as his OWN rule). Imported and joined the way the game does it. The host's own
## gun stays at 12" (the rule is the hero's); the unit's gate reach is the hero's 12 + 6.
func test_ratmen_grenadiers_with_getrie_reach_18_at_73() -> void:
	var units := _import_ratmen_getrie_with_grenadiers(true)
	var host: GameUnit = units["Grenadiers"]
	var hero: GameUnit = units["Getrie Veikasip"]
	assert_array(host.get_attached_heroes()).override_failure_message("fixture: Getrie is not joined").contains([hero])
	assert_int(SoloController.shooting_range_bonus(hero)) \
		.override_failure_message("Getrie's own Increased Shooting Range was not read").is_equal(6)
	assert_int(SoloController.shooting_range_bonus(host)).override_failure_message("the hero's rule is not the host's").is_equal(0)
	assert_int(_main.solo_controller._gate_reach_in(host)) \
		.override_failure_message("ratmen Grenadiers + Getrie: weapon reach must be 18\"").is_equal(18)


## The live gate: a foe 15" from the host's nearest model is past every host gun and inside the hero's 12 + 6, so the
## Hold intent opens the shot, and the table's range line names the BOOK rule for the hero.
func test_the_hold_gate_opens_for_the_heros_lifted_gun_at_73() -> void:
	var pair := _host_and_hero(["Increased Shooting Range"])
	var foe := E2EBoot.make_unit(_main, 2, "Foes", [SEED + Vector3(17.0 * INCH, 0.0, 0.0)])
	foe.unit_properties["game_system"] = "gf"
	foe.unit_properties["special_rules"] = []
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	var solo: SoloController = _main.solo_controller
	var intent := solo.player_intent(pair[0], AiDecision.Action.HOLD, foe)
	intent["source"] = "player"
	var report := solo.execute_intent(intent, ActIntent.blank_report(pair[0]))
	assert_bool(bool(report["can_shoot"])) \
		.override_failure_message("the hero's 12\" gun + 6\" reaches the foe; the gate read the host's 12\" only").is_true()
	_main._solo_log_range_bonus(pair[0], foe)
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).override_failure_message("rules-must-log: the book rule names itself (log: %s)" % text) \
		.contains("Increased Shooting Range +6")
