extends GdUnitTestSuite
## C-2: `CoreActivation.ai_transcript` - the AI activation's transcript before its first die, shared by `run_ai` and the
## shadow replay. Without a split aim it is exactly the three entries `run_ai` always sent (no "split" key, so the
## core's answer is unchanged); with one, the intent carries it. RED: drop the empty-split guard and the first case
## gains a "split" key.
## Constructed: a stub main (only `solo_controller.last_move_paths` is read), two bare units in the tree.

const IN2M := 0.0254


class StubController:
	var last_move_paths: Array = []


class StubMain:
	var solo_controller := StubController.new()


func _unit(uid: String, positions: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": 1, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n: Node3D = auto_free(Node3D.new())
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func test_the_transcript_is_begin_placed_intent_with_the_walked_routes() -> void:
	var a := _unit("a", [Vector3(1.0 * IN2M, 0, 2.0 * IN2M), Vector3(3.0 * IN2M, 0, 0)])
	var b := _unit("b", [Vector3(20.0 * IN2M, 0, 0)])
	var main := StubMain.new()
	main.solo_controller.last_move_paths = [{"model": a.models[0], "path": [Vector3(0, 0, 0), Vector3(1.0 * IN2M, 0, 2.0 * IN2M)]}]
	var t := CoreActivation.ai_transcript(main, a, {"action": AiDecision.Action.ADVANCE}, b)
	assert_array(t).is_equal([{"t": "begin"},
		{"t": "placed", "positions": [a.models[0].node.global_position, a.models[1].node.global_position],
			"trails": [[Vector2(0, 0), Vector2(1.0 * IN2M, 2.0 * IN2M)], []]},
		{"t": "intent", "kind": AiDecision.Action.ADVANCE, "shoot": "b"}])


func test_a_split_aim_rides_the_intent_and_no_target_sends_no_shoot() -> void:
	var a := _unit("a", [Vector3.ZERO])
	var b := _unit("b", [Vector3(20.0 * IN2M, 0, 0)])
	var aim := [{"member": "a", "weapon": "Rifle", "target": "b"}]
	var t := CoreActivation.ai_transcript(StubMain.new(), a, {"action": AiDecision.Action.HOLD}, b, aim)
	assert_dict(t[2]).is_equal({"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": "b", "split": aim})
	assert_dict(CoreActivation.ai_transcript(StubMain.new(), a, {"action": AiDecision.Action.HOLD}, null)[2]) \
		.is_equal({"t": "intent", "kind": AiDecision.Action.HOLD})


func _shot(member: GameUnit, weapon: String) -> Dictionary:
	return {"member": member, "profile": {"name": weapon}}


## C-17: `split_aim` is the aim `sim.rs split_plan` reads: the member's NAME (the core finds it by name), the weapon, the target's key,
## the groups in the table's order; one group has none. RED: send the member's unit id and the core drops every weapon.
func test_the_split_aim_names_member_weapon_and_target_key_in_group_order() -> void:
	var a := _unit("a", [Vector3.ZERO])
	var b := _unit("b", [Vector3.ZERO])
	var c := _unit("c", [Vector3.ZERO])
	var parts := [{"target": b, "shots": [_shot(a, "Rifle")]}, {"target": c, "shots": [_shot(a, "Lance"), _shot(a, "Pistol")]}]
	assert_array(CoreActivation.split_aim(parts)).is_equal([{"member": "a", "weapon": "Rifle", "target": "b"},
		{"member": "a", "weapon": "Lance", "target": "c"}, {"member": "a", "weapon": "Pistol", "target": "c"}])
	assert_array(CoreActivation.split_aim(parts.slice(0, 1))).is_empty()


## One (member, weapon) named for two targets is what the core pools (`split_weapon_reaimed`); the door refuses it. The same weapon twice at
## ONE target is no re-aim.
func test_an_aim_naming_one_weapon_for_two_targets_is_ambiguous() -> void:
	var one := {"member": "a", "weapon": "Gun", "target": "b"}
	assert_bool(CoreActivation._aim_ambiguous([one, {"member": "a", "weapon": "Gun", "target": "c"}])).is_true()
	assert_bool(CoreActivation._aim_ambiguous([one, one])).is_false()
	assert_bool(CoreActivation._aim_ambiguous([one, {"member": "a", "weapon": "Lance", "target": "c"}])).is_false()
	assert_bool(CoreActivation._aim_ambiguous([])).is_false()
