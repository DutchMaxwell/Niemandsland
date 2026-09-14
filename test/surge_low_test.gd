extends GdUnitTestSuite
## RED (STANDALONE_SWEEP_F 2026-09-14, row `Great Sergeant`): the printed
## "5 or 6" Surge never paid on the table either — the alias stamp loop
## (ai_ev.gd's Surge coverage wave) reads `surge_low` only off `upgrades`
## carriers, so the plain auto-hit entry's printed `surge_low: 5` was dead
## data and the dice path paid the natural 6s alone. From the EPOCH_50
## SURGE-LOW gate the alias loop stamps the entry's printed low window
## (default 6) plus the ungated sentinel over_in (-1: the entry prints no
## distance gate, melee 0.0" included), and the dice consumer
## (main.gd:4532-4543) already reads both keys — one stamping, one truth.

func _unit_with(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t_1"
	u.unit_properties = {"player_id": 2, "name": "T", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _shoot_profile() -> Dictionary:
	return {"range": 24, "attacks": 2, "ap": 0, "rules": []}


func _melee_profile() -> Dictionary:
	return {"range": 0, "attacks": 2, "ap": 0, "rules": []}


func test_great_sergeant_stamps_its_printed_low_window_at_50_and_replays_below() -> void:
	var u := _unit_with(["Great Sergeant"], "aof", "ogres")
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = 50   # EPOCH_50_SURGE_LOW — the printed 5-6 reads
	var shoot := _shoot_profile()
	var melee := _melee_profile()
	AiEv.stamp_sergeant([shoot, melee], u)
	assert_bool(bool(shoot.get("surge", false))) \
		.override_failure_message("the alias lost its facet").is_true()
	assert_int(int(shoot.get("surge_low", 6))) \
		.override_failure_message("the printed surge_low never reached the shooting profile").is_equal(5)
	assert_float(float(shoot.get("surge_over_in", 0.0))) \
		.override_failure_message("the printed rule has no distance gate — the sentinel must open it").is_equal_approx(-1.0, 0.0001)
	assert_int(int(melee.get("surge_low", 6))) \
		.override_failure_message("the printed surge_low never reached the melee profile").is_equal(5)
	AiActRecorder.rules_epoch = 49   # the OLD leg: the corpus replay below the gate
	var shoot49 := _shoot_profile()
	var melee49 := _melee_profile()
	AiEv.stamp_sergeant([shoot49, melee49], u)
	assert_bool(bool(shoot49.get("surge", false))) \
		.override_failure_message("epoch 49 replays the plain facet").is_true()
	assert_int(int(shoot49.get("surge_low", 6))) \
		.override_failure_message("epoch 49 must replay the recorded 6s read").is_equal(6)
	assert_bool(shoot49.has("surge_over_in")) \
		.override_failure_message("epoch 49 must stamp no window").is_false()
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore


func test_an_alias_without_a_printed_low_keeps_the_sixes_at_50() -> void:
	# Brutal (aof/halflings) prints no `surge_low` — the default-6 read must keep
	# its 5s dead at the live epoch (the Boost reader's 5 default must not leak).
	var u := _unit_with(["Brutal"], "aof", "halflings")
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = 50
	var shoot := _shoot_profile()
	AiEv.stamp_sergeant([shoot], u)
	assert_bool(bool(shoot.get("surge", false))).is_true()
	assert_int(int(shoot.get("surge_low", 6))) \
		.override_failure_message("no printed low, no 5s (main.gd's default)").is_equal(6)
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore
