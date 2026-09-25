extends GdUnitTestSuite
## E2E — NML-939: the Utility-Buff giver family works in a PLAIN human-vs-human room.
##
## THE GAP. _solo_apply_utility_buffs opened with `solo_controller == null -> return`, and a plain
## human-vs-human multiplayer room never has a solo_controller: _ensure_solo_controller refuses to build
## one without a designated AI slot (#196 — its existence alone arms NACHTMAHR's alternation pump). So
## every buff GIVER (Precision Shooter Buff, Furious Buff, the enemy-side Debuffs, ...) was dead data
## there, while the same rules worked in solo and in a room with an AI-held slot (e2e_mp_utility_buffs_test).
##
## THE FIX UNDER TEST. The resolver and its target pick no longer need the controller: geometry comes
## from the same null-safe helper the LOS line uses (_los_unit_centre), the enemy side is "every other
## player's army", and the controller stays null (no NACHTMAHR is summoned). The human's v1 target pick is
## the automatic value proxy, exactly as in solo. Both doors open: declaring an attack, and completing an
## activation that never attacks.
##
## THE FIXTURE. A plain MP room: solo_ai_slots empty, NO solo controller, a live FakeNet session.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


## Stand-in for NetworkManager at main's seam: a live session that records every outbound frame.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func broadcast_unit_property(gu: GameUnit, key: String, value: Variant) -> void:
		sent.append({"kind": "property", "unit": gu.unit_id, "key": key, "value": value})
	func broadcast_spell_mods(gu: GameUnit, records: Array) -> void:
		sent.append({"kind": "mods", "unit": gu.unit_id, "records": records})


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	# PLAIN MP room: no AI slot, no controller, a live session. Deliberately NOT _ensure_solo_controller().
	_main.solo_ai_slots = {}
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


func _at(inches_x: float) -> Vector3:
	return Vector3(inches_x * INCH, 0.0, 0.0)


## A three-model line: the value proxy picks the BIGGEST unit, so a receiver has to out-value the
## one-model Hero that is buffing.
func _line(inches_x: float) -> Array:
	return [_at(inches_x), _at(inches_x + 1.2), _at(inches_x + 2.4)]


## Register a fixture unit and stamp the book that actually FIELDS these rules — the registry gate is
## system-scoped, so an unstamped unit resolves no primitive at all.
func _reg(pid: int, unit_name: String, positions: Array, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "human_defense_force"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _mods_on(u: GameUnit) -> Array:
	return _main._solo_spell_mods.get(u.get_instance_id(), [])


func _mod_frames(u: GameUnit) -> Array:
	var out: Array = []
	for e in _fake.sent:
		var d := e as Dictionary
		if str(d["kind"]) == "mods" and str(d["unit"]) == u.unit_id:
			out.append(d)
	return out


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A human Hero with a shooting buff and a friend worth buffing (both player 1).
func _giver_and_friend() -> Array:
	var giver := _reg(1, "Field Commander", [_at(0.0)], ["Hero", "Precision Shooter Buff"])
	var friend := _reg(1, "Riflemen", _line(6.0), [])
	return [giver, friend]


func _assert_still_no_controller() -> void:
	assert_object(_main.solo_controller) \
		.override_failure_message("#196: a plain human-vs-human room must never get a solo controller (it would summon NACHTMAHR)") \
		.is_null()
	assert_bool(_main._solo_alternation_active()).is_false()


# === 1. The resolver ==============================================================================

## THE CLAIM: a human buff giver resolves in a plain room, and the record rides the wire so the
## opponent's client holds the same modifier.
func test_a_friendly_buff_lands_in_a_plain_human_room(timeout := 120000) -> void:
	var gf := _giver_and_friend()
	assert_object(_main.solo_controller).override_failure_message("fixture: the room must have no controller").is_null()

	_main._solo_apply_utility_buffs(gf[0])

	assert_int(_mods_on(gf[1]).size()) \
		.override_failure_message("the buff giver does nothing in a plain human-vs-human room (no solo controller)") \
		.is_equal(1)
	var rec: Dictionary = (_mods_on(gf[1])[0] as Dictionary) if not _mods_on(gf[1]).is_empty() else {}
	assert_int(int(rec.get("hit_mod", 0))).is_equal(1)
	assert_str(str(rec.get("scope", ""))).is_equal("shooting")
	assert_int(_mod_frames(gf[1]).size()) \
		.override_failure_message("the record never left this client (sent: %s)" % str(_fake.sent)) \
		.is_greater_equal(1)
	assert_str(_log_text()).contains("Precision Shooter Buff: Field Commander → Riflemen")
	_assert_still_no_controller()


## A friend that is out of the printed 12" pick range gets nothing while the one in range does — the
## range gate still binds without the controller's geometry.
func test_the_pick_range_still_binds(timeout := 120000) -> void:
	var giver := _reg(1, "Field Commander", [_at(0.0)], ["Hero", "Precision Shooter Buff"])
	var near := _reg(1, "Scouts", _line(6.0), [])
	var far := _reg(1, "Riflemen", _line(30.0), [])

	_main._solo_apply_utility_buffs(giver)

	assert_int(_mods_on(near).size()).override_failure_message("fixture: the unit in range must be the pick").is_equal(1)
	assert_int(_mods_on(far).size()).override_failure_message("a unit 30\" away was buffed").is_equal(0)


## Enemy-side buffs/debuffs pick from the OTHER player's army — there is no controller to say which
## slot that is.
func test_an_enemy_debuff_lands_on_the_other_players_unit(timeout := 120000) -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {"human_defense_force": {
		"Precision Debuff": {"primitive": "Utility Buff", "rated": false, "book_version": "3.5.3",
			"params": {"hit_mod": -1, "range_in": 18, "target": "enemy", "once": true, "needs_los": true}},
	}}, "common": {}}
	var giver := _reg(1, "Plague Magus", [_at(0.0)], ["Precision Debuff"])
	var own := _reg(1, "Riflemen", _line(6.0), [])
	var foe := _reg(2, "Stormwind", _line(12.0), [])

	_main._solo_apply_utility_buffs(giver)

	assert_int(_mods_on(foe).size()) \
		.override_failure_message("the debuff never landed on the enemy player's unit (records: %s)" % str(_mods_on(foe))) \
		.is_equal(1)
	assert_int(_mods_on(own).size()).override_failure_message("the debuff landed on the giver's OWN side").is_equal(0)
	var rec: Dictionary = (_mods_on(foe)[0] as Dictionary) if not _mods_on(foe).is_empty() else {}
	assert_int(int(rec.get("hit_mod", 0))).is_equal(-1)
	assert_int(_mod_frames(foe).size()).is_greater_equal(1)
	_assert_still_no_controller()


## Re-Position Artillery moves a model — the players do that by hand at a table, and the automation's
## own mover is the AI planner's. So the rule announces itself instead of silently doing nothing.
func test_reposition_artillery_names_itself_and_moves_nothing(timeout := 120000) -> void:
	var giver := _reg(1, "Gun Captain", [_at(0.0)], ["Hero", "Re-Position Artillery"])
	giver.unit_properties["faction_folder"] = "battle_brothers"   # a book that fields Re-Position Artillery
	var gun := _reg(1, "Field Gun", [_at(4.0)], ["Artillery"])
	var before: Vector3 = _main._los_unit_centre(gun)

	_main._solo_apply_utility_buffs(giver)

	assert_str(_log_text()).contains("Re-Position Artillery: Gun Captain")
	assert_vector(_main._los_unit_centre(gun)).override_failure_message("the gun was moved by an automation that does not exist here").is_equal(before)
	_assert_still_no_controller()


# === 2. The two doors =============================================================================

## Door one: declaring an attack ("once per activation, BEFORE attacking").
func test_declaring_an_attack_buys_the_buff_in_a_plain_room(timeout := 120000) -> void:
	var gf := _giver_and_friend()

	await _main.solo_begin_targeting(gf[0], false)

	assert_int(_mods_on(gf[1]).size()) \
		.override_failure_message("declaring an attack did not resolve the Utility Buff in a plain human-vs-human room") \
		.is_equal(1)
	_assert_still_no_controller()


## Door two: a unit that never attacks still gets its buff when its activation is completed.
func test_a_unit_that_never_attacks_buys_the_buff_at_activation(timeout := 120000) -> void:
	var gf := _giver_and_friend()

	await _main._on_solo_human_activated(gf[0])

	assert_int(_mods_on(gf[1]).size()) \
		.override_failure_message("completing an activation did not resolve the Utility Buff in a plain human-vs-human room") \
		.is_equal(1)
	_assert_still_no_controller()


## "Once per activation": both doors in a row buy it once, and the second door sends nothing.
func test_both_doors_buy_it_once(timeout := 120000) -> void:
	var gf := _giver_and_friend()

	await _main.solo_begin_targeting(gf[0], false)
	_fake.sent.clear()
	await _main._on_solo_human_activated(gf[0])

	assert_int(_mods_on(gf[1]).size()).override_failure_message("two doors, one application").is_equal(1)
	assert_int(_mod_frames(gf[1]).size()).override_failure_message("the second door put a duplicate record on the wire").is_equal(0)


# === 3. Counter-proof =============================================================================

## Nothing of this touches a room that HAS an AI seat: the controller is built there as before and the
## buff still lands through it (the e2e_mp_utility_buffs_test fixture, one assertion).
func test_a_room_with_an_ai_slot_still_buffs_through_its_controller(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).override_failure_message("fixture: an AI-slot room builds its controller").is_not_null()
	var gf := _giver_and_friend()

	_main._solo_apply_utility_buffs(gf[0])

	assert_int(_mods_on(gf[1]).size()).is_equal(1)
