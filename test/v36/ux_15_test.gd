extends GdUnitTestSuite
## Rules 3.6 wave, row UX-15: a Reinforcement copy lands fully within 9" of a table edge (3.5: 12") and,
## from rules epoch 73, over 9" from every enemy model (3.5 named no enemy distance). The band is map
## data and reads the same at every epoch; only the enemy ring is gated on EPOCH_73_V36. The suite
## boots the real scene because the wiring (map -> strip, enemy bases -> blockers, log line) is the point.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# --- helpers -------------------------------------------------------------------------------

func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _carrier(count: int) -> GameUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = "Clan Rats"
	u.size = count
	u.quality = 4
	u.defense = 4
	u.base_size_round = 25
	u.base_width_mm = 25
	u.base_depth_mm = 25
	u.game_system = "gf"
	u.special_rules.assign(["Tough(1)", "Reinforcement"])
	var positions: Array = []
	for i in count:
		positions.append(Vector3(float(i) * 1.2 * INCH, 0.0, 0.0))
	var gu: GameUnit = _main.opr_army_manager.create_runtime_unit({
		"opr_unit": u, "faction_folder": "ratmen_clans",
	}, 1, positions, "spawn")
	assert_object(gu).is_not_null()
	return gu


## The enemy stands 6" in front of the owner's back-edge slot, the spot the automatic search prefers.
func _enemy_near_the_back_edge() -> GameUnit:
	var trect: Rect2 = _main._table_rect()
	var at := Vector3(trect.position.x + trect.size.x * 0.5, 0.0, trect.position.y + trect.size.y * 0.05 + 6.0 * INCH)
	var foe: GameUnit = E2EBoot.make_unit(_main, 2, "Foe", [at])
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	for m in foe.models:
		(m as ModelInstance).wounds_max = 1
		(m as ModelInstance).wounds_current = 1
	return foe


func _copy_of(original: GameUnit) -> GameUnit:
	for g in _main.opr_army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu != null and gu != original and str(gu.unit_properties.get("origin", "")) == "reinforcement":
			return gu
	return null


## Shaken carrier, enemy 6" from its back-edge slot, one round later the copy is due: returns it.
func _arrive_beside_an_enemy(epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var foe := _enemy_near_the_back_edge()
	var u := _carrier(3)
	u.is_shaken = true
	_main.solo_begin_reinforcement(u)
	await _main._reinforcement_arrivals(_main.opr_army_manager.current_round + 1)
	return {"copy": _copy_of(u), "foe": foe}


## The smallest edge-to-edge gap between any model of `a` and any model of `b`, in metres.
func _closest_gap(a: GameUnit, b: GameUnit) -> float:
	var best := INF
	for ma in a.get_alive_models():
		for mb in b.get_alive_models():
			var pa: Vector3 = (ma as ModelInstance).node.global_position
			var pb: Vector3 = (mb as ModelInstance).node.global_position
			var gap := Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)) \
				- SoloController.model_base_radius_m(ma as ModelInstance) \
				- SoloController.model_base_radius_m(mb as ModelInstance)
			best = minf(best, gap)
	return best


# === the band: map data, every epoch ==========================================================

func test_the_map_band_is_nine_inches_in_every_book_that_fields_reinforcement() -> void:
	for pair in [["gf", "ratmen_clans"], ["gf", "soul_snatcher_cults"], ["aof", "ratmen"], ["aof", "volcanic_dwarves"]]:
		var band = RulesRegistry.param(str(pair[0]), str(pair[1]), "Reinforcement", "within_in", -1)
		assert_float(float(band)) \
			.override_failure_message("%s/%s: Reinforcement band is %s, expected 9" % [pair[0], pair[1], str(band)]) \
			.is_equal(9.0)


func test_the_arrival_line_reads_the_nine_inch_band_from_the_map_at_epoch_72() -> void:
	var res: Dictionary = await _arrive_beside_an_enemy(72)
	assert_object(res["copy"]).is_not_null()
	assert_str(_log_text()).contains("within 9\" of a table edge")
	assert_str(_log_text()).not_contains("from every enemy")


# === the enemy ring: new at epoch 73, absent at 72 ============================================

func test_a_copy_may_land_beside_an_enemy_at_epoch_72() -> void:
	var res: Dictionary = await _arrive_beside_an_enemy(72)
	assert_object(res["copy"]).is_not_null()
	assert_float(_closest_gap(res["copy"], res["foe"])) \
		.override_failure_message("epoch 72 reads no enemy distance") \
		.is_less(9.0 * INCH)


func test_a_copy_lands_over_nine_inches_from_every_enemy_at_epoch_73() -> void:
	var res: Dictionary = await _arrive_beside_an_enemy(AiActRecorder.EPOCH_73_V36)
	assert_object(res["copy"]).is_not_null() \
		.override_failure_message("the copy still has to come back, on a slot further along the edge")
	assert_float(_closest_gap(res["copy"], res["foe"])) \
		.override_failure_message("a model stands inside the 9\" ring around the enemy") \
		.is_greater(9.0 * INCH)


func test_the_arrival_line_names_the_nine_inch_enemy_distance_at_epoch_73() -> void:
	var res: Dictionary = await _arrive_beside_an_enemy(AiActRecorder.EPOCH_73_V36)
	assert_object(res["copy"]).is_not_null()
	assert_str(_log_text()).contains("over 9\" from every enemy")
