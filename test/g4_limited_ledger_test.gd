extends GdUnitTestSuite
## G4-H-LIM — the act state the table hands to the core (and records) names the Limited weapons a unit
## has already fired. The table keeps that once-per-game ledger in `unit_properties["limited_used"]` and a
## spent weapon does not fire; the act state carried no such field, so the AI's search priced a second shot
## of a spent Limited weapon. The exporter (`AiActRecorder._ledger_of`) writes the names from EPOCH_73_V36;
## below it the export is byte-identical to before.
##
## The fired state is built the way the game builds it: a real weapon through `AiShooting.profiles_in_range`
## (the volley's profile builder), spent through `SoloController.mark_limited_used` (main.gd's own call).

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests: restore


func _pod() -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Disposable Assault Rocket-Pod"
	w.range_value = 15
	w.attacks = 1
	w.count = 3
	w.special_rules.append("AP(1)")
	w.special_rules.append("Limited")
	w.special_rules.append("Assault")
	return w


func _gators() -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "gators_2"
	u.unit_properties = {"player_id": 2, "name": "Gators", "game_system": "gf",
		"faction_folder": "saurian_starhosts"}
	return u


func _controller() -> SoloController:
	var mgr := OPRArmyManager.new()
	add_child(mgr)
	auto_free(mgr)
	var sc := SoloController.new()
	add_child(sc)
	sc.setup(mgr, null, null, 1, 2)
	return auto_free(sc)


## The unit fires its Limited pod the way main.gd does after the dice rolled.
func _fire_the_pod(u: GameUnit) -> void:
	var prof := AiShooting.profiles_in_range([_pod()], 15.0)[0] as Dictionary
	assert_bool(bool(prof.get("limited", false))).is_true()   # the live profile builder knows Limited
	_controller().mark_limited_used(u, prof)


func test_the_exported_state_names_the_limited_weapon_a_unit_fired() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _gators()
	_fire_the_pod(u)
	var ledger := AiActRecorder._ledger_of(u)
	assert_array(ledger.get("limited_used", [])) \
		.override_failure_message("G4-H-LIM: the act state does not name the spent Limited weapon, so the core prices it again.") \
		.contains_exactly(["Disposable Assault Rocket-Pod"])


func test_a_unit_that_has_not_fired_its_limited_weapon_exports_no_key() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(AiActRecorder._ledger_of(_gators()).has("limited_used")).is_false()


func test_below_epoch_73_the_export_is_unchanged() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	var u := _gators()
	_fire_the_pod(u)
	assert_bool(AiActRecorder._ledger_of(u).has("limited_used")).is_false()
