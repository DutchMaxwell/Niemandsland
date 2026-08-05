extends GdUnitTestSuite
## NML-936 (BUG B2) — `requires_not_shaken` is written into the "Spell Conduit" registry entry's
## params but read by nobody. scripts/main.gd's _solo_resolve_one_cast HARDCODES
## `cu.is_shaken` in the Spell Conduit sweep's outer guard instead of reading the rule's own
## requires_not_shaken param, and logs nothing when a conduit is skipped for being Shaken. A
## conduit whose data says the Shaken requirement does NOT apply (requires_not_shaken: false)
## pins the fix: without reading that param the sweep would skip it unconditionally while Shaken.
##
## Drives the REAL _solo_resolve_one_cast over main.tscn in batch mode (_solo_batch = true —
## the harness lever e2e_defense_log_labels_test.gd already uses for instant, non-physics
## dice), so the whole cast flow — including the die roll the +1 feeds into — runs headless in
## one frame. Registry data comes from the same RulesRegistry._cache injection pattern
## test/rules_registry_test.gd's _inject_gf_map uses.

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
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true   # instant, non-physics dice — see e2e_defense_log_labels_test.gd


func after_test() -> void:
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## Synthetic map: "Spell Conduit" explicitly opts OUT of the Shaken requirement.
func _inject_conduit_map() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {"testfac": {
		"Spell Conduit": {"primitive": "Spell Conduit",
			"params": {"casting_mod": 1, "range_in": 12.0, "requires_not_shaken": false}},
	}}, "common": {}}


## A caster (pid 1) and a SHAKEN conduit (pid 1) 6" apart — well inside the rule's 12" range —
## both registered in opr_army_manager.game_units (_solo_resolve_one_cast's Spell Conduit
## sweep reads get_game_units_for_player, not a scene walk).
func _caster_and_shaken_conduit() -> Dictionary:
	var caster := E2EBoot.make_unit(_main, 1, "Caster", [Vector3.ZERO])
	caster.unit_properties["game_system"] = "gf"
	caster.unit_properties["faction_folder"] = "testfac"
	_main.opr_army_manager.game_units[caster.unit_id] = caster
	var conduit := E2EBoot.make_unit(_main, 1, "Conduit", [Vector3(6.0 * INCH, 0, 0)])
	conduit.unit_properties["game_system"] = "gf"
	conduit.unit_properties["faction_folder"] = "testfac"
	conduit.unit_properties["special_rules"] = ["Spell Conduit"]
	conduit.is_shaken = true
	_main.opr_army_manager.game_units[conduit.unit_id] = conduit
	return {"caster": caster, "conduit": conduit}


func test_a_shaken_spell_conduit_is_named_in_the_log(timeout := 240000) -> void:
	_inject_conduit_map()
	var fixture := _caster_and_shaken_conduit()
	var caster: GameUnit = fixture["caster"]
	# A minimal self-targeted buff cast — the assertion only cares about the casting_mod line
	# logged BEFORE the die roll, so the spell's own effect is deliberately inert.
	var cast := {"caster": caster, "caster_unit": caster, "name": "Test Buff",
		"spell": {"effect": {"kind": "buff"}}, "targets": [caster], "boost": 0, "interference": 0}
	await _main._solo_resolve_one_cast(cast)
	assert_str(_log_text()) \
		.override_failure_message("NML-936 — a Spell Conduit whose OWN params say requires_not_shaken: " +
			"false was still skipped for being Shaken (_solo_resolve_one_cast hardcodes cu.is_shaken " +
			"instead of reading the param; log:\n%s)" % _log_text()) \
		.contains("+1 to casting rolls")
	await E2EBoot.settle(get_tree())


## NML-981 — the 12" is measured base edge to base edge (nearest models), like every other
## ranged check (the AI's own conduit-origin sweep + NML-206 precedent). Two 60 mm bases
## 13" apart at the CENTRES stand only ~10.6" apart at the EDGES — in range by the book;
## the old unit-centre reading denied that legal +1. The 15" pair guards the other
## direction: ~12.6" at the edges stays out.
func _caster_and_wide_conduit(centre_gap_in: float) -> GameUnit:
	var caster := E2EBoot.make_unit(_main, 1, "Caster", [Vector3.ZERO])
	caster.unit_properties["game_system"] = "gf"
	caster.unit_properties["faction_folder"] = "testfac"
	caster.unit_properties["base_size_round"] = 60
	_main.opr_army_manager.game_units[caster.unit_id] = caster
	var conduit := E2EBoot.make_unit(_main, 1, "Conduit", [Vector3(centre_gap_in * INCH, 0, 0)])
	conduit.unit_properties["game_system"] = "gf"
	conduit.unit_properties["faction_folder"] = "testfac"
	conduit.unit_properties["base_size_round"] = 60
	conduit.unit_properties["special_rules"] = ["Spell Conduit"]
	_main.opr_army_manager.game_units[conduit.unit_id] = conduit
	return caster


func _run_inert_cast(caster: GameUnit) -> void:
	var cast := {"caster": caster, "caster_unit": caster, "name": "Test Buff",
		"spell": {"effect": {"kind": "buff"}}, "targets": [caster], "boost": 0, "interference": 0}
	await _main._solo_resolve_one_cast(cast)


func test_a_wide_based_conduit_at_13in_centres_gives_the_plus_one(timeout := 240000) -> void:
	_inject_conduit_map()
	var caster := _caster_and_wide_conduit(13.0)
	await _run_inert_cast(caster)
	assert_str(_log_text()) \
		.override_failure_message("NML-981 — 60 mm pair, 13\" at the centres = ~10.6\" at the " +
			"edges: IN range by the book, but the unit-centre reading denies the +1 (log:\n%s)" % _log_text()) \
		.contains("+1 to casting rolls")
	await E2EBoot.settle(get_tree())


func test_a_pair_beyond_12in_at_the_edges_stays_out_of_range(timeout := 240000) -> void:
	_inject_conduit_map()
	var caster := _caster_and_wide_conduit(15.0)
	await _run_inert_cast(caster)
	assert_str(_log_text()) \
		.override_failure_message("NML-981 guard — 60 mm pair, 15\" centres = ~12.6\" edges: " +
			"OUT of range, no conduit bonus may appear (log:\n%s)" % _log_text()) \
		.not_contains("+1 to casting rolls")
	await E2EBoot.settle(get_tree())
