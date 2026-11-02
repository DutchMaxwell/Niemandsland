extends GdUnitTestSuite
## Rules 3.6, row SHO-10-fix: the TARGET-STATE conditions the save re-roll window can name
## (`above_half_strength`, `shaken_or_fatigued`, `near_terrain`) reached the Rust table price but
## never the GD one, so the GD twin priced every such window as if the state were false. These pin
## the GD price against the state the Rust table path passes (`dice.rs` `CondApTarget::of`).

const ATT := {"quality": 4, "models": 5}

const PROBE_BOOK := {"common": {
	"Probe Base": {"primitive": "Bane", "params": {"reroll_save_sixes": true}},
	"Probe Bane": {"primitive": "Bane", "params": {
		"condition": "above_half_strength", "reroll_save_low": 5, "upgrades": "Probe Base"}}}}


func before_test() -> void:
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func _bane(condition: String) -> Dictionary:
	return {"name": "Probe Gun", "attacks": 8, "ap": 0, "deadly": 0, "relentless": false,
		"blast": 0, "reliable": false, "surge": false, "rending": false, "bane": true,
		"thrust": false, "counter": false, "range": 24, "rules": [],
		"bane_condition": {"condition": condition}}


func _plain() -> Dictionary:
	var p := _bane("above_half_strength")
	p["bane"] = false
	p.erase("bane_condition")
	return p


func _rifle() -> Dictionary:
	var p := _bane("above_half_strength")
	p.erase("bane_condition")
	return p


func _ctx(state: Dictionary) -> Dictionary:
	var c := {"defense": 3, "tough": 1, "models": 5}
	c.merge(state)
	return c


func _price(baned: Dictionary, state: Dictionary) -> float:
	return AiEv.profile_ev(baned, ATT, _ctx(state), 12.0, false)


func _price_plain(state: Dictionary) -> float:
	return AiEv.profile_ev(_plain(), ATT, _ctx(state), 12.0, false)


func test_above_half_strength_opens_the_table_price() -> void:
	var baned := _bane("above_half_strength")
	assert_bool(_price(baned, {"above_half_strength": true}) > _price_plain({"above_half_strength": true})) \
		.override_failure_message("RED on main: above half strength prices like a fresh target").is_true()
	assert_float(_price(baned, {"above_half_strength": false})) \
		.is_equal_approx(_price_plain({"above_half_strength": false}), 0.0001)


func test_shaken_or_fatigued_opens_the_table_price() -> void:
	var baned := _bane("shaken_or_fatigued")
	assert_bool(_price(baned, {"shaken_or_fatigued": true}) > _price_plain({"shaken_or_fatigued": true})) \
		.override_failure_message("RED on main: Shaken/Fatigued prices like a fresh target").is_true()
	assert_float(_price(baned, {"shaken_or_fatigued": false})) \
		.is_equal_approx(_price_plain({"shaken_or_fatigued": false}), 0.0001)


func test_near_terrain_opens_the_table_price() -> void:
	var baned := _bane("near_terrain")
	assert_bool(_price(baned, {"near_terrain": true}) > _price_plain({"near_terrain": true})) \
		.override_failure_message("RED on main: a target by terrain prices like one in the open").is_true()
	assert_float(_price(baned, {"near_terrain": false})) \
		.is_equal_approx(_price_plain({"near_terrain": false}), 0.0001)


func test_no_state_keys_keeps_the_window_shut_as_before() -> void:
	var baned := _bane("above_half_strength")
	assert_float(_price(baned, {})) \
		.is_equal_approx(_price_plain({}), 0.0001)


func test_below_epoch_73_the_stamp_carries_no_condition() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = PROBE_BOOK.duplicate(true)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var u := GameUnit.new()
	u.unit_id = "u_sho10fix"
	u.unit_properties = {"player_id": 1, "name": "U", "quality": 4, "defense": 3,
		"special_rules": ["Probe Base", "Probe Bane"], "game_system": "gf", "faction_folder": ""}
	var rifle: Dictionary = AiEv.stamp_sergeant([_rifle()], u)[0]
	assert_bool(rifle.has("bane_condition")) \
		.override_failure_message("below 73 the window stays unconditional").is_false()
