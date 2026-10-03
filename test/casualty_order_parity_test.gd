extends GdUnitTestSuite
## Tray-exact S4 — the TABLE side of the casualty-order parity pin. Every unit in
## core/nml-core/tests/fixtures/casualty_order.json is built as a GameUnit and
## SoloController.casualty_order must return the fixture's "expected"; the core's
## casualty::casualty_order is pinned to the same file (casualty.rs), so both agree.

const FIXTURE := "res://core/nml-core/tests/fixtures/casualty_order.json"


func _unit(spec: Dictionary) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = str(spec["name"])
	u.unit_properties = {"player_id": 1, "name": u.unit_id, "quality": 4, "defense": 4, "special_rules": []}
	for ms in spec["models"]:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		m.wounds_max = int(ms["wounds_max"])
		m.wounds_current = int(ms["wounds"])
		var weapons: Array = []
		for w in ms["weapons"]:
			weapons.append({"name": w})
		var equipment: Array = []
		for k in range(int(ms["equipment"])):
			equipment.append("Item %d" % k)
		m.properties = {"weapons": weapons, "equipment": equipment}
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(ms["pos"][0], ms["pos"][1], ms["pos"][2])
		m.node = n
		u.models.append(m)
	return u


## Tray-exact S5 — the chain-keeping order (SoloController.chain_casualty_order) on the fixture's
## "chains": round bases of `base_mm` at base scale 1 (model tough property 1), every pick.
func test_the_tables_chain_casualty_order_matches_the_shared_fixture() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for spec in data["chains"]:
		var u := _unit(spec)
		u.unit_properties["base_size_round"] = int(spec["base_mm"])
		u.unit_properties["game_system"] = "gf"
		for m in u.models:
			(m as ModelInstance).properties["tough"] = 1
		var got: Array = SoloController.chain_casualty_order(u)
		var want: Array = (spec["expected"] as Array).map(func(x: Variant) -> int: return int(x))
		assert_array(got).override_failure_message("%s: table %s, fixture %s" % [
			spec["name"], str(got), str(want)]).is_equal(want)


func test_the_tables_casualty_order_matches_the_shared_fixture() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for spec in data["units"]:
		var got: Array = SoloController.casualty_order(_unit(spec))
		var want: Array = (spec["expected"] as Array).map(func(x: Variant) -> int: return int(x))  # JSON numbers are floats
		assert_array(got).override_failure_message("%s: table %s, fixture %s" % [
			spec["name"], str(got), str(want)]).is_equal(want)
