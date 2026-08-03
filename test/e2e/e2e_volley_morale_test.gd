extends GdUnitTestSuite
## E2E — NML-966: after CLICKED wound allocation the 50%-strength morale test is silently skipped.
##
## THE SEAM. `_solo_resolve_ai_volley` captures `alive_before = target.get_alive_count()` (main.gd:2892)
## and, if anything landed, calls `_solo_shooting_morale(target, alive_before, …)` (main.gd:3081). That
## hook's multi-model trigger is `AiCombatMath.should_test_shooting_morale(alive_before, alive_now,
## unit.models.size())` — three numbers that all count the unit's OWN models. The OUTCOME predicate one
## screen further down, `_solo_below_half_strength` (main.gd:8019-8023), counts the COMBINED chain:
## SoloController.combined_alive / combined_total, unit + attached heroes (NML-008 fixed that half, the
## trigger was left behind).
##
## THE GAP. The #172 click allocation accepts any model of the JOINED CHAIN (the router's
## `chain.has(mi.unit)`, main.gd:8639), so the owner may put the wounds on the attached hero. The hero
## dies, the chain is at half strength or less — and no OWN model died, so the trigger reads "no
## casualties" and rolls no morale test at all. Half the rule counts the hero, half of it does not.
##
## WHY THIS SUITE DRIVES THE WHOLE VOLLEY. The defect lives BETWEEN the alive_before capture and the
## morale hook; a test that captured the counts itself and called `_solo_shooting_morale` directly
## would be re-implementing the very line under suspicion. So both cases drive the REAL
## `_solo_resolve_ai_volley` over the REAL scenes/main.tscn: real shots, real tray faces, the real save
## prompt, the real wound landing, the real allocation prompt, the real morale hook.
##
## WHAT IS REAL vs CONSTRUCTED. Real: main.tscn with its real _ready(), the real OPRArmyManager, the
## real SoloController, the real AiShooting weapon profile, the real dice tray (batch faces), the real
## battle log. Constructed: the GameUnits and their model nodes, the shot list (the shape
## `_run_ai_shooting` builds at main.gd:2831-2833), and the synthetic wound picks — the click raycast
## itself is already covered by e2e_wound_allocation_test / e2e_reanimation_click_allocation_test.
##
## NO ASSERTION SITS BEHIND A DIE. `_solo_batch = true` draws tray faces from the GLOBAL RNG instead of
## awaiting the physics tray, so `seed(VOLLEY_SEED)` pins every die of a run. On top of that each case
## is built with room to spare (the control needs 2-3 of 3 possible wounds, the red case needs 3 of 6),
## and asserts the state it needed as a NAMED fixture precondition before it asserts the claim — a
## drifting seed therefore fails as "the fixture did not land N wounds", never as a silent pass.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Seeds the global RNG the batch tray draws from — one run, one fixed set of faces.
const VOLLEY_SEED := 20250803

## Own seed for the gap-B (Deadly-only) case: VOLLEY_SEED's faces are tuned for a 3-die pooled save
## roll, not the 6-die Deadly-weapon volley below — a separate constant keeps each case's dice fixed
## without coupling their outcomes.
const DEADLY_SEED := 20250803001

## Rolls of `_solo_resolve_ai_volley` that happen BEFORE the wound landing: the to-hit batch and the
## defender's save batch. The click prompt needs `_solo_batch` false, the batch tray needs it true — so
## the red case drops the flag on this roll and the pump puts it back with the first pick.
const ROLLS_BEFORE_WOUNDS := 2

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array

var _pump: Timer = null        # harness pump: answers the save dialog and feeds the wound picks
var _rolls := 0                # roll_finnished emissions seen so far
var _flip_batch_on := 0        # >0: drop _solo_batch when _rolls reaches this
var _pick_hero: GameUnit = null   # while alive, every clicked wound goes HERE (the defect's setup)
var _pick_rest: GameUnit = null   # the leftovers once the hero is down
var _picks_fed := 0
var _prompt_ticks := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	# Batch dice: _solo_tray_roll draws faces from the RNG instead of awaiting the physics tray,
	# which headless would never settle.
	_main._solo_batch = true
	_rolls = 0
	_flip_batch_on = 0
	_pick_hero = null
	_pick_rest = null
	_picks_fed = 0
	_prompt_ticks = 0
	_main.dice_roller_control.roll_finnished.connect(_on_roll_finished)
	_arm_pump()


func after_test() -> void:
	if _pump != null and is_instance_valid(_pump):
		_pump.stop()
	_pump = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === harness pump =============================================================================

## The volley awaits two things no headless run can click: the human's save confirmation
## (`_solo_prompt_saves` puts up a ConfirmationDialog and spins frames until it answers) and the #172
## wound-allocation prompt (`_solo_prompt_wound_allocation` spins frames until a model is picked). One
## repeating timer answers both — it ticks on the same tree the awaited coroutine yields to.
func _arm_pump() -> void:
	_pump = Timer.new()
	_pump.name = "NML966Pump"
	_pump.wait_time = 0.02
	_pump.one_shot = false
	get_tree().root.add_child(_pump)   # freed by free_stray_root_nodes in after_test
	_pump.timeout.connect(_on_pump)
	_pump.start()


func _on_pump() -> void:
	if _main == null or not is_instance_valid(_main):
		return
	_answer_save_prompt()
	var prompt: Dictionary = _main._solo_model_pick
	if prompt.is_empty() or _pick_hero == null:
		return
	var outcome: Array = prompt["outcome"]
	_prompt_ticks += 1
	if _prompt_ticks > 250:
		# Deadlock guard: neither model can take the pick any more. Hand the rest to the auto path
		# (RMB = an empty recommended pick) so the case fails on an assertion, never by hanging.
		outcome.append({})
		return
	if not outcome.is_empty():
		return   # the previous click has not been applied yet — one wound at a time
	# ONE wound per click, onto the hero for as long as he stands. Feeding them one at a time (and
	# only after the last one landed) is what makes "the first three killed the hero" true by
	# construction instead of by dice count.
	var on: GameUnit = _pick_hero if _pick_hero.get_alive_count() > 0 else _pick_rest
	outcome.append({"unit": on, "index": 0})
	_picks_fed += 1
	if _picks_fed == 1:
		# The click gate (_solo_wound_choice_matters) is behind us; the morale die that follows the
		# landing needs the batch tray again, and the pacing holds must stay inert.
		_main._solo_batch = true


## The AI volley makes the HUMAN roll their own saves — press OK for the absent player.
func _answer_save_prompt() -> void:
	for c in _main.get_children():
		var dlg := c as AcceptDialog
		if dlg != null and dlg.title == "Incoming fire!":
			dlg.confirmed.emit()


func _on_roll_finished(_total: int) -> void:
	_rolls += 1
	if _flip_batch_on > 0 and _rolls == _flip_batch_on:
		# Emitted from INSIDE show_faces(), i.e. after this roll's faces are already drawn — the flag
		# only reaches the wound landing that follows.
		_main._solo_batch = false


# === fixture helpers ==========================================================================

## A registered unit with `positions.size()` live models. Quality and Defense are the two numbers the
## volley's arithmetic reads.
func _unit(pid: int, unit_name: String, positions: Array, quality: int = 4, defense: int = 4) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	for i in range(u.models.size()):
		(u.models[i] as ModelInstance).model_index = i
	u.unit_properties["quality"] = quality
	u.unit_properties["defense"] = defense
	u.unit_properties["special_rules"] = []
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Tough(X) on a unit's single model.
func _make_tough(u: GameUnit, wounds: int) -> GameUnit:
	var m := u.models[0] as ModelInstance
	m.wounds_max = wounds
	m.wounds_current = wounds
	var rules: Array = u.unit_properties.get("special_rules", [])
	rules.append("Tough(%d)" % wounds)
	u.unit_properties["special_rules"] = rules
	return u


## A joined hero — the attached_to / attached_heroes wiring the whole chain seam reads (mirrors
## _joined_hero in e2e_unread_params_test.gd:88-96).
func _joined_hero(host: GameUnit, hero_name: String, at: Vector3, tough: int) -> GameUnit:
	var h := _unit(int(host.unit_properties.get("player_id", 1)), hero_name, [at])
	h.unit_properties["special_rules"] = ["Hero"]
	_make_tough(h, tough)
	h.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [h]
	return h


## ONE shot in the shape `_run_ai_shooting` builds (main.gd:2831-2833), with a REAL AiShooting profile
## parsed from a real OPRWeapon — so the volley reads production's own weapon dictionary. AP(5) against
## Defense 4 leaves the defender saving on "6 only", which is as close to a fixed outcome as the OPR
## dice allow (DiceRules: an unmodified 6 always saves, an unmodified 1 always misses).
func _shots(attacker: GameUnit, weapon_name: String, attacks: int, ap: int, range_in: int, extra_rules: Array = []) -> Array:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	var rules: Array[String] = ["AP(%d)" % ap]
	for r in extra_rules:
		rules.append(str(r))
	w.special_rules = rules
	var profiles: Array = AiShooting.profiles_in_range([w], 0.0)
	assert_int(profiles.size()) \
		.override_failure_message("fixture: the weapon must parse into exactly one firing profile") \
		.is_equal(1)
	return [{"member": attacker, "quality": attacker.get_quality(),
		"alive": attacker.get_alive_count(), "max": attacker.models.size(),
		"reach": range_in, "profile": profiles[0]}]


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## Every battle-log line that reports a morale test outcome — the observable of `_solo_morale_test`
## (main.gd:8098-8110): "… passes morale", "… fails morale — Shaken", "… fails morale at half strength
## — ROUTS". Exactly one of the three exists per test rolled, whatever the die says, so the assertion
## reads the RULE and not the dice. (The `is_shaken` flag would only show a FAILED test.)
func _morale_lines() -> Array:
	var out: Array = []
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.contains("passes morale") or t.contains("fails morale"):
			out.append(t)
	return out


# === 1. CONTROL — automatic allocation still tests morale at half strength ====================

## The trigger works when the wounds land on the unit's OWN models: a 4-model squad with no attached
## hero, a uniform non-Tough loadout (so `_solo_wound_choice_matters` stays false and the allocation
## is automatic), shot down to half strength or less by a real AI volley. This is the case NML-966
## does NOT break — it is here so the red case below cannot pass by the volley simply doing nothing.
func test_auto_allocation_volley_triggers_half_strength_morale(timeout := 120000) -> void:
	var ai := _unit(2, "Sturmtrupp", [Vector3.ZERO], 2)
	var squad := _unit(1, "Wachtrupp", [Vector3(0.15, 0.0, -0.03), Vector3(0.15, 0.0, 0.0),
		Vector3(0.15, 0.0, 0.03), Vector3(0.15, 0.0, 0.06)])
	# The click gate must be structurally shut: no Tough model, one shared (empty) loadout. Measured
	# with the batch flag DOWN, because batch alone would answer "false" for the wrong reason.
	_main._solo_batch = false
	assert_bool(_main._solo_wound_choice_matters(squad, 2)) \
		.override_failure_message("fixture: a uniform non-Tough squad must allocate automatically") \
		.is_false()
	_main._solo_batch = true

	seed(VOLLEY_SEED)
	await _main._solo_resolve_ai_volley(ai, squad, _shots(ai, "Autogun", 3, 5, 24), false)

	var alive: int = squad.get_alive_count()
	assert_int(alive) \
		.override_failure_message("fixture: the volley had to leave 1-2 of 4 models alive (half or less, not wiped) — it left %d\n%s" % [alive, _log_text()]) \
		.is_between(1, 2)
	assert_bool(_main._solo_below_half_strength(squad)) \
		.override_failure_message("fixture: %d of 4 models must read as half strength or less" % alive) \
		.is_true()
	assert_array(_morale_lines()) \
		.override_failure_message("the squad dropped to %d of 4 models and no morale test was rolled:\n%s" % [alive, _log_text()]) \
		.is_not_empty()
	await E2EBoot.settle(get_tree())


# === 2. RED (NML-966) — the same drop, clicked onto the attached hero, tests nothing ==========

## The defect. A Tough(9) trooper with a joined Tough(3) hero is a TWO-model unit (GF/AoF v3.5.1 p.14:
## a joined unit measures its strength over unit + hero together). A real AI volley lands its wounds,
## the owner clicks the first three onto the HERO — he dies — and the leftovers onto the trooper, who
## is Tough enough to soak them. The chain now stands at 1 of 2 models, half strength or less, while
## the squad's own model count never moved: 1 alive before, 1 alive after.
##
## EXPECTED AT HEAD: every fixture assertion passes (the hero is dead, no own model died, the chain IS
## below half) and the morale assertion FAILS — `should_test_shooting_morale` saw "no casualties".
func test_hero_click_allocation_volley_triggers_half_strength_morale(timeout := 120000) -> void:
	var ai := _unit(2, "Sturmtrupp", [Vector3.ZERO], 2)
	var squad := _make_tough(_unit(1, "Wachtrupp", [Vector3(0.15, 0.0, 0.0)]), 9)
	var hero := _joined_hero(squad, "Klauenherr", Vector3(0.20, 0.0, 0.10), 3)
	assert_int(SoloController.combined_total(squad)) \
		.override_failure_message("fixture: the joined chain must count 2 models (trooper + hero)") \
		.is_equal(2)
	_main._solo_batch = false
	assert_bool(_main._solo_wound_choice_matters(squad, 3)) \
		.override_failure_message("fixture: the Tough models in the chain must open the click prompt") \
		.is_true()
	_main._solo_batch = true

	_pick_hero = hero            # every wound goes onto the hero while he stands …
	_pick_rest = squad           # … the rest onto the Tough trooper, who survives them
	_flip_batch_on = ROLLS_BEFORE_WOUNDS

	seed(VOLLEY_SEED)
	await _main._solo_resolve_ai_volley(ai, squad, _shots(ai, "Autogun", 6, 5, 24), false)

	assert_int(_picks_fed) \
		.override_failure_message("fixture: the wound-allocation prompt never opened — nothing was clicked\n%s" % _log_text()) \
		.is_greater_equal(3)
	assert_int(hero.get_alive_count()) \
		.override_failure_message("fixture: the first three clicked wounds had to kill the Tough(3) hero\n%s" % _log_text()) \
		.is_equal(0)
	assert_int(squad.get_alive_count()) \
		.override_failure_message("fixture: no OWN model may die — the trigger's own inputs must not move\n%s" % _log_text()) \
		.is_equal(1)
	assert_bool(_main._solo_below_half_strength(squad)) \
		.override_failure_message("fixture: 1 of 2 combined models must read as half strength or less") \
		.is_true()

	assert_array(_morale_lines()) \
		.override_failure_message("NML-966 — the joined unit stands at 1 of 2 models (half strength or less) after the volley, but NO morale test was rolled: the shooting trigger counts the squad's OWN models (1 before, 1 after = \"no casualties\") while the outcome predicate counts the combined chain. Every wound the owner clicked onto the hero is invisible to the trigger.\n%s" % _log_text()) \
		.is_not_empty()
	await E2EBoot.settle(get_tree())


# === 3. RED (NML-966 gap B) — a Deadly-only kill never reaches `landed`, morale never rolls =====

## THE SECOND GAP. `_solo_resolve_ai_volley` pools every shot's unsaved wounds into two counters,
## `regenable`/`regen_proof`, and ONLY those two feed `landed` (main.gd:3068, `_solo_land_wounds`).
## Deadly and Takedown wounds never touch either counter — main.gd:3057-3062 routes them straight to
## `_solo_land_deadly_wounds` / `_solo_land_takedown_wounds`, which apply the casualties directly and
## return their own dealt-count to nobody (the `await` at those call sites is not even assigned). So a
## volley whose ONLY weapon is Deadly reaches the morale gate with `landed == 0`, whatever it killed —
## `if landed > 0` (main.gd:3080) skips `_solo_shooting_morale` outright, before `alive_before`/
## `alive_now` are ever compared.
##
## FIXTURE PROOF (not re-implementing the gate): the shot list carries a SINGLE Deadly(3) weapon, so
## `regenable`/`regen_proof` can only ever be 0 for this volley — the fixture asserts that directly off
## the battle log: a "Deadly(3): … dealt" line (the deadly path fired) and the ABSENCE of the
## `on_wounds` line `_solo_apply_wounds` prints ("%s takes N wound(s) (a/b)", battle_log.gd:198-199),
## which only fires when `_solo_land_wounds` sees `landed > 0` (main.gd:6398-6402). No own-model death
## can slip through any other channel because no other weapon is in this shot's list.
##
## EXPECTED AT HEAD: every fixture assertion passes (deadly casualties took the squad to half strength
## or less, the normal pool never fired) and the morale assertion FAILS — the gate at main.gd:3080
## never called `_solo_shooting_morale` at all.
func test_deadly_only_volley_triggers_half_strength_morale(timeout := 120000) -> void:
	var ai := _unit(2, "Sturmtrupp", [Vector3.ZERO], 2)
	var squad := _unit(1, "Wachtrupp", [Vector3(0.15, 0.0, -0.03), Vector3(0.15, 0.0, 0.0),
		Vector3(0.15, 0.0, 0.03), Vector3(0.15, 0.0, 0.06)])
	# Same click-gate precondition as the control case: no Tough model, one shared (empty) loadout —
	# structurally automatic allocation, so a clicked pick can never confound this fixture either.
	_main._solo_batch = false
	assert_bool(_main._solo_wound_choice_matters(squad, 2)) \
		.override_failure_message("fixture: a uniform non-Tough squad must allocate automatically") \
		.is_false()
	_main._solo_batch = true

	seed(DEADLY_SEED)
	await _main._solo_resolve_ai_volley(ai, squad, _shots(ai, "Deadlygun", 5, 5, 24, ["Deadly(3)"]), false)

	var log := _log_text()
	var alive: int = squad.get_alive_count()
	assert_int(alive) \
		.override_failure_message("fixture: the volley had to leave 1-2 of 4 models alive (half or less, not wiped) through Deadly(3) alone — it left %d\n%s" % [alive, log]) \
		.is_between(1, 2)
	assert_bool(_main._solo_below_half_strength(squad)) \
		.override_failure_message("fixture: %d of 4 models must read as half strength or less" % alive) \
		.is_true()
	assert_bool(log.contains("Deadly(3)")) \
		.override_failure_message("fixture: the casualties must be provably Deadly — no \"Deadly(3)\" log line was found\n%s" % log) \
		.is_true()
	assert_bool(log.contains("%s takes" % squad.get_name())) \
		.override_failure_message("fixture: the normal `landed` pool must stay at 0 — a \"%s takes N wound(s)\" line means _solo_land_wounds saw landed > 0, which defeats this fixture\n%s" % [squad.get_name(), log]) \
		.is_false()

	assert_array(_morale_lines()) \
		.override_failure_message("NML-966 (gap B) — the squad dropped to %d of 4 models (half strength or less) through Deadly(3) alone, but NO morale test was rolled: `landed` only pools the non-Deadly/Takedown wounds (main.gd:3068), so a volley whose casualties are entirely Deadly never satisfies the `if landed > 0` gate (main.gd:3080).\n%s" % [alive, log]) \
		.is_not_empty()
	await E2EBoot.settle(get_tree())
