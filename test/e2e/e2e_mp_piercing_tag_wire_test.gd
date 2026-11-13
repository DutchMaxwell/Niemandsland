extends GdUnitTestSuite
## E2E - MP (online co-op, #673): the AI's Piercing Tag markers have to reach the other table.
##
## THE DEFECT. In an online co-op room two humans face one AI seat and the AI's activation "resolves
## on whichever machine's activation it answered" (see e2e_coop_ai_cast_interference_test.gd). The
## Piercing Tag family keeps its pool in `unit_properties["piercing_tag_markers"]` (plus
## `piercing_tag_source`, which decides spend-whole vs. stands-while-it-lives), and every write was a
## plain local one with no key on NetworkManager's allow-list. A tag the AI placed while answering
## player 1 therefore did not exist on player 2's machine: when the AI answered player 2 later, its
## volley spent nothing (no +AP), and a spend made there never reached the first machine either.
##
## The suite drives the REAL main.tscn placement / spend and records what main hands to
## NetworkManager (the FakeNet seam of e2e_mp_hidden_counters_test.gd), then replays those exact
## arguments into the REAL receiver on a "second machine" whose copy of the unit starts empty.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const MARKERS := "piercing_tag_markers"
const SOURCE := "piercing_tag_source"


## Stands in for NetworkManager at main's seam: a live session that records every outbound hidden
## state delta in the order main sent them.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func broadcast_unit_property(gu: GameUnit, key: String, value: Variant) -> void:
		sent.append({"unit": gu.unit_id, "key": key, "value": value})

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet
var _real_net: Node
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true   # no dialogs, no physics tray, no floating text in a headless sweep
	_real_net = _main.network_manager   # kept for the receive-side proof (its handler is call_remote)
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null
	_real_net = null


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The AI's tagger: alien_hives prints the plain Piercing Tag, custodian_brothers the Piercing Target.
func _tagger(rule: String, faction: String) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 2, "Marksman", [Vector3.ZERO]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = [rule]
	return u


## A human unit in reach; `models` 2 makes it the tougher pick when two are in reach.
func _foe(unit_name: String, pos: Vector3, models: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(pos + Vector3(0.02 * INCH * i, 0, 0))
	return _reg(E2EBoot.make_unit(_main, 1, unit_name, positions))


func _rows(key: String) -> Array:
	var out: Array = []
	for e in _fake.sent:
		if str((e as Dictionary)["key"]) == key:
			out.append(e)
	return out


func _values(key: String) -> Array:
	var out: Array = []
	for e in _rows(key):
		out.append((e as Dictionary)["value"])
	return out


## Read defensively: with no frame at all every assertion must still FAIL cleanly - an out-of-bounds
## index takes gdUnit's -d run into the debugger and the whole headless process down.
func _first(key: String) -> Dictionary:
	var rows := _rows(key)
	return (rows[0] as Dictionary) if not rows.is_empty() else {}


## The second machine: it never saw the placement, so its copy of the unit starts without the keys;
## it then receives exactly the frames this machine sent, through the REAL receiver.
func _replay_on_the_other_table(unit: GameUnit) -> void:
	unit.unit_properties.erase(MARKERS)
	unit.unit_properties.erase(SOURCE)
	for e in _fake.sent:
		var d := e as Dictionary
		_real_net.sync_unit_property(str(d["unit"]), str(d["key"]), d["value"])


# === 1. Placement ================================================================================

## Stacked on one unit: ONE count frame, and the rule that placed it.
func test_a_stacked_tag_sends_its_count_and_its_source(timeout := 120000) -> void:
	var tagger := _tagger("Piercing Tag(2)", "alien_hives")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)

	await _main._solo_apply_piercing_tag(tagger)

	assert_int(int(alpha.unit_properties.get(MARKERS, 0))) \
		.override_failure_message("fixture check: both tokens must stack locally") \
		.is_equal(2)
	assert_array(_values(MARKERS)) \
		.override_failure_message("the placement never reached the wire - the other table sees an untagged unit (sent: %s)" % str(_fake.sent)) \
		.is_equal([2])
	assert_str(str(_first(MARKERS).get("unit", "<no message>"))).is_equal(alpha.unit_id)
	assert_array(_values(SOURCE)) \
		.override_failure_message("the pool's source decides spend-whole vs stands - it has to travel with the count (sent: %s)" % str(_fake.sent)) \
		.is_equal(["Piercing Tag"])


## Spread over two units: one count frame per tagged unit.
func test_a_spread_tag_sends_one_frame_per_unit(timeout := 120000) -> void:
	var tagger := _tagger("Piercing Tag(2)", "alien_hives")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)
	var bravo := _foe("Bravo", Vector3(10.0 * INCH, 0, 6.0 * INCH), 1)

	await _main._solo_apply_piercing_tag(tagger)

	assert_int(int(alpha.unit_properties.get(MARKERS, 0))).is_equal(1)
	assert_int(int(bravo.unit_properties.get(MARKERS, 0))).is_equal(1)
	assert_array(_values(MARKERS)) \
		.override_failure_message("one token on each of two units must send two frames (sent: %s)" % str(_fake.sent)) \
		.is_equal([1, 1])
	var named: Array = []
	for e in _rows(MARKERS):
		named.append(str((e as Dictionary)["unit"]))
	named.sort()
	var expected: Array = [alpha.unit_id, bravo.unit_id]
	expected.sort()
	assert_array(named).is_equal(expected)


# === 2. Spending =================================================================================

## 3.6: one token per attack - every spend sends the remainder, down to 0.
func test_each_spend_sends_the_remainder(timeout := 120000) -> void:
	var tagger := _tagger("Piercing Tag(2)", "alien_hives")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)
	await _main._solo_apply_piercing_tag(tagger)

	assert_int(_main._solo_spend_piercing_tag(alpha)).is_equal(1)
	assert_int(_main._solo_spend_piercing_tag(alpha)).is_equal(1)

	assert_int(int(alpha.unit_properties.get(MARKERS, 0))).is_equal(0)
	assert_array(_values(MARKERS)) \
		.override_failure_message("placement 2, then two single spends - the wire reads 2, 1, 0 (sent: %s)" % str(_fake.sent)) \
		.is_equal([2, 1, 0])


## 3.5: the first attack spends the whole pool - one frame, 0.
func test_a_spend_whole_sends_zero_below_73(timeout := 120000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var tagger := _tagger("Piercing Tag(2)", "alien_hives")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)
	await _main._solo_apply_piercing_tag(tagger)

	assert_int(_main._solo_spend_piercing_tag(alpha)).is_equal(2)

	assert_array(_values(MARKERS)) \
		.override_failure_message("3.5: placement 2, then the whole pool spent (sent: %s)" % str(_fake.sent)) \
		.is_equal([2, 0])


## Piercing Target stands while the target lives: nothing changes on a spend, so nothing is sent.
func test_a_standing_piercing_target_pool_sends_nothing_on_a_spend(timeout := 120000) -> void:
	var tagger := _tagger("Piercing Target", "custodian_brothers")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 1)
	await _main._solo_apply_piercing_tag(tagger)

	assert_int(_main._solo_spend_piercing_tag(alpha)).is_equal(1)
	assert_int(_main._solo_spend_piercing_tag(alpha)).is_equal(1)

	assert_array(_values(MARKERS)) \
		.override_failure_message("the pool stands: one placement frame and no spend frame (sent: %s)" % str(_fake.sent)) \
		.is_equal([1])
	assert_array(_values(SOURCE)).is_equal(["Piercing Target"])


# === 3. The other table ==========================================================================

## THE CO-OP CASE: the AI answered player 1 on machine A and placed the tag; it answers player 2 on
## machine B. B only knows what the wire told it - so its volley must still spend a token.
func test_the_other_table_can_spend_what_this_table_placed(timeout := 120000) -> void:
	var tagger := _tagger("Piercing Tag(2)", "alien_hives")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)
	await _main._solo_apply_piercing_tag(tagger)

	_replay_on_the_other_table(alpha)

	assert_int(int(alpha.unit_properties.get(MARKERS, 0))) \
		.override_failure_message("the second machine never learned of the tag (sent: %s)" % str(_fake.sent)) \
		.is_equal(2)
	assert_int(_main._solo_spend_piercing_tag(alpha)) \
		.override_failure_message("the AI's volley on the second machine got no +AP from a tag placed on the first") \
		.is_equal(1)
	assert_int(int(alpha.unit_properties.get(MARKERS, 0))).is_equal(1)


## The same round trip for the standing pool: without the SOURCE the second machine would treat a
## Piercing Target as a plain tag and burn the pool down on its first volley.
func test_the_other_table_keeps_a_piercing_target_standing(timeout := 120000) -> void:
	var tagger := _tagger("Piercing Target", "custodian_brothers")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 1)
	await _main._solo_apply_piercing_tag(tagger)

	_replay_on_the_other_table(alpha)

	assert_int(_main._solo_spend_piercing_tag(alpha)).override_failure_message("first volley on the second machine").is_equal(1)
	assert_int(_main._solo_spend_piercing_tag(alpha)) \
		.override_failure_message("the pool must stand on the second machine too - the source did not arrive") \
		.is_equal(1)


# === 4. Counter-proofs ===========================================================================

## Offline the whole thing must stay silent and still count.
func test_a_solo_game_places_and_spends_without_a_frame(timeout := 120000) -> void:
	_fake.active = false
	var tagger := _tagger("Piercing Tag(2)", "alien_hives")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)

	await _main._solo_apply_piercing_tag(tagger)
	assert_int(_main._solo_spend_piercing_tag(alpha)).is_equal(1)

	assert_int(int(alpha.unit_properties.get(MARKERS, 0))) \
		.override_failure_message("solo counting changed") \
		.is_equal(1)
	assert_str(str(alpha.unit_properties.get(SOURCE, ""))).is_equal("Piercing Tag")
	assert_array(_fake.sent) \
		.override_failure_message("an offline game broadcast hidden state") \
		.is_empty()


## The allow-list is still a boundary: the new keys are listed, ownership still is not.
func test_the_receiver_takes_the_piercing_keys_and_still_refuses_ownership(timeout := 120000) -> void:
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 1)

	_real_net.sync_unit_property(alpha.unit_id, "player_id", 2)
	assert_int(int(alpha.unit_properties.get("player_id", 0))).is_equal(1)

	_real_net.sync_unit_property(alpha.unit_id, MARKERS, 3)
	_real_net.sync_unit_property(alpha.unit_id, SOURCE, "Piercing Tag")
	assert_int(int(alpha.unit_properties.get(MARKERS, 0))).is_equal(3)
	assert_str(str(alpha.unit_properties.get(SOURCE, ""))).is_equal("Piercing Tag")
