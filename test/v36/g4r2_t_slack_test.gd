extends GdUnitTestSuite
## G4R2 F-T-SLACK (PARITY_DIAG_1104_R2_SHOOT 2.13, lead ruling D3): a weapon reaches when the NEAREST base edge
## of the target is within its printed range, with no extra slack. Replaying aof_1000_net_003 act 1 shows both
## engines already agree on that: at the table's landing the host's 12" Spout Flames stand 12.3" from the
## nearest foe model and neither engine fires them. The shot the core takes there is the JOINED HERO's 24" Chakram
## (without it the core is silent too). The table's activation gates read the host's own weapon list only, so the
## 24" gun never opened the gate: "no shot - nearest enemy 12.3" away, weapon reach 12"". From EPOCH_73_V36 the
## gates read the living chain (host plus joined heroes), the list the volley itself fires. The controls come
## first (gdUnit drops the cases declared after a failing one in a scene suite): the 11.9" / 12.1" pair pins the
## no-slack reading, a short hero gun opens nothing, and below 73 the host-only read stands.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := Vector3(0.03, 0.0, 0.03)   # a point inside some 3" terrain cell

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	RulesRegistry.reset_cache()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = _epoch_before


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _weapon(wname: String, range_in: int, attacks: int) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	return w


func _armed(u: GameUnit, weapon: OPRApiClient.OPRWeapon) -> void:
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["special_rules"] = []
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons.append(weapon)
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u


## The act's host: two models with a 12" gun (the act's Scorchers carry Spout Flames).
func _host() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Scorchers", [SEED, SEED + Vector3(2.0 * INCH, 0.0, 0.0)])
	_armed(u, _weapon("Spout Flames", 12, 1))
	return u


## The joined hero (the act's Harbinger of Change): one model beside the host, a gun of `range_in`.
func _join_hero(host: GameUnit, wname: String, range_in: int) -> GameUnit:
	var hero := E2EBoot.make_unit(_main, 2, "Harbinger of Change", [SEED + Vector3(0.0, 0.0, 2.0 * INCH)])
	_armed(hero, _weapon(wname, range_in, 6))
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	return hero


## A lone foe whose nearest model edge stands `gap_in` inches from the host's nearest model edge: placed once,
## measured through the controller's own gap seam, then shifted by the difference.
func _foe_at_gap(shooter: GameUnit, gap_in: float) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Shooter-Furies", [SEED + Vector3(30.0 * INCH, 0.0, 0.0)])
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["special_rules"] = []
	_main.opr_army_manager.game_units[u.unit_id] = u
	var solo: SoloController = _main.solo_controller
	var epoch_now := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36   # the base-edge gap is only measured from 73 on
	var first: float = solo.shoot_reach_gap_in(shooter, u, 0.0)
	var node: Node3D = (u.models[0] as ModelInstance).node
	node.global_position += Vector3((gap_in - first) * INCH, 0.0, 0.0)
	var now: float = solo.shoot_reach_gap_in(shooter, u, 0.0)
	AiActRecorder.rules_epoch = epoch_now
	assert_float(now).override_failure_message("fixture: the nearest base-edge gap must be %.2f\" (is %.2f\")" % [gap_in, now]) \
		.is_between(gap_in - 0.02, gap_in + 0.02)
	return u


## One Hold-and-shoot activation of `shooter` at `target`, through the controller's own intent door and the
## table's rule-note printer. `source` "ai" lets the post-move retarget run; "player" never retargets.
func _hold(shooter: GameUnit, target: GameUnit, source: String) -> Dictionary:
	var solo: SoloController = _main.solo_controller
	var intent := solo.player_intent(shooter, AiDecision.Action.HOLD, target)
	intent["source"] = source
	var report := solo.execute_intent(intent, ActIntent.blank_report(shooter))
	_main._print_rule_notes(report)
	return report


# ===== controls (green before and after the fix) =====

## D3: the host's 12" gun reaches a foe whose nearest base edge is 11.9" away, and not one at 12.1".
func test_the_host_gun_alone_reaches_at_11_9_and_not_at_12_1() -> void:
	var shooter := _host()
	var near := _foe_at_gap(shooter, 11.9)
	assert_bool(bool(_hold(shooter, near, "player")["can_shoot"])) \
		.override_failure_message("a 12\" gun reaches a nearest base edge at 11.9\"").is_true()
	var far := _foe_at_gap(shooter, 12.1)
	assert_bool(bool(_hold(shooter, far, "player")["can_shoot"])) \
		.override_failure_message("no extra slack: a 12\" gun does not reach 12.1\"").is_false()


## A hero whose gun is SHORTER than the host's opens nothing: the chain reach is the longest gun, no more.
func test_a_short_hero_gun_does_not_extend_the_reach_at_73() -> void:
	var shooter := _host()
	_join_hero(shooter, "Hex Pistol", 6)
	var foe := _foe_at_gap(shooter, 12.3)
	var report := _hold(shooter, foe, "player")
	assert_bool(bool(report["can_shoot"])).is_false()
	assert_str(_log_text()).not_contains("Hero:")


## Below the 3.6 epoch the host's own list stands byte for byte: the 24" gun still does not open the gate.
func test_below_73_the_host_only_read_stays() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var shooter := _host()
	_join_hero(shooter, "Heavy Hexed Chakram", 24)
	var foe := _foe_at_gap(shooter, 12.3)
	var report := _hold(shooter, foe, "player")
	assert_bool(bool(report["can_shoot"])).is_false()
	assert_str(_log_text()).not_contains("Hero:")


# ===== the fix (RED before) =====

## aof_1000_net_003 act 1: the host's flames stop at 12", the joined hero's 24" Chakram reaches the foe 12.3"
## away, so the gate opens, and the log names the Hero rule.
func test_the_joined_heros_longer_gun_opens_the_gate_at_73() -> void:
	var shooter := _host()
	_join_hero(shooter, "Heavy Hexed Chakram", 24)
	var foe := _foe_at_gap(shooter, 12.3)
	var report := _hold(shooter, foe, "player")
	var text := _log_text()
	assert_bool(bool(report["can_shoot"])) \
		.override_failure_message("the hero's 24\" Chakram reaches 12.3\" (log: %s)" % text.strip_edges()).is_true()
	assert_str(text) \
		.override_failure_message("rules-must-log: the Hero rule names itself (log: %s)" % text.strip_edges()) \
		.contains("Scorchers: Hero")


## The post-move retarget scan reads the same chain: the foe only the hero's gun reaches is the pick.
func test_the_retarget_picks_a_foe_only_the_heros_gun_reaches_at_73() -> void:
	var shooter := _host()
	_join_hero(shooter, "Heavy Hexed Chakram", 24)
	var foe := _foe_at_gap(shooter, 12.3)
	assert_object(_main.solo_controller.best_shoot_target_now(shooter, true)) \
		.override_failure_message("the picker measured the host's 12\" only").is_same(foe)
