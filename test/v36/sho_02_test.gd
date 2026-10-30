extends GdUnitTestSuite
## SHO-02 (0.3.15, rules 3.6): a moved Indirect shooter hits at its base quality — the 3.5
## "-1 after moving" is gone from `EPOCH_73_V36` on, and the "Indirect when Shooting" aura follows
## the same removal. `EPOCH_72_PLAYTEST_RULES` keeps today's -1. The dice seam itself lives in the
## volley paths; this suite pins the shared helper they call and the EV's epoch-blind reading.

const MainScript := preload("res://scripts/main.gd")

var _epoch0 := 0


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _unit(rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho02_target"
	u.unit_properties = {"player_id": 2, "name": "Target", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf"}
	var m := ModelInstance.new()
	m.is_alive = true
	m.node = auto_free(Node3D.new())
	add_child(m.node)
	u.models.append(m)
	return u


func _hit_info_at(epoch: int, target: GameUnit) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var main: Node3D = auto_free(MainScript.new())
	return main._solo_hit_mod_info(null, target, 12.0, false)


func _mod_at(epoch: int, moved: bool, penalty: int = 1) -> int:
	AiActRecorder.rules_epoch = epoch
	return AiCombatMath.indirect_hit_modifier(moved, penalty)


## OLD leg: at 72 the moved Indirect shot still takes the 3.5 -1 (the flipped pre-3.6 reading).
func test_a_moved_indirect_shooter_takes_the_minus_one_at_epoch_72() -> void:
	assert_int(_mod_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES, true)).is_equal(-1)
	assert_int(_mod_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES, true, 2)).is_equal(-2)
	assert_int(_mod_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES, false)).is_equal(0)


## NEW leg: at 73 the penalty is gone; the magnitude argument changes nothing.
func test_a_moved_indirect_shooter_has_no_penalty_at_epoch_73() -> void:
	assert_int(_mod_at(AiActRecorder.EPOCH_73_V36, true)).is_equal(0)
	assert_int(_mod_at(AiActRecorder.EPOCH_73_V36, true, 2)).is_equal(0)


## CONTROL: a shooter that held is unchanged at 73.
func test_a_held_indirect_shooter_is_unchanged_at_epoch_73() -> void:
	assert_int(_mod_at(AiActRecorder.EPOCH_73_V36, false)).is_equal(0)


## CONTROL: the table's to-hit breakdown names no Indirect moved line at 73, for an Indirect
## carrier and a plain one alike.
func test_the_hit_info_names_no_indirect_moved_line_at_epoch_73() -> void:
	for rules: Array in [["Indirect"], []]:
		var info := _hit_info_at(AiActRecorder.EPOCH_73_V36, _unit(rules))
		assert_int(int(info.get("mod", 0))).is_equal(0)
		assert_str(str(info.get("note", ""))).not_contains("Indirect moved")


## CONTROL: the EV never priced the moved -1, so both epochs value the same Indirect shot alike.
func test_the_ev_has_no_moved_indirect_penalty_at_epoch_73() -> void:
	var profile := {"range": 24, "attacks": 4, "ap": 0, "indirect": true}
	var att := {"quality": 4, "models": 1}
	var def := {"defense": 4, "tough": 1, "models": 5}
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var old_ev := AiEv.profile_ev(profile, att, def, 12.0, false)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var new_ev := AiEv.profile_ev(profile, att, def, 12.0, false)
	assert_float(new_ev).is_equal_approx(old_ev, 0.0001)
