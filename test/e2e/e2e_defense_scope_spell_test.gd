extends GdUnitTestSuite
## E2E — NML-104 (maintainer rules ruling 2026-07-31: "the wording decides"). The block step of the
## core rules is SOURCE-NEUTRAL ("roll one die for every hit that the unit has taken") and OPR names
## spells explicitly whenever a rule means them. So a GENERIC Defense modifier — a warding token's
## "+1 to defense rolls", a hex's "-1", a marker buff — counts against spell damage as well, while a
## rule whose own text limits it (Shielded: "hits that are not from spells") stays out.
##
## What was broken: the spell-damage path saved at the bare Armor-adjusted Defense, so every active
## +/- to defense rolls was silently dropped the moment the wound came from a spell — the buff the
## player had just cast did nothing, without a word in the log. These suites ride the REAL cast
## resolution on scenes/main.tscn, so the dice see what the rules say, and the log says it out loud.

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
	# Batch mode is the harness lever for the physics dice tray: fair faces, drawn instantly.
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


## A registered unit — the fixture has to live in opr_army_manager.game_units, or the AI-ownership,
## morale and wound plumbing the cast walks through never sees it.
func _unit(pid: int, unit_name: String, pos: Vector3, models: int = 3) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(pos + Vector3(0.0, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A caster with no weapons — the spell is the whole attack.
func _caster() -> GameUnit:
	var c := _unit(1, "Mystic", Vector3.ZERO, 1)
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	opr.weapons = ws
	c.source_type = "opr"
	c.source_data = opr
	return c


## The damage-spell entry the resolution reads: `hits` fixed hits, no weapon rules, unit-targeted.
func _damage_spell(hits: int = 3) -> Dictionary:
	return {"effect": {"kind": "damage", "hits": hits, "weapon_rules": []},
		"target": {"kind": "unit", "side": "enemy"}}


# ===== (1) the generic token reaches the spell's save step =====

func test_a_generic_defense_token_improves_the_spell_save(timeout := 240000) -> void:
	var caster := _caster()
	var foe := _unit(2, "Grunts", Vector3(6.0 * INCH, 0, 0))   # Defense 4+ (E2EBoot fixture)
	_main._solo_place_spell_tokens("Warding Chant", [foe], {"kind": "buff", "modifier": {"def_mod": 1}})
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_SPELL)) \
		.override_failure_message("NML-104 — a plain \"+1 to defense rolls\" has no clause, so it applies to spell damage too") \
		.is_equal(3)
	await _main._solo_resolve_spell_damage(caster, caster, "Fire Bolt", _damage_spell(), foe)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the spell's saves must be rolled at the token-improved target (log: %s)" % text.strip_edges()) \
		.contains("Grunts saves on 3+")
	assert_str(text) \
		.override_failure_message("rules-must-log: the modifier that DID apply must be named (log: %s)" % text.strip_edges()) \
		.contains("+1 defense vs spell damage — Warding Chant")


# ===== (2) Shielded keeps its own clause — the standing behaviour must not flip =====

func test_shielded_stays_out_of_the_spell_save_and_says_so(timeout := 240000) -> void:
	var caster := _caster()
	var foe := _unit(2, "Guards", Vector3(6.0 * INCH, 0, 0))
	foe.unit_properties["special_rules"] = ["Shielded"]
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_SHOOTING)) \
		.override_failure_message("Shielded still gives its +1 against a shot") \
		.is_equal(3)
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_SPELL)) \
		.override_failure_message("Shielded's own text is \"hits that are NOT from spells\" — it must not reach a spell's saves") \
		.is_equal(4)
	await _main._solo_resolve_spell_damage(caster, caster, "Fire Bolt", _damage_spell(), foe)
	var text := _log_text()
	assert_str(text).contains("Guards saves on 4+")
	assert_str(text) \
		.override_failure_message("rules-must-log: a bonus that silently fails to apply reads as a missing rule (log: %s)" % text.strip_edges()) \
		.contains("Shielded does not apply to spell damage")


# ===== (3) symmetry — a hex bites through a spell just like a blessing helps =====

func test_a_negative_defense_token_worsens_the_spell_save(timeout := 240000) -> void:
	var caster := _caster()
	var foe := _unit(2, "Grunts", Vector3(6.0 * INCH, 0, 0))
	_main._solo_place_spell_tokens("Withering Hex", [foe], {"kind": "debuff", "modifier": {"def_mod": -1}})
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_SPELL)) \
		.override_failure_message("NML-104 symmetry — a generic \"-1 to defense rolls\" bites against spell damage too") \
		.is_equal(5)
	await _main._solo_resolve_spell_damage(caster, caster, "Fire Bolt", _damage_spell(), foe)
	var text := _log_text()
	assert_str(text).contains("Grunts saves on 5+")
	assert_str(text).contains("-1 defense vs spell damage — Withering Hex")


# ===== (4) a token that scopes ITSELF to an attack keeps its own limit =====

func test_a_melee_scoped_token_stays_out_of_the_spell_save(timeout := 240000) -> void:
	var caster := _caster()
	var foe := _unit(2, "Grunts", Vector3(6.0 * INCH, 0, 0))
	_main._solo_place_spell_tokens("Shield Wall", [foe],
		{"kind": "buff", "modifier": {"def_mod": 1}, "scope": "melee"})
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_SPELL)) \
		.override_failure_message("a spell hit is neither a shot nor a melee attack — a melee-scoped token must not help") \
		.is_equal(4)
	await _main._solo_resolve_spell_damage(caster, caster, "Fire Bolt", _damage_spell(), foe)
	var text := _log_text()
	assert_str(text).contains("Grunts saves on 4+")
	assert_str(text) \
		.override_failure_message("rules-must-log: the token the player can see on the unit must say why it stays quiet (log: %s)" % text.strip_edges()) \
		.contains("Shield Wall does not apply to spell damage (its modifier is scoped to melee)")


# ===== (5) counter-check: the same token is unchanged on the shooting path =====

## The volley is rigged so a hit is all but certain: Quality 2+ with 8 attacks leaves a 6e-7 chance
## of an all-miss, so the save line the assertion reads is there.
func test_the_same_token_still_works_against_shooting(timeout := 240000) -> void:
	var shooter := _unit(1, "Tank", Vector3.ZERO, 1)
	shooter.unit_properties["quality"] = 2
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 8
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	shooter.source_type = "opr"
	shooter.source_data = opr
	var foe := _unit(2, "Grunts", Vector3(8.0 * INCH, 0, 0))
	_main._solo_place_spell_tokens("Warding Chant", [foe], {"kind": "buff", "modifier": {"def_mod": 1}})
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_SHOOTING)).is_equal(3)
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_MELEE)).is_equal(3)
	await _main._run_human_shooting(shooter, foe)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the token must keep working on the shooting path, untouched by NML-104 (log: %s)" % text.strip_edges()) \
		.contains("Grunts saves on 3+")
	assert_str(text) \
		.override_failure_message("a shot is not a spell — the spell-scope lines belong to the cast path only") \
		.not_contains("vs spell damage")
