extends GdUnitTestSuite
## One-core P3 step 46: the Godot binding of the core's round, `NmlCore.round_end` / `round_begin`.
## Real: the NmlCore extension (the CI shards build and load it), BattleSim.capture + state_to_plain.
## Constructed: one objective at the origin owned by side 2; "a" (side 1) 1" from it, "s" (side 2, placed by Spawn this
## round) 2" from it, "b" (side 2) 20" away. The full table-vs-core comparison is step 48's gate.

const IN2M := 0.0254
const WORDS := {"labels": {1: "P1 (Alpha)", 2: "P2 (Beta)"}, "cite": "GF 3.5", "placed_by": {"s": "Spawn"}}

var _core: Object
var _h := 0


func before_test() -> void:
	_core = ClassDB.instantiate("NmlCore")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"a": _unit(1, 1.0, "a"), "s": _unit(2, -2.0, "s"), "b": _unit(2, 20.0, "b")}
	(army.game_units["s"] as GameUnit).unit_properties["ambush_arrived_round"] = 2
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO], func(_i: int) -> int: return 2, 2, 4)
	_h = _core.capture_plain(BattleSim.state_to_plain(state))


## One bare model at `x_in` inches on the x axis (step_activation_binding_test.gd's `_unit`, one model).
func _unit(pid: int, x_in: float, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = Vector3(x_in * IN2M, 0, 0)
	m.node = n
	u.models.append(m)
	return u


func test_the_round_end_seizes_with_the_arrival_reason_and_the_round_begin_names_the_opener() -> void:
	var r: Dictionary = _core.round_end(_h, WORDS)
	assert_array(r["owners"]).is_equal([1])
	assert_str(str(r["lines"][0]["text"])).is_equal(
		"Objective 1 seized by P1 (Alpha) — s was placed by Spawn this round and cannot seize or contest (GF 3.5)")
	var b: Dictionary = _core.round_begin(int(r["handle"]), 2)
	assert_int(int(b["opener"])).is_equal(2)
	assert_str(str(b["lines"][0]["text"])).is_equal("Round 3 begins")
	for h in [_h, int(r["handle"]), int(b["handle"])]:
		_core.release(h)


func test_a_malformed_words_dictionary_and_an_unknown_handle_are_refused() -> void:
	assert_bool(_core.round_end(_h, {"labels": "P1 (Alpha)"}).has("refused")).is_true()
	assert_bool(_core.round_end(_h, {"placed_by": {"s": 3}}).has("refused")).is_true()
	assert_bool(_core.round_end(999999, WORDS).has("refused")).is_true()
	assert_bool(_core.round_begin(999999, 1).has("refused")).is_true()
	_core.release(_h)
