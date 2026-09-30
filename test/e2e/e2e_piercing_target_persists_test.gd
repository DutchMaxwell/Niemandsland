extends GdUnitTestSuite
## E2E — D42 (a), PLAN_wave3_2026-09-27.md step 21: Piercing Target's +AP(X) stands while the
## target lives (army-book v3.5.3, no page: "place X markers on it. Friendly units get +AP(X)
## on their weapons when attacking it" — no removal clause, no duration). Before this fix,
## `_solo_spend_piercing_tag` zeroed the pool for every source alike; from
## `EPOCH_67_MARKERS_BURSTS` only "Piercing Target" persists, the plain "Piercing Tag" primitive
## still spends whole (CONTROL below).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Player 2 (the AI slot per before_test) carrying the given family name, in the GF faction whose
## book actually prints it (rules_mechanics_gf.json: custodian_brothers = Piercing Target,
## alien_hives = the plain Piercing Tag).
func _tagger(name: String, rule: String, faction: String, pos: Vector3) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 2, name, [pos]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = [rule]
	return u


func _target(pos: Vector3) -> GameUnit:
	return _reg(E2EBoot.make_unit(_main, 1, "Marked", [pos]))


func test_piercing_target_marker_survives_two_spends() -> void:
	var tagger := _tagger("Marksman", "Piercing Target", "custodian_brothers", Vector3.ZERO)
	var tgt := _target(Vector3(10.0 * INCH, 0, 0))
	_main._solo_apply_piercing_tag(tagger)
	assert_str(str(tgt.unit_properties.get("piercing_tag_source", ""))) \
		.override_failure_message("the placement must stamp which rule placed the marker") \
		.is_equal("Piercing Target")
	var first: int = _main._solo_spend_piercing_tag(tgt)
	assert_int(first).override_failure_message("the first volley must see the placed marker").is_equal(1)
	var second: int = _main._solo_spend_piercing_tag(tgt)
	assert_int(second) \
		.override_failure_message("D42 a: Piercing Target's +AP stands while the target lives — the book has no removal clause") \
		.is_equal(1)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log — got: %s" % text.strip_edges()) \
		.contains("Piercing Target: +AP(1) stands while Marked lives")


## CONTROL: the plain "Piercing Tag" primitive (no "Target" text) must still spend whole — the
## fix is a persistence for the NAMED book text, not a blanket change to the shared marker pool.
func test_plain_piercing_tag_still_spends_whole() -> void:
	var tagger := _tagger("Grunt", "Piercing Tag", "alien_hives", Vector3.ZERO)
	var tgt := _target(Vector3(10.0 * INCH, 0, 0))
	_main._solo_apply_piercing_tag(tagger)
	var first: int = _main._solo_spend_piercing_tag(tgt)
	assert_int(first).is_equal(1)
	var second: int = _main._solo_spend_piercing_tag(tgt)
	assert_int(second) \
		.override_failure_message("CONTROL: the plain Piercing Tag must still spend whole, not a blanket persistence") \
		.is_equal(0)
