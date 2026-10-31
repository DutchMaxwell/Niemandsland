extends GdUnitTestSuite
## Rules 3.6 wave, row W1.5a (D-GATE6): a charge is measured before any model moves, from the closest model
## to the closest model, base edge to base edge, and the Screened family's charge leg reads the shared 6"
## charge threshold (shooting keeps 9"). Both legs pinned: at 72 the table keeps its unit-centre charge
## distance and its melee hit modifiers never see it; at 73 the measure is the edge gap and the Screened
## charge leg reads it.
##
## The new helpers are reached through has_method/call, so a missing one fails on the assertion, not on
## parsing; the fallback is the table's behaviour before the row (centre distance, 0.0 melee read), so
## the epoch-72 legs and the unchanged 73 cases are controls that pass with and without the row.

const MainScript := preload("res://scripts/main.gd")
const M := 0.0254

var _epoch0 := 0
var _uid := 0


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


## One single-model unit at `x_in` inches along the table's x axis on a round base of `base_mm`.
func _unit(pid: int, rules: Array, x_in: float, base_mm: int) -> GameUnit:
	var u := GameUnit.new()
	_uid += 1
	u.unit_id = "w15a_%d_%d" % [pid, _uid]
	u.unit_properties = {"player_id": pid, "name": "U%d" % _uid, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "machine_cults", "base_size_round": base_mm}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = Vector3(x_in * M, 0.0, 0.0)
	m.node = n
	u.models.append(m)
	return u


func _bare_main() -> Node3D:
	var main: Node3D = auto_free(MainScript.new())
	main.solo_controller = auto_free(SoloController.new())
	return main


## The charge distance the table stamps into report["charge_from_in"], from the same centre distance the
## intent carries.
func _charge_from_in(solo: SoloController, att: GameUnit, tgt: GameUnit) -> float:
	var centre_in := MoveIntent.distance_inches(solo.unit_centre(att), solo.unit_centre(tgt))
	if not solo.has_method("charge_from_in"):
		return centre_in
	return float(solo.call("charge_from_in", att, tgt, centre_in))


## The melee hit modifier of the charger's strikes after a charge between the two units, as the melee
## strike phase builds it at `epoch`.
func _charge_hit_mod(epoch: int, centre_in: float, att_mm: int, tgt_mm: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var main := _bare_main()
	var att := _unit(2, [], 0.0, att_mm)
	var tgt := _unit(1, ["Screened"], centre_in, tgt_mm)
	var d := _charge_from_in(main.solo_controller, att, tgt)
	var leg_in := 0.0
	if main.has_method("_solo_charge_leg_dist_in"):
		leg_in = float(main.call("_solo_charge_leg_dist_in", true, d))
	return main._solo_hit_mod_info(att, tgt, leg_in, true, true)


func test_the_charge_distance_is_the_unit_centre_distance_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var solo: SoloController = auto_free(SoloController.new())
	assert_float(_charge_from_in(solo, _unit(2, [], 0.0, 25), _unit(1, [], 8.0, 26))).is_equal_approx(8.0, 0.01)
	assert_float(_charge_from_in(solo, _unit(2, [], 0.0, 100), _unit(1, [], 9.5, 103))).is_equal_approx(9.5, 0.01)


func test_the_charge_distance_is_the_closest_edge_gap_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var solo: SoloController = auto_free(SoloController.new())
	# 25 mm + 26 mm bases: radii 1.004" together, so 8" between centres is 6.996" edge to edge.
	assert_float(_charge_from_in(solo, _unit(2, [], 0.0, 25), _unit(1, [], 8.0, 26))).is_equal_approx(6.996, 0.01)
	# 100 mm + 103 mm bases: 3.996" together, so 9.5" between centres is 5.504" edge to edge.
	assert_float(_charge_from_in(solo, _unit(2, [], 0.0, 100), _unit(1, [], 9.5, 103))).is_equal_approx(5.504, 0.01)


## Centres 8", edges 7": below the wave the table's melee read never sees the charge, so no -1.
func test_screened_charged_from_seven_inches_is_unpenalised_at_epoch_72() -> void:
	var info := _charge_hit_mod(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 8.0, 25, 26)
	assert_int(int(info["mod"])).is_equal(0)


## Centres 8", edges 7": from the wave the charge from 7" is over the 6" gate — -1 to hit, and the log
## note names the rule (rules-must-log).
func test_screened_charged_from_seven_inches_costs_the_hit_at_epoch_73() -> void:
	var info := _charge_hit_mod(AiActRecorder.EPOCH_73_V36, 8.0, 25, 26)
	assert_int(int(info["mod"])) \
		.override_failure_message("charged from 7\" edge to edge: Screened's -1 must fire on the 6\" gate") \
		.is_equal(-1)
	assert_str(str(info.get("note", ""))).contains("Screened")


## Centres 9.5", edges 5.5": no -1 at either epoch (72: the melee read is 0.0; 73: 5.5" is not over 6").
func test_screened_charged_from_five_and_a_half_inches_is_unpenalised_at_epoch_72() -> void:
	assert_int(int(_charge_hit_mod(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 9.5, 100, 103)["mod"])).is_equal(0)


func test_screened_charged_from_five_and_a_half_inches_is_unpenalised_at_epoch_73() -> void:
	assert_int(int(_charge_hit_mod(AiActRecorder.EPOCH_73_V36, 9.5, 100, 103)["mod"])).is_equal(0)


## Control: centres 7", edges 5" never fires.
func test_screened_charged_from_five_inches_is_unpenalised_at_epoch_72_and_at_epoch_73() -> void:
	assert_int(int(_charge_hit_mod(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 7.0, 50, 52)["mod"])).is_equal(0)
	assert_int(int(_charge_hit_mod(AiActRecorder.EPOCH_73_V36, 7.0, 50, 52)["mod"])).is_equal(0)


## The shooting leg keeps the entry's own 9": a shot from 7" stays unpenalised at 73.
func test_screened_shot_from_seven_inches_is_unpenalised_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main := _bare_main()
	var tgt := _unit(1, ["Screened"], 8.0, 26)
	assert_int(int(main._solo_hit_mod_info(_unit(2, [], 0.0, 25), tgt, 7.0, false)["mod"])).is_equal(0)
