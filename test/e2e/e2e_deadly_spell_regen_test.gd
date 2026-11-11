extends GdUnitTestSuite
## E2E — play-test fix A4 for damage SPELLS (maintainer rulings 29.10.2026): Deadly(X) against the
## Regeneration family rolls one die PER WOUND AFTER the multiplication ("Ne, man wuerfelt pro Wunde einen
## Reparaturwurf"), and on a model with fewer wounds left than X all X dice are still rolled before the cap
## ("Drei Wuerfe muessen gelingen").
##
## #1914 fixed the weapons' per-model landing (`_solo_land_deadly_wounds`). A damage spell still took the
## pooled path: `_solo_deadly_wounds` multiplied by the Tough-capped factor first, and the Regeneration roll
## came after, on the capped count — a Deadly(3) spell on 1-wound models rolled ONE die per wound. Now a
## Deadly spell's unsaved wounds land through the same per-model landing (Resistance keeps its spell
## threshold). These cases ride the real spell-damage resolution on scenes/main.tscn with an AI-owned
## target, so every die auto-rolls.

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
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _caster() -> GameUnit:
	var c := E2EBoot.make_unit(_main, 1, "Mystic", [Vector3.ZERO])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	opr.weapons = ws
	c.source_type = "opr"
	c.source_data = opr
	_main.opr_army_manager.game_units[c.unit_id] = c
	return c


## An AI-owned unit of three models with `tough` wounds each, every model carrying `rule`.
func _foe(rule: String, tough: int) -> GameUnit:
	var positions: Array = []
	for i in range(3):
		positions.append(Vector3(6.0 * INCH, 0, 0.03 * i))
	var u := E2EBoot.make_unit(_main, 2, "Brutes", positions)
	var rules: Array = [rule]
	if tough > 1:
		rules.append("Tough(%d)" % tough)
	u.unit_properties["special_rules"] = rules
	for m in u.models:
		(m as ModelInstance).wounds_max = tough
		(m as ModelInstance).wounds_current = tough
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## AP(4) against the fixture's Defense 4+: only natural 6s save, so most hits go through.
func _cast(foe: GameUnit, hits: int, weapon_rules: Array) -> String:
	var entry := {"effect": {"kind": "damage", "hits": hits, "weapon_rules": weapon_rules},
		"target": {"kind": "unit", "side": "enemy"}}
	var caster := _caster()
	_main.seed_tray_rng(5)
	await _main._solo_resolve_spell_damage(caster, caster, "Test Bolt", entry, foe)
	return _log_text()


## Every "<foe> rolls N <rule> di… (T+) — K wound(s) ignored" line as [N, T, K].
func _rolls(text: String, rule: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("Brutes rolls (\\d+) %s dic?e \\((\\d)\\+\\) — (\\d+) wounds? ignored" % rule)
	for m in re.search_all(text):
		out.append([int(m.get_string(1)), int(m.get_string(2)), int(m.get_string(3))])
	return out


# ===== the ruling =====

## The claim: each unsaved wound of a Deadly(3) spell on 1-wound Regeneration models is three wounds and
## three dice; a model survives only when all three are ignored.
func test_deadly_spell_rolls_regeneration_for_every_multiplied_wound() -> void:
	var foe := _foe("Regeneration", 1)
	var text := await _cast(foe, 2, ["AP(4)", "Deadly(3)"])
	var rolls := _rolls(text, "regeneration")
	assert_int(rolls.size()) \
		.override_failure_message("A4 for spells — every unsaved Deadly wound gets its own roll (log: %s)" % text.strip_edges()) \
		.is_greater(0)
	var killed := 0
	for r in rolls:
		assert_int(int(r[0])) \
			.override_failure_message("A4 for spells — one die per wound AFTER the ×3 (log: %s)" % text.strip_edges()) \
			.is_equal(3)
		if int(r[2]) < 3:
			killed += 1
	assert_int(foe.get_alive_count()) \
		.override_failure_message("\"Drei Wuerfe muessen gelingen\" — a model with 1 wound needs all three (log: %s)" % text.strip_edges()) \
		.is_equal(3 - killed)
	assert_str(text).contains("no carry-over")
	assert_str(text).not_contains("Tough-capped")
	await E2EBoot.settle(get_tree())


## The Tough cap limits the WOUNDS, not the rolls: one Deadly(3) spell wound on a fresh Tough(2) model rolls
## three dice, then at most two wounds land on that one model and nothing carries over. (Seed 5: of the two
## save dice one is a 6, so exactly one wound goes through.)
func test_deadly_spell_tough_cap_limits_the_wounds_not_the_rolls() -> void:
	var foe := _foe("Regeneration", 2)
	var text := await _cast(foe, 2, ["AP(4)", "Deadly(3)"])
	var rolls := _rolls(text, "regeneration")
	assert_int(rolls.size()) \
		.override_failure_message("A4 for spells — the one unsaved wound gets one roll (log: %s)" % text.strip_edges()) \
		.is_equal(1)
	if rolls.size() != 1:
		return
	assert_int(int(rolls[0][0])) \
		.override_failure_message("A4 for spells — all 3 wounds are rolled before the Tough(2) cap (log: %s)" % text.strip_edges()) \
		.is_equal(3)
	var hurt := 0
	for m in foe.models:
		if (m as ModelInstance).wounds_current < 2 or not (m as ModelInstance).is_alive:
			hurt += 1
	assert_int(hurt).override_failure_message("no carry-over: one model takes the wound").is_less_equal(1)
	await E2EBoot.settle(get_tree())


## Resistance keeps its SPELL threshold (2+) on the per-model landing: three dice per wound, at 2+.
func test_deadly_spell_against_resistance_rolls_at_the_spell_threshold() -> void:
	var foe := _foe("Resistance", 1)
	var text := await _cast(foe, 2, ["AP(4)", "Deadly(3)"])
	var rolls := _rolls(text, "resistance")
	assert_int(rolls.size()) \
		.override_failure_message("A4 for spells — Resistance rolls per unsaved Deadly wound (log: %s)" % text.strip_edges()) \
		.is_greater(0)
	for r in rolls:
		assert_int(int(r[0])).override_failure_message("three dice per wound (log: %s)" % text.strip_edges()).is_equal(3)
		assert_int(int(r[1])).override_failure_message("spell wounds: Resistance ignores on 2+ (log: %s)" % text.strip_edges()).is_equal(2)
	await E2EBoot.settle(get_tree())


# ===== controls =====

## CONTROL: a spell without Deadly keeps the pooled landing — one die per unsaved wound, no Deadly line.
func test_a_plain_spell_still_rolls_once_per_wound() -> void:
	var foe := _foe("Regeneration", 1)
	var text := await _cast(foe, 2, ["AP(4)"])
	var rolls := _rolls(text, "regeneration")
	assert_int(rolls.size()).override_failure_message("log: %s" % text.strip_edges()).is_equal(1)
	assert_int(int(rolls[0][0]) if rolls.size() == 1 else -1).is_less_equal(2)
	assert_str(text).not_contains("Deadly(")
	await E2EBoot.settle(get_tree())


## CONTROL: Deadly wounds that ignore Regeneration (Bane) roll nothing, and the skip is logged (A1).
func test_a_regen_proof_deadly_spell_rolls_nothing_and_says_so() -> void:
	var foe := _foe("Regeneration", 1)
	var text := await _cast(foe, 2, ["AP(4)", "Deadly(3)", "Bane"])
	assert_str(text).not_contains("regeneration di")
	assert_str(text).contains("ignore Regeneration — no regeneration roll")
	await E2EBoot.settle(get_tree())
