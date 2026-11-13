extends GdUnitTestSuite
## E2E — MP: placing a Precision Tag has to reach the other table.
##
## THE DEFECT. `_solo_apply_precision_tag` first wrote `unit_properties["tag_markers"]` and THEN called
## `_sync_unit_property(unit, "tag_markers", <the same value>)`. The seam returns early when the key
## already holds the value (that is how the repeated spell restamps stay off the wire), so the
## placement never produced a `broadcast_unit_property` frame. The other table only heard about the
## marks when they were SPENT (`_solo_consume_tag_markers` computes the remainder and does not pre-write)
## — so for a whole round it saw a Tagged unit as untagged and rolled its own dice and range rings off
## the wrong number.
##
## The suite drives the REAL main.tscn placement and records what main hands to NetworkManager (the
## same FakeNet seam as e2e_mp_hidden_counters_test.gd).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


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
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A bearer with the shipped gf/jackals entry: Precision Tag is a "Utility Buff" there.
func _tagger(unit_name: String, x: int) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 1, unit_name, [Vector3.ZERO]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "jackals"
	u.unit_properties["special_rules"] = ["Precision Tag(%d)" % x]
	return u


## An enemy in reach; `models` 2 makes it the tougher pick when two are in reach.
func _foe(unit_name: String, pos: Vector3, models: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(pos + Vector3(0.02 * INCH * i, 0, 0))
	return _reg(E2EBoot.make_unit(_main, 2, unit_name, positions))


## Only the deltas for the Tag key, in the order main sent them.
func _sent() -> Array:
	var out: Array = []
	for e in _fake.sent:
		if str((e as Dictionary)["key"]) == "tag_markers":
			out.append(e)
	return out


## Read defensively: with no frame at all every assertion must still FAIL cleanly - an out-of-bounds
## index takes gdUnit's -d run into the debugger and the whole headless process down (signal 6).
func _first() -> Dictionary:
	var rows := _sent()
	return (rows[0] as Dictionary) if not rows.is_empty() else {}


func _values() -> Array:
	var out: Array = []
	for e in _sent():
		out.append((e as Dictionary)["value"])
	return out


## Stacked on one unit: ONE frame carrying the new count. Before the fix the pre-write made the seam
## see "unchanged" and the frame never left.
func test_a_placed_tag_sends_its_count(timeout := 120000) -> void:
	var tagger := _tagger("Marksman", 2)
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)

	_main._solo_apply_precision_tag(tagger)

	assert_int(int(alpha.unit_properties.get("tag_markers", 0))) \
		.override_failure_message("fixture check: both tokens must stack locally") \
		.is_equal(2)
	assert_array(_values()) \
		.override_failure_message("the placement never reached the wire — the other table sees an untagged unit (sent: %s)" % str(_fake.sent)) \
		.is_equal([2])
	assert_str(str(_first().get("unit", "<no message>"))) \
		.override_failure_message("the frame names the tagged unit") \
		.is_equal(alpha.unit_id)


## Spread over two units: one frame per tagged unit, each with its own count.
func test_a_spread_tag_sends_one_frame_per_unit(timeout := 120000) -> void:
	var tagger := _tagger("Marksman", 2)
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)
	var bravo := _foe("Bravo", Vector3(10.0 * INCH, 0, 6.0 * INCH), 1)

	_main._solo_apply_precision_tag(tagger)

	assert_int(int(alpha.unit_properties.get("tag_markers", 0))).is_equal(1)
	assert_int(int(bravo.unit_properties.get("tag_markers", 0))).is_equal(1)
	assert_array(_values()) \
		.override_failure_message("one token on each of two units must send two frames (sent: %s)" % str(_fake.sent)) \
		.is_equal([1, 1])
	var named: Array = []
	for e in _sent():
		named.append(str((e as Dictionary)["unit"]))
	named.sort()
	var expected: Array = [alpha.unit_id, bravo.unit_id]
	expected.sort()
	assert_array(named).is_equal(expected)


## A second Tag on an already-tagged unit sends the NEW TOTAL (the receiver's handler stores the
## value, it does not add a delta).
func test_a_second_tag_on_the_same_unit_sends_the_new_total(timeout := 120000) -> void:
	var first := _tagger("Marksman", 2)
	var second := _tagger("Sniper", 1)
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)

	_main._solo_apply_precision_tag(first)
	_main._solo_apply_precision_tag(second)

	assert_int(int(alpha.unit_properties.get("tag_markers", 0))).is_equal(3)
	assert_array(_values()) \
		.override_failure_message("each placement sends the running total (sent: %s)" % str(_fake.sent)) \
		.is_equal([2, 3])


## The Tag and its spend share the seam: after the placement went out, spending one token sends the
## remainder, so the peer ends on the same number the table does.
func test_placement_then_spend_ends_on_the_same_number(timeout := 120000) -> void:
	var tagger := _tagger("Marksman", 2)
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)

	_main._solo_apply_precision_tag(tagger)
	var spent: int = _main._solo_consume_tag_markers(alpha)

	assert_int(spent).is_equal(1)
	assert_array(_values()) \
		.override_failure_message("placement 2, then one spent -> the wire reads 2 then 1 (sent: %s)" % str(_fake.sent)) \
		.is_equal([2, 1])
	assert_int(int(alpha.unit_properties.get("tag_markers", 0))).is_equal(1)


## Offline the placement must stay silent and still count.
func test_a_solo_game_places_without_a_frame(timeout := 120000) -> void:
	_fake.active = false
	var tagger := _tagger("Marksman", 2)
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 2)

	_main._solo_apply_precision_tag(tagger)

	assert_int(int(alpha.unit_properties.get("tag_markers", 0))) \
		.override_failure_message("solo counting changed") \
		.is_equal(2)
	assert_array(_fake.sent) \
		.override_failure_message("an offline game broadcast hidden state") \
		.is_empty()
