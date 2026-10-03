extends GdUnitTestSuite
## Tray-exact series S2 — the table's capture writes each living model's KIT: what
## SoloController.casualty_order (solo_controller.gd:9151-9220) ranks a model by — its weapon
## entries (names, duplicates kept), its equipment count and its own Tough. The Rust core reads it
## from the plain state's per-unit `kits` (core/nml-core/src/io.rs PlainKit), slot-aligned with
## `positions`, so its casualty order and its Takedown pick can be the table's.

const IN2M := 0.0254


func _model(u: GameUnit, at: Vector3, weapons: Array, equipment: Array, tough: int) -> ModelInstance:
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_max = tough
	m.wounds_current = tough
	m.unit = u
	m.properties = {"weapons": weapons, "equipment": equipment}
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	m.node = n
	return m


func _state() -> Dictionary:
	var a := GameUnit.new()
	a.unit_id = "A"
	a.unit_properties = {"player_id": 1, "name": "A", "quality": 4, "defense": 4, "special_rules": []}
	a.models.append(_model(a, Vector3.ZERO, [{"name": "Rifle"}], [], 1))
	a.models.append(_model(a, Vector3(1.0 * IN2M, 0, 0),
		[{"name": "Rifle"}, {"name": "Missile Launcher"}], [{"name": "Comms"}], 3))
	var dead := _model(a, Vector3(2.0 * IN2M, 0, 0), [{"name": "Rifle"}], [], 1)
	dead.is_alive = false
	a.models.append(dead)
	var b := GameUnit.new()
	b.unit_id = "B"
	b.unit_properties = {"player_id": 2, "name": "B", "quality": 4, "defense": 4, "special_rules": []}
	b.models.append(_model(b, Vector3(12.0 * IN2M, 0, 0), [{"name": "CCW"}], [], 1))
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"A": a, "B": b}
	return BattleSim.capture(army, func() -> Array: return [], func(_i: int) -> int: return 0, 1, 3)


func test_the_plain_state_carries_one_kit_per_living_model_aligned_with_positions() -> void:
	var plain: Dictionary = BattleSim.state_to_plain(_state(), false)
	var a: Dictionary = plain["units"]["A"]
	var kits: Array = a.get("kits", [])
	assert_int(kits.size()).override_failure_message(
		"no kits: the core cannot rank casualties or pick a Takedown target").is_equal(2)
	if kits.size() != 2:
		return
	assert_int(kits.size()).is_equal((a["positions"] as Array).size())
	assert_dict(kits[0]).is_equal({"weapons": ["Rifle"], "equipment": 0, "wounds_max": 1})
	assert_dict(kits[1]).is_equal({"weapons": ["Rifle", "Missile Launcher"], "equipment": 1, "wounds_max": 3})
