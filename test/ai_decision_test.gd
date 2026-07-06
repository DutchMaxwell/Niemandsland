extends GdUnitTestSuite
## Solo-AI M2: AiDecision — the OFFICIAL v3.5.0 no-objective tree branches (objectives = M3).

const ADV := 6.0
const CHG := 12.0
const SHOOT := 24.0


func test_melee_charges_when_in_reach() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 10.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.CHARGE)


func test_melee_rushes_whenever_out_of_charge_range() -> void:
	# Official tree: a melee unit out of charge range always RUSHES toward the enemy — it never merely
	# advances (the old charge+advance window was a deviation).
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 15.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.RUSH)
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 40.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.RUSH)


func test_shooter_kites_when_already_in_range() -> void:
	# "Advancing" basic concept: shooters in range move AWAY from the closest enemy, staying in range.
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 12.0, ADV, CHG, SHOOT, true)).is_equal(AiDecision.Action.KITE)


func test_shooter_advances_into_range() -> void:
	# Out of range/LOS now, but advancing 6" brings the 26" target within 24" range → advance + shoot.
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 26.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.ADVANCE)


func test_shooter_rushes_when_far_out_of_range() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 40.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.RUSH)


func test_hybrid_charges_then_shoots_then_rushes() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 10.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.CHARGE)
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 20.0, ADV, CHG, SHOOT, true)).is_equal(AiDecision.Action.ADVANCE)
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 26.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.ADVANCE)
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 45.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.RUSH)
