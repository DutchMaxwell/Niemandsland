extends GdUnitTestSuite
## W-P1 parity — Musician reaches the LAB's move bands. The game grants +1"
## on every move band inside _act(); the sim's seven band reads used the raw
## bands and imagined carriers 1" short. sim_move_bands() is the one truth.

const IN2M := 0.0254


func _unit(id: String, pid: int, rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "name": id, "quality": 4, "defense": 4,
		"special_rules": rules}
	var m: ModelInstance = ModelInstance.new()
	m.unit = u
	m.is_alive = true
	m.node = auto_free(Node3D.new())
	add_child(m.node)
	u.models.append(m)
	return u


func test_sim_bands_carry_the_musician_inch_on_both_bands() -> void:
	var plain := _unit("Plain", 1, [])
	var brass := _unit("Brass", 1, ["Musician"])
	var pb: Dictionary = SoloController.sim_move_bands(plain)
	var bb: Dictionary = SoloController.sim_move_bands(brass)
	assert_float(float(bb["advance"])).is_equal_approx(float(pb["advance"]) + 1.0, 0.001)
	assert_float(float(bb["rush"])).is_equal_approx(float(pb["rush"]) + 1.0, 0.001)


func test_resolve_moves_the_carrier_the_extra_inch() -> void:
	var brass := _unit("Brass", 1, ["Musician"])
	var plain := _unit("Plain", 1, [])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Brass": brass, "Plain": plain}
	var state := BattleSim.capture(army)
	var far := Vector3(0, 0, 60.0 * IN2M)
	var nb := BattleSim.resolve(state, {"unit": "Brass", "kind": AiDecision.Action.RUSH, "dest": far})
	var np := BattleSim.resolve(state, {"unit": "Plain", "kind": AiDecision.Action.RUSH, "dest": far})
	var db: float = ((nb["units"]["Brass"] as Dictionary)["positions"][0] as Vector3).z / IN2M
	var dp: float = ((np["units"]["Plain"] as Dictionary)["positions"][0] as Vector3).z / IN2M
	assert_float(db - dp).is_equal_approx(1.0, 0.01)
