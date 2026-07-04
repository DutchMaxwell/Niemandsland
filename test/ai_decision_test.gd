extends GdUnitTestSuite
## Solo-AI M2: AiDecision picks HOLD/ADVANCE/RUSH/CHARGE per archetype + situation. Deterministic.

const ADV := 6.0
const CHG := 12.0
const SHOOT := 24.0


func test_melee_charges_when_in_reach() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 10.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.CHARGE)


func test_melee_rushes_to_close_the_gap() -> void:
	# 15" > charge 12", but within charge+advance (18") → rush now to charge next turn.
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 15.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.RUSH)


func test_melee_advances_when_far() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.MELEE, 25.0, ADV, CHG, 0.0, false)).is_equal(AiDecision.Action.ADVANCE)


func test_shooter_holds_when_in_range() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 12.0, ADV, CHG, SHOOT, true)).is_equal(AiDecision.Action.HOLD)


func test_shooter_advances_into_range() -> void:
	# Out of range now, but advancing 6" brings the 8" target within 24" range → advance (can still shoot).
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 8.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.ADVANCE)


func test_shooter_rushes_when_far_out_of_range() -> void:
	# 40" target, advancing alone (→34") still can't reach 24" range → rush to close faster.
	assert_int(AiDecision.decide(AiArchetype.Type.SHOOTING, 40.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.RUSH)


func test_hybrid_charges_then_shoots_then_advances() -> void:
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 10.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.CHARGE)
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 20.0, ADV, CHG, SHOOT, true)).is_equal(AiDecision.Action.HOLD)
	assert_int(AiDecision.decide(AiArchetype.Type.HYBRID, 20.0, ADV, CHG, SHOOT, false)).is_equal(AiDecision.Action.ADVANCE)
