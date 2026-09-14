extends GdUnitTestSuite
## Sweep C 2026-09-14, row `Unstoppable in Melee` — the clamp half on the TABLE.
## The point-sim stamp (BattleSim._profiles_of) folds the name onto the MELEE
## imagination only, from the frozen EPOCH_35_UNSTOPPABLE_MELEE; the shooting
## imagination and every pre-35 epoch keep the name silent (only its
## Regeneration half, the Lacerate alias, fired there).

const IN2M := 0.0254


func _sim_unit(id: String, pid: int, rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "name": id, "quality": 4, "defense": 4,
		"special_rules": rules}
	var od := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 2
	var r := OPRApiClient.OPRWeapon.new()
	r.name = "Rifle"
	r.range_value = 24
	r.attacks = 1
	od.weapons = [w, r] as Array[OPRApiClient.OPRWeapon]
	u.source_type = "opr"
	u.source_data = od
	var m: ModelInstance = ModelInstance.new()
	m.unit = u
	m.is_alive = true
	m.node = auto_free(Node3D.new())
	add_child(m.node)
	m.node.global_position = Vector3.ZERO
	u.models.append(m)
	return u


func _capture(units: Array) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army)


## NEW leg: at the frozen gate the melee imagination carries the clamp flag on
## the carrier's melee profile; the SHOOTING imagination and a rule-less unit
## never do (melee-only scoping, the volley clamps keep the weapon flag).
func test_the_melee_imagination_clamps_from_epoch_35_and_the_volley_does_not() -> void:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_35_UNSTOPPABLE_MELEE
	var carrier := _sim_unit("Carrier", 1, ["Unstoppable in Melee"])
	var plain := _sim_unit("Plain", 1, [])
	var state := _capture([carrier, plain])
	var melee: Array = BattleSim._profiles_of(state["units"]["Carrier"], true)
	assert_bool(bool((melee[0] as Dictionary).get("unstoppable", false))).is_true()
	var volley: Array = BattleSim._profiles_of(state["units"]["Carrier"], false, 12.0)
	assert_bool(bool((volley[0] as Dictionary).get("unstoppable", false))).is_false()
	assert_bool(bool((BattleSim._profiles_of(state["units"]["Plain"], true)[0] as Dictionary) \
		.get("unstoppable", false))).is_false()
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore


## OLD leg: below the gate the name stays silent on the melee imagination too —
## every recorded game replays with the penalty landing.
func test_below_epoch_35_the_name_stays_silent_on_the_melee_imagination() -> void:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = 34   # the corpus replay epoch (EPOCH_34_UNSTOPPABLE_MARK)
	var carrier := _sim_unit("Carrier", 1, ["Unstoppable in Melee"])
	var state := _capture([carrier])
	var melee: Array = BattleSim._profiles_of(state["units"]["Carrier"], true)
	assert_bool(bool((melee[0] as Dictionary).get("unstoppable", false))).is_false()
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests — restore
