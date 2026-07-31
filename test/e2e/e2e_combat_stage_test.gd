extends GdUnitTestSuite
## E2E — pacing grill 2026-07-31: the SOLO combat seams feed the combat stage. A forced
## stage (hold 0) rides a real human volley / melee / cast on main.tscn and must come out
## with that path's phase history. Plain e2e suites stay untouched because an unforced
## stage is inert headless — and a batch sweep is inert even when it is not.

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
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _armed(pid: int, unit_name: String, pos: Vector3, weapon_names: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wn in weapon_names:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(wn)
		w.range_value = 24
		w.attacks = 2
		ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A melee fixture: `models` bodies in a tight line at `pos` and ONE melee weapon (range 0 is
## what AiShooting.melee_profiles keys on). An empty `weapon` leaves the unit unable to fight —
## the "no melee weapons in reach" case the strike phase logs.
func _melee_unit(pid: int, unit_name: String, pos: Vector3, models: int,
		weapon: String, attacks: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(pos + Vector3(0.0, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	if not weapon.is_empty():
		var w := OPRApiClient.OPRWeapon.new()
		w.name = weapon
		w.range_value = 0
		w.attacks = attacks
		ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _phase_titles() -> Array:
	var titles: Array = []
	for ph in _main.combat_stage._phases:
		titles.append(str((ph as Dictionary)["title"]))
	return titles


## The rule lines of the first phase card called `title` ("" when no such card was cut).
func _card_text(title: String) -> String:
	for ph in _main.combat_stage._phases:
		var phd := ph as Dictionary
		if str(phd["title"]) != title:
			continue
		var text := ""
		for l in (phd["lines"] as Array):
			text += str(l) + "\n"
		return text
	return ""


## Everything the OTHER cards hold — what a missing phase boundary would bleed into.
func _text_outside(title: String) -> String:
	var text := ""
	for ph in _main.combat_stage._phases:
		var phd := ph as Dictionary
		if str(phd["title"]) == title:
			continue
		for l in (phd["lines"] as Array):
			text += str(l) + "\n"
	return text


func test_human_volley_walks_the_stage_phases(timeout := 240000) -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle"])
	var foe := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0), [])
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	await _main._run_human_shooting(shooter, foe)
	var titles: Array = []
	for ph in _main.combat_stage._phases:
		titles.append(str((ph as Dictionary)["title"]))
	assert_array(titles) \
		.override_failure_message("the volley must feed the stage (got: %s)" % str(titles)) \
		.contains(["Declaration", "Rifle"])
	# The declaration card carries the volley's rule lines from the COMBAT log stream.
	var decl := _main.combat_stage._phases[0] as Dictionary
	var decl_text := ""
	for l in (decl["lines"] as Array):
		decl_text += str(l) + "\n"
	assert_str(decl_text).contains("line of sight")
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads


func test_unforced_stage_stays_inert_for_plain_e2e() -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle"])
	var foe := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0), [])
	GraphicsSettings.combat_stage_hold_s = 2.5   # would stall for seconds per phase if active
	var t0 := Time.get_ticks_msec()
	await _main._run_human_shooting(shooter, foe)
	assert_array(_main.combat_stage._phases) \
		.override_failure_message("an unforced headless stage must not capture or hold") \
		.is_empty()
	assert_bool(Time.get_ticks_msec() - t0 < 60000).is_true()
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads


func test_a_full_miss_weapon_still_closes_its_phase_card() -> void:
	# CI find: the 0-hit `continue` skipped the phase boundary — the miss line bled into
	# the Result card and the weapon phase vanished. A guaranteed all-miss cannot exist
	# (a natural 6 always hits), so: 1 attack at the worst quality exercises the 0-hit
	# path in 5/6 of runs, and the DETERMINISTIC claim is two-fold — the weapon card
	# always closes, and the fires-line never lands in the Result card.
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle"])
	shooter.unit_properties["quality"] = 7   # clamps to 6+ — only a natural 6 hits
	(shooter.source_data.weapons[0] as OPRApiClient.OPRWeapon).attacks = 1
	var foe := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0), [])
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	await _main._run_human_shooting(shooter, foe)
	var titles: Array = []
	for ph in _main.combat_stage._phases:
		titles.append(str((ph as Dictionary)["title"]))
	assert_array(titles) \
		.override_failure_message("the weapon card must close on hit AND on full miss (got: %s)" % str(titles)) \
		.contains(["Rifle"])
	for ph in _main.combat_stage._phases:
		var phd := ph as Dictionary
		if str(phd["title"]) != "Rifle":
			var text := ""
			for l in (phd["lines"] as Array):
				text += str(l) + "\n"
			assert_str(text) \
				.override_failure_message("the fires-line bled out of its weapon card into '%s'" % str(phd["title"])) \
				.not_contains("fires Rifle")
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads


# === Stage 2 — the melee exchange and the cast procedure ride the same stage ===

## Why batch mode: it is the harness lever for the two things a headless melee cannot do —
## the physics dice tray (batch draws fair faces instantly) and the consolidation board prompt
## (batch answers it, nobody can click). The stage is forced ON TOP: CombatStage.active() lets
## force_for_tests win over batch by design, which is exactly what makes this testable.
## The melee is rigged so its outcome is DETERMINISTIC, not likely: the defender has no melee
## weapon (it can never deal a wound) and the charger has Fear(1) (+1 on the who-won tally),
## so the defender always loses the comparison, and 2 attacks can never kill 3 models, so it
## always survives to test morale.
func test_human_charge_walks_the_melee_stage_phases(timeout := 240000) -> void:
	_main._solo_batch = true
	var charger := _melee_unit(1, "Tank", Vector3.ZERO, 1, "Chainblade", 2)
	charger.unit_properties["special_rules"] = ["Fear(1)"]
	var foe := _melee_unit(2, "Foe", Vector3(1.0 * INCH, 0, 0), 3, "", 0)
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	await _main._run_human_melee(charger, foe)
	var titles := _phase_titles()
	assert_array(titles) \
		.override_failure_message("the melee must walk the stage (got: %s)" % str(titles)) \
		.contains(["Charge", "Tank strikes", "Foe strikes back", "Melee result", "Morale"])
	assert_str(_card_text("Charge")).contains("Tank charges Foe")
	# The strike-back card exists BECAUSE its boundary sits outside the branch: the defender has
	# no melee weapon, so the whole wave is the one rule line saying so.
	assert_str(_card_text("Foe strikes back")).contains("no melee weapons in reach")
	# Fear(1) against a defender that cannot deal a wound: the verdict is fixed, and the tally
	# names the Fear-adjusted value.
	assert_str(_card_text("Melee result")).contains("Foe loses the melee")
	assert_str(_card_text("Melee result")).contains("Fear: ")
	assert_str(_text_outside("Melee result")) \
		.override_failure_message("the melee verdict bled out of its own card") \
		.not_contains("Melee result:")
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads


func test_a_cast_walks_the_stage_phases(timeout := 240000) -> void:
	_main._solo_batch = true
	var caster := _armed(1, "Mystic", Vector3.ZERO, [])
	var ally := _armed(1, "Ward", Vector3(2.0 * INCH, 0, 0), [])
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	var cast := {"caster": caster, "caster_unit": caster,
		"spell": {"effect": {"kind": "buff", "grants_rule": "Fearless"}},
		"name": "Warding Chant", "targets": [ally], "boost": 0, "interference": 0,
		"base_target": 2, "threshold": 1, "owner_label": "You", "human_cast": true}
	# A natural 1 always fails (DiceRules), so no cast is certain — repeat until one succeeds.
	# Each cast is its own activation, so the assertions read the SUCCESSFUL one's history;
	# 8 tries at 2+ leaves a 6e-7 chance of never getting there.
	var tries := 0
	while tries < 8:
		await _main._solo_resolve_one_cast(cast)
		tries += 1
		if _card_text("Cast roll").contains("SUCCESS"):
			break
	var titles := _phase_titles()
	assert_array(titles) \
		.override_failure_message("the cast must walk the stage (got: %s)" % str(titles)) \
		.contains(["Cast", "Cast roll", "Effect"])
	assert_str(_card_text("Cast")).contains("Mystic casts Warding Chant at Ward")
	assert_str(_card_text("Cast roll")).contains("cast roll")
	assert_str(_card_text("Effect")).contains("Warding Chant takes effect on Ward")
	# The effect must live in the Effect card — a missing boundary would drop it into the roll card.
	assert_str(_text_outside("Effect")) \
		.override_failure_message("the effect line bled out of the Effect card") \
		.not_contains("takes effect on")
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads


## The early-exit lesson from the 0-hit weapon, on the cast path: a spell whose targets are all
## gone returns before any die — and must still close its card, or the fizzle line bleeds into
## whatever activation comes next. No dice involved, so this one is exact.
func test_a_fizzled_cast_still_closes_its_card(timeout := 240000) -> void:
	_main._solo_batch = true
	var caster := _armed(1, "Mystic", Vector3.ZERO, [])
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	await _main._solo_resolve_one_cast({"caster": caster, "caster_unit": caster,
		"spell": {"effect": {"kind": "buff"}}, "name": "Warding Chant", "targets": [],
		"base_target": 2, "threshold": 1, "owner_label": "You"})
	assert_array(_phase_titles()) \
		.override_failure_message("the fizzle must close its own card") \
		.contains(["Cast"])
	assert_str(_card_text("Cast")).contains("fizzles")
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads


## Inertness counter-check for the melee seam: a selfplay sweep sets batch and never forces the
## stage, so nothing is captured and nothing holds (the headless-without-force half is covered
## by the volley test above).
func test_a_batch_melee_never_pays_for_the_stage(timeout := 240000) -> void:
	_main._solo_batch = true
	var charger := _melee_unit(1, "Tank", Vector3.ZERO, 1, "Chainblade", 2)
	var foe := _melee_unit(2, "Foe", Vector3(1.0 * INCH, 0, 0), 3, "", 0)
	GraphicsSettings.combat_stage_hold_s = 2.5   # would stall per phase if the stage were live
	await _main._run_human_melee(charger, foe)
	assert_array(_main.combat_stage._phases) \
		.override_failure_message("a batch sweep must never capture or hold") \
		.is_empty()
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads
