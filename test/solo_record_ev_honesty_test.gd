extends GdUnitTestSuite
## Stage 1 record honesty — the candidate EV inside a 'target' record. The charge tie-break score is a
## NET dealt-minus-taken utility that legitimately drops below zero against a superior enemy. The record
## floored it at 0.0, so "the machine had no preference" and "the machine saw a losing trade" read
## identically afterwards — and that is the exact field the ghost-shot tie analysis leans on. The record
## must carry the RAW score. Selection ranks the raw values and never the recorded ones, so what the AI
## PICKS is unchanged; this suite asserts both halves.

const IN2M := 0.0254


func _unit(pid: int, pos: Vector3, uid: String, quality: int, defense: int, models: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": quality, "defense": defense}
	for i in range(models):
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = pos + Vector3(0, 0, float(i) * 0.03)
		m.node = n
		u.models.append(m)
	return u


func _arm_melee(u: GameUnit, attacks: int) -> void:
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = attacks
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr


## A lone Q6 brawler between two equally-near, equally-fresh enemies: charging the elite squad is a
## clearly LOSING trade (negative net EV), charging the lone weakling is the better of the two.
func test_target_record_keeps_a_negative_candidate_ev_and_the_pick_stands() -> void:
	var brawler := _unit(2, Vector3.ZERO, "Brawler", 6, 6, 1)
	_arm_melee(brawler, 1)
	var elite := _unit(1, Vector3(10.0 * IN2M, 0, 0), "Elite", 3, 2, 5)
	_arm_melee(elite, 4)
	var weak := _unit(1, Vector3(0, 0, 10.0 * IN2M), "Weak", 5, 4, 1)
	_arm_melee(weak, 1)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {brawler.unit_id: brawler, elite.unit_id: elite, weak.unit_id: weak}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var recs: Array = []
	solo.decision_sink = func(rec: Dictionary) -> void:
		if str(rec.get("kind", "")) == "target":
			recs.append(rec)

	var picked := solo.nearest_human_unit(brawler)

	# BEHAVIOUR GUARD: the raw score still drives the pick — the less-bad trade wins the tie.
	assert_object(picked).override_failure_message(
		"the AI must still take the weaker of two tied targets").is_equal(weak)
	assert_int(recs.size()).is_equal(1)
	var by_name := {}
	for c in (recs[0]["candidates"] as Array):
		by_name[str((c as Dictionary)["name"])] = float((c as Dictionary)["ev"])
	assert_str(str(recs[0]["chosen"])).is_equal("Weak")
	assert_bool(by_name.has("Elite")).override_failure_message(
		"both tied targets belong in the record").is_true()
	# THE FIX: the losing trade is written down as the negative number it is, not as a flat 0.00.
	assert_float(float(by_name["Elite"])).override_failure_message(
		"a losing charge must be recorded as negative EV, not floored to zero").is_less(0.0)
	# And it must be the SAME number the ranking used — not merely "some negative value".
	assert_float(float(by_name["Elite"])).is_less(float(by_name["Weak"]))
