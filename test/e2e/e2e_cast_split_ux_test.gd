extends GdUnitTestSuite
## E2E — maintainer UX wave (31.07.): (1) spell markers live and die by the SPELL's own text —
## "next time" tokens survive the round-end sweep until consumed, round-scoped ones expire with
## a named line; (2) cast picks wear rings and a re-click takes the pick back; (3) split fire is
## DECLARED visually (rings + firing vectors) and only the explicit Fire! button rolls dice.

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


# ===== (1) token duration follows the spell text =====

func test_next_time_token_survives_round_end_and_round_token_expires_named() -> void:
	var u := E2EBoot.make_unit(_main, 1, "Grunts", [Vector3.ZERO])
	_main._solo_place_spell_tokens("Once Buff", [u],
		{"grants_rule": "Shred", "once": true, "duration": "once"})
	_main._solo_place_spell_tokens("Round Buff", [u],
		{"grants_rule": "Poison", "once": false, "duration": "round"})
	var text := _log_text()
	assert_str(text).contains("\"Once Buff\" token placed on Grunts (persists until it applies)")
	assert_str(text).contains("\"Round Buff\" token placed on Grunts (expires at the end of the round)")
	_main._solo_expire_spell_tokens()
	text = _log_text()
	assert_str(text) \
		.override_failure_message("round-scoped token must expire with a NAMED line (log: %s)" % text.strip_edges()) \
		.contains("\"Round Buff\" on Grunts expires with the round — it was never consumed")
	assert_str(text).not_contains("\"Once Buff\" on Grunts expires with the round")
	var still: Array = []
	for e in _main._solo_spell_tokens_active:
		still.append(str((e as Dictionary).get("token")))
	assert_array(still) \
		.override_failure_message("the next-time token must SURVIVE the round-end sweep") \
		.contains(["Once Buff"])
	assert_array(still).not_contains(["Round Buff"])


# ===== (2) cast picks: ring on, re-click takes it back =====

func test_cast_pick_ring_and_reclick_unpick() -> void:
	var caster := E2EBoot.make_unit(_main, 1, "Mage", [Vector3.ZERO])
	var a := E2EBoot.make_unit(_main, 1, "AllyA", [Vector3(6.0 * INCH, 0, 0)])
	var b := E2EBoot.make_unit(_main, 1, "AllyB", [Vector3(0, 0, 6.0 * INCH)])
	_main._solo_target_mode = {"unit": caster, "cast_member": caster,
		"cast_entry": {"name": "Twin Blessing", "target": {"count": 2, "side": "friendly"}},
		"cast_valid": [a, b], "cast_rings": []}
	_main._solo_cast_click(a)
	assert_array(_main._solo_target_mode.get("cast_picked", []) as Array).contains([a])
	var rings: Dictionary = _main._solo_target_mode.get("cast_pick_rings", {})
	assert_int(rings.size()) \
		.override_failure_message("a picked cast target must wear its own ring") \
		.is_equal(1)
	_main._solo_cast_click(a)
	assert_array(_main._solo_target_mode.get("cast_picked", []) as Array) \
		.override_failure_message("re-click on the picked unit must take the pick back") \
		.is_empty()
	assert_int((_main._solo_target_mode.get("cast_pick_rings", {}) as Dictionary).size()).is_equal(0)
	assert_bool((_main._solo_target_mode.get("cast_valid", []) as Array).has(a)).is_true()
	assert_str(_log_text()).contains("AllyA unpicked")
	_main._solo_end_targeting()


# ===== (3) split fire: declaration stands, Fire! rolls, Cancel frees the unit =====

func _split_mode(shooter: GameUnit, foe_a: GameUnit) -> void:
	_main._solo_target_mode = {"unit": shooter, "melee": false, "split_first": foe_a,
		"split_b_names": ["Cannon"], "split_rest_names": ["Rifle"], "split_visuals": []}


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


func test_second_pick_declares_and_fire_button_resolves(timeout := 240000) -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle", "Cannon"])
	var foe_a := _armed(2, "FoeA", Vector3(8.0 * INCH, 0, 0), [])
	var foe_b := _armed(2, "FoeB", Vector3(0, 0, 8.0 * INCH), [])
	_split_mode(shooter, foe_a)
	_main._solo_split_declare_second(foe_b)
	assert_bool(_main._solo_target_mode.has("split_second")) \
		.override_failure_message("the second pick must DECLARE, not fire") \
		.is_true()
	assert_bool((_main._solo_target_mode.get("split_visuals", []) as Array).size() >= 2) \
		.override_failure_message("declared pairs must be drawn (rings + firing vectors)") \
		.is_true()
	assert_bool(shooter.is_activated).is_false()   # no dice yet — the GO button is the trigger
	assert_str(_log_text()).contains("press Fire!")
	_main._solo_split_commit()
	# Fire-and-forget coroutine: both volleys ride tray timers — give them real frame budget.
	for i in range(600):
		await _runner.simulate_frames(10)
		if shooter.is_activated:
			break
	var text := _log_text()
	assert_str(text).contains("Split fire: Tank fires at FoeA and FoeB")
	assert_str(text).contains("fires Rifle at FoeA")
	assert_str(text).contains("fires Cannon at FoeB")
	assert_bool(shooter.is_activated).is_true()


func test_cancel_at_go_stage_leaves_the_unit_free() -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle", "Cannon"])
	var foe_a := _armed(2, "FoeA", Vector3(8.0 * INCH, 0, 0), [])
	var foe_b := _armed(2, "FoeB", Vector3(0, 0, 8.0 * INCH), [])
	_split_mode(shooter, foe_a)
	_main._solo_split_declare_second(foe_b)
	_main._solo_split_abort()
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_bool(shooter.is_activated) \
		.override_failure_message("cancel at the GO stage must not consume the activation") \
		.is_false()
	assert_str(_log_text()).contains("Split fire cancelled — Tank has not acted")
