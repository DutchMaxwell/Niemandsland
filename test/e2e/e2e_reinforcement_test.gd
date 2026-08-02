extends GdUnitTestSuite
## E2E — the RUNTIME UNIT FACTORY and the army-book rule "Reinforcement" (v3.5.3, byte-identical in
## all 12 books that field it): "When a unit where all models have this rule is Shaken or fully
## destroyed, you may remove it from the table as destroyed and place a new copy of it fully within
## 12" of any table edge at the beginning of the next round after Ambushers have been deployed. Units
## that deploy via Reinforcement can't seize or contest objectives on the round they deploy, and this
## rule doesn't apply to the new copy of the unit."
##
## WHY THIS SUITE IS E2E AND NOT UNIT LEVEL. Until this wave a unit could only be born during army
## IMPORT. Three things therefore had never been true for a unit created mid-game, and none of them
## can be proved without booting the real scene:
##   (a) the unit dock only ever rebuilt on the army_spawned signal, so a new unit had no card,
##   (b) the save serializes only DIRECT children of object_manager in the group "selectable" and
##       drops any model whose node lacks the "game_unit" meta — a half-built unit vanishes on load,
##   (c) the round-start alternation reads eligibility ONCE, so a unit that appears at the wrong
##       moment in the round-start sequence corrupts the whole round's activation order.
## Each of those is a test below, and each of them was RED before this wave.
##
## The pure halves — the refusal branches, the 12" strip geometry, the spot search, the copy's rule
## list — live in test/solo_controller_test.gd; here we prove the wiring.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _tmp_saves: Array = []


func before_test() -> void:
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
	for p in _tmp_saves:
		if FileAccess.file_exists(str(p)):
			DirAccess.remove_absolute(str(p))
	_tmp_saves.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# --- helpers -------------------------------------------------------------------------------

func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A minimal but REAL OPRUnit profile — the thing a runtime unit is actually built from. Carries a
## bought upgrade and an item grant so the "upgrades survive the copy" claim has something to bite on.
func _profile(unit_name: String, size: int, rules: Array) -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = unit_name
	u.size = size
	u.quality = 4
	u.defense = 4
	u.cost = 130
	u.base_size_round = 25
	u.base_width_mm = 25
	u.base_depth_mm = 25
	u.game_system = "gf"
	u.upgrades.assign(["Clan Backup"])
	u.item_grants = {"Combat Shield": ["Shielded"]}
	for r in rules:
		u.special_rules.append(str(r))
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rusty Blade"
	w.attacks = 2
	w.special_rules.assign(["AP(1)"])
	u.weapons.append(w)
	return u


func _row(count: int, at: Vector3) -> Array:
	var out: Array = []
	for i in count:
		out.append(at + Vector3(float(i) * 1.2 * INCH, 0.0, 0.0))
	return out


## A carrier standing on the table. Deliberately built through the runtime factory rather than the
## lightweight E2EBoot fixture: only a factory-built unit is a full citizen (models parented under
## object_manager, in the save's groups, with the metas), and half of this suite is exactly about
## what happens to such a unit across a save. Its origin stamp is "spawn" so _copy_of can still tell
## the returning Reinforcement copy apart from it.
func _carrier(unit_name: String, count: int, pid: int = 1, rules: Array = ["Tough(1)", "Reinforcement"]) -> GameUnit:
	var u: GameUnit = _main.opr_army_manager.create_runtime_unit({
		"opr_unit": _profile(unit_name, count, rules), "faction_folder": "ratmen_clans",
	}, pid, _row(count, Vector3(0.0, 0.0, 0.0)), "spawn")
	assert_object(u).is_not_null()
	return u


func _table_rect() -> Rect2:
	return _main._table_rect()


# === 1. THE FACTORY — a runtime unit is a FULL citizen ======================================
# The foundation everything else stands on: create_runtime_unit must set every single thing
# _spawn_unit and spawn_army set between them. Asserted field by field on purpose — a factory that
# gets 90% of this right produces a unit that looks fine and disappears on the next save.

func test_factory_builds_a_unit_with_every_field_meta_and_group() -> void:
	var mgr = _main.opr_army_manager
	var profile := _profile("Clan Rats", 3, ["Tough(1)"])
	var positions := _row(3, Vector3(0.3, 0.0, 0.3))

	var gu: GameUnit = mgr.create_runtime_unit({
		"opr_unit": profile, "faction_folder": "ratmen_clans", "display_suffix": " (2)",
	}, 1, positions, "reinforcement")

	assert_object(gu).is_not_null()
	# --- identity + registration
	assert_str(gu.unit_id).is_not_empty()
	assert_bool(mgr.game_units.has(gu.unit_id)).is_true() \
		.override_failure_message("not in game_units -> invisible to the dock, the save AND the activation order")
	assert_object(mgr.unit_to_game_unit.get(profile)).is_same(gu)
	assert_bool(mgr.unit_to_models.has(profile)).is_true()
	# --- unit_properties
	assert_int(int(gu.unit_properties["player_id"])).is_equal(1)
	assert_str(str(gu.unit_properties["faction_folder"])).is_equal("ratmen_clans")
	assert_str(str(gu.unit_properties["display_suffix"])).is_equal(" (2)")
	assert_str(str(gu.unit_properties["game_system"])).is_equal("gf")
	assert_str(str(gu.unit_properties["origin"])).is_equal("reinforcement")
	assert_int(int(gu.unit_properties["origin_round"])).is_equal(int(mgr.current_round))
	assert_int(int(gu.unit_properties["size"])).is_equal(3)
	# --- models: one ModelInstance per position, all wired both ways
	assert_int(gu.models.size()).is_equal(3)
	for i in 3:
		var mi := gu.models[i] as ModelInstance
		assert_object(mi).is_not_null()
		assert_object(mi.unit).is_same(gu)
		assert_int(mi.model_index).is_equal(i)
		var node := mi.node
		assert_object(node).is_not_null()
		# parent MUST be object_manager: the save walks its DIRECT children only
		assert_object(node.get_parent()).is_same(_main.object_manager) \
			.override_failure_message("model %d is not a direct child of object_manager -> the save skips it" % i)
		assert_bool(node is StaticBody3D).is_true()
		# the four groups the rest of the game keys on
		assert_bool(node.is_in_group("selectable")).is_true()
		assert_bool(node.is_in_group("miniature")).is_true()
		assert_bool(node.is_in_group("opr_unit")).is_true()
		assert_bool(node.is_in_group("unit")).is_true()
		# the metas save/load and the radial menu read
		assert_object(node.get_meta("model_instance")).is_same(mi)
		assert_object(node.get_meta("game_unit")).is_same(gu)
		assert_int(int(node.get_meta("model_index"))).is_equal(i)
		assert_object(node.get_meta("opr_unit")).is_same(profile)
		assert_int(int(node.get_meta("opr_player_id"))).is_equal(1)
		assert_int(int(node.get_meta("network_id"))).is_greater(0)
		# a collider, or measuring and selection raycasts pass straight through it
		var has_shape := false
		for c in node.get_children():
			if c is CollisionShape3D:
				has_shape = true
		assert_bool(has_shape).is_true().override_failure_message("model %d has no CollisionShape3D" % i)
		# it stands where it was asked to stand
		assert_float(node.global_position.distance_to(positions[i])).is_less(0.001)
		# Sort Table sends it back HERE, not to the world origin
		assert_float(mi.import_position.distance_to(Vector3(positions[i].x, 0.0, positions[i].z))).is_less(0.001)
	# --- network ids are unique across the unit
	var seen := {}
	for mi2 in gu.models:
		var nid := int((mi2 as ModelInstance).node.get_meta("network_id"))
		assert_bool(seen.has(nid)).is_false().override_failure_message("duplicate network_id %d" % nid)
		seen[nid] = true
	await E2EBoot.settle(get_tree())


func test_factory_refuses_to_build_half_a_unit() -> void:
	var mgr = _main.opr_army_manager
	assert_object(mgr.create_runtime_unit({}, 1, _row(2, Vector3.ZERO), "spawn")).is_null()
	assert_object(mgr.create_runtime_unit({"opr_unit": _profile("X", 2, [])}, 1, [], "spawn")).is_null()
	await E2EBoot.settle(get_tree())


func test_factory_takes_fewer_positions_than_the_unit_size() -> void:
	# The Platznot path: the caller placed what fit and the factory must build exactly that.
	var mgr = _main.opr_army_manager
	var profile := _profile("Clan Rats", 5, [])
	profile.size = 2
	var gu: GameUnit = mgr.create_runtime_unit({"opr_unit": profile}, 1, _row(2, Vector3(0.5, 0.0, 0.5)), "reinforcement")
	assert_int(gu.models.size()).is_equal(2)
	await E2EBoot.settle(get_tree())


# === 2. THE UNIT DOCK — was RED: rebuild() only ever ran on army_spawned ====================

func test_a_runtime_unit_gets_a_card_in_the_unit_dock() -> void:
	if _main.unit_dock == null:
		return
	_main.unit_dock.rebuild()
	var before: int = _main.unit_dock._cards.size()
	var gu: GameUnit = _main.opr_army_manager.create_runtime_unit(
		{"opr_unit": _profile("Clan Rats", 2, [])}, 1, _row(2, Vector3(0.4, 0.0, 0.4)), "reinforcement")
	await _runner.simulate_frames(2)
	assert_bool(_main.unit_dock._cards.has(gu.unit_id)).is_true() \
		.override_failure_message("the dock has no card for the runtime unit — rebuild() never ran for it")
	assert_int(_main.unit_dock._cards.size()).is_equal(before + 1)
	await E2EBoot.settle(get_tree())


# === 3. SAVE + LOAD — was RED: a half-built unit is silently dropped ========================

func test_a_runtime_unit_survives_save_and_load_with_its_model_positions() -> void:
	var mgr = _main.opr_army_manager
	var positions := _row(3, Vector3(0.25, 0.0, -0.35))
	var gu: GameUnit = mgr.create_runtime_unit({
		"opr_unit": _profile("Clan Rats", 3, ["Tough(1)"]), "faction_folder": "ratmen_clans",
	}, 1, positions, "reinforcement")
	var uid: String = gu.unit_id
	await _runner.simulate_frames(2)

	var path := "user://e2e_reinforcement_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)

	# The save file itself must carry the unit — proving it was not dropped at serialize time.
	var raw: String = FileAccess.get_file_as_string(path)
	assert_str(raw).contains(uid).override_failure_message("the runtime unit is not in the save file at all")

	await _main.save_manager.load_game(path)
	await _runner.simulate_frames(4)

	var loaded: GameUnit = mgr.game_units.get(uid)
	assert_object(loaded).is_not_null().override_failure_message("the runtime unit did not come back from the save")
	assert_int(loaded.models.size()).is_equal(3)
	assert_str(str(loaded.unit_properties.get("origin", ""))).is_equal("reinforcement") \
		.override_failure_message("the provenance stamp did not survive the round trip")
	for i in 3:
		var node: Node3D = (loaded.models[i] as ModelInstance).node
		assert_object(node).is_not_null().override_failure_message("model %d has no node after load" % i)
		assert_float(Vector2(node.global_position.x, node.global_position.z)
			.distance_to(Vector2(positions[i].x, positions[i].z))).is_less(0.01) \
			.override_failure_message("model %d came back at the wrong spot" % i)
	await E2EBoot.settle(get_tree())


# === 4. THE OFFER — "IS Shaken", the joined hero, and the copy losing the rule ==============

func test_the_offer_stands_for_as_long_as_the_unit_is_shaken() -> void:
	var u := _carrier("Clan Rats", 3)
	u.is_shaken = false
	_main.solo_begin_reinforcement(u)
	assert_int(SoloController.reinforcement_due_round(u)).is_equal(-1)
	assert_str(_log_text()).contains("neither Shaken nor destroyed")

	# Still Shaken two log lines later: the offer is not a one-frame window on "becomes Shaken".
	u.is_shaken = true
	_main.solo_begin_reinforcement(u)
	assert_int(SoloController.reinforcement_due_round(u)) \
		.is_equal(SoloController.reinforcement_arrival_round(_main.opr_army_manager.current_round))
	assert_str(_log_text()).contains("is removed from the table as destroyed while Shaken")
	assert_int(u.get_alive_count()).is_equal(0) \
		.override_failure_message("the unit is still standing — 'remove it from the table as destroyed' did not happen")
	await E2EBoot.settle(get_tree())


func test_a_joined_hero_without_the_rule_blocks_it_out_loud() -> void:
	var u := _carrier("Clan Rats", 3)
	u.is_shaken = true
	var hero := _reg(E2EBoot.make_unit(_main, 1, "Warlord", [Vector3(0.1, 0.0, 0.0)]))
	hero.unit_properties["special_rules"] = ["Hero"]
	EquipmentDistributor.attach_hero_to_unit(hero, u)

	_main.solo_begin_reinforcement(u)

	assert_int(SoloController.reinforcement_due_round(u)).is_equal(-1) \
		.override_failure_message("the rule fired although a joined hero does not carry it")
	assert_str(_log_text()).contains("all models have this rule") \
		.override_failure_message("blocked SILENTLY — a rule that refuses without a line reads as broken")
	assert_str(_log_text()).contains("Warlord")
	await E2EBoot.settle(get_tree())


func test_the_returning_copy_really_loses_the_rule() -> void:
	var u := _carrier("Clan Rats", 3)
	u.is_shaken = true
	_main.solo_begin_reinforcement(u)
	var round_no: int = _main.opr_army_manager.current_round
	await _main._reinforcement_arrivals(round_no + 1)

	var copy: GameUnit = _copy_of(u)
	assert_object(copy).is_not_null()
	# Gone from the live rule list AND from the profile the unit card reads — not a hidden flag.
	assert_bool(SoloController.has_exact_rule(copy, "Reinforcement")).is_false() \
		.override_failure_message("the copy still has Reinforcement — it could reinforce for ever")
	assert_array(copy.unit_properties["special_rules"]).not_contains(["Reinforcement"])
	var src := copy.source_data as OPRApiClient.OPRUnit
	assert_array(src.special_rules).not_contains(["Reinforcement"])
	# The bought upgrade DID come back.
	assert_array(src.upgrades).contains(["Clan Backup"])
	assert_str(_log_text()).contains("does not have Reinforcement")
	# ...and the original's own profile is untouched: the copy was independent.
	assert_array((u.source_data as OPRApiClient.OPRUnit).special_rules).contains(["Reinforcement"])
	await E2EBoot.settle(get_tree())


## The unit created by the last arrival (origin stamp), or null.
func _copy_of(original: GameUnit) -> GameUnit:
	for g in _main.opr_army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu != null and gu != original and str(gu.unit_properties.get("origin", "")) == "reinforcement":
			return gu
	return null


# === 5. THE ARRIVAL — the 12" strip, enemies allowed, the objective lock, the activation ====

func test_the_copy_lands_fully_within_twelve_inches_of_a_table_edge() -> void:
	var u := _carrier("Clan Rats", 3)
	u.is_shaken = true
	_main.solo_begin_reinforcement(u)
	await _main._reinforcement_arrivals(_main.opr_army_manager.current_round + 1)

	var copy: GameUnit = _copy_of(u)
	assert_object(copy).is_not_null()
	var trect := _table_rect()
	var margin: float = SoloController.REINFORCEMENT_EDGE_IN * INCH
	for m in copy.get_alive_models():
		var mi := m as ModelInstance
		var r: float = SoloController.model_base_radius_m(mi)
		assert_bool(SoloController.reinforcement_spot_in_strip(mi.node.global_position, r, trect, margin)).is_true() \
			.override_failure_message("a model landed outside the 12\" edge strip at %s" % str(mi.node.global_position))
	await E2EBoot.settle(get_tree())


func test_every_table_edge_is_legal_including_the_enemys() -> void:
	# The book names a minimum distance from enemies for Ambush and deliberately does not here. So a
	# copy may land right under the enemy's nose, and the strip search must not invent a no-go ring.
	var trect := _table_rect()
	var margin: float = SoloController.REINFORCEMENT_EDGE_IN * INCH
	var r := 0.016
	var far_edge_spot := Vector3(0.0, 0.0, trect.end.y - r - 0.001)
	assert_bool(SoloController.reinforcement_spot_in_strip(far_edge_spot, r, trect, margin)).is_true() \
		.override_failure_message("the enemy's own table edge was refused")
	# An enemy standing 2" away changes nothing: he is not a blocker unless the bases would overlap.
	var enemy_near := Vector3(2.0 * INCH, 0.0, trect.end.y - r - 0.001)
	var spots: Array = SoloController.reinforcement_spots([r], trect, margin,
		[{"p": enemy_near, "r": r}], far_edge_spot, INCH)
	assert_int(spots.size()).is_equal(1)
	assert_float(Vector2(spots[0].x, spots[0].z).distance_to(Vector2(enemy_near.x, enemy_near.z))) \
		.is_greater(2.0 * r - 0.0001)


func test_the_arriving_copy_cannot_seize_but_does_activate() -> void:
	var u := _carrier("Clan Rats", 3)
	u.is_shaken = true
	_main.solo_begin_reinforcement(u)
	var arrival_round: int = _main.opr_army_manager.current_round + 1
	_main.opr_army_manager.current_round = arrival_round
	await _main._reinforcement_arrivals(arrival_round)

	var copy: GameUnit = _copy_of(u)
	assert_object(copy).is_not_null()
	# The objective lock reuses the Ambush stamp, so _solo_auto_seize's existing gate covers it.
	assert_int(int(copy.unit_properties.get("ambush_arrived_round", -1))).is_equal(arrival_round)
	var infos: Array = [{"player": 1, "shaken": false, "ambush_locked": true, "aircraft": false,
		"positions": [Vector3.ZERO], "radii": [0.016]}]
	var res: Dictionary = SoloController.seize_objectives(infos, [Vector3.ZERO], [0])
	assert_int(int((res.get("owners", [0]) as Array)[0])).is_equal(0) \
		.override_failure_message("the arriving copy seized an objective in its arrival round")
	# ...but it counts for this round's alternation exactly like an Ambush arrival.
	assert_bool(_main.solo_controller.is_eligible(copy)).is_true() \
		.override_failure_message("the copy arrived and cannot act — it must activate normally")
	assert_str(_log_text()).contains("cannot seize or contest objectives this round")
	await E2EBoot.settle(get_tree())


# === 6. PLATZNOT — place what fits, forfeit the rest, say so ================================

func test_a_crowded_edge_places_what_fits_and_forfeits_the_rest_with_a_line() -> void:
	var u := _carrier("Clan Rats", 4)
	u.is_shaken = true
	_main.solo_begin_reinforcement(u)
	# Blanket the whole strip with standing enemies so only a couple of gaps are left.
	var trect := _table_rect()
	var margin: float = SoloController.REINFORCEMENT_EDGE_IN * INCH
	var wall: Array = []
	var x: float = trect.position.x
	while x <= trect.end.x:
		var z: float = trect.position.y
		while z <= trect.end.y:
			if SoloController.reinforcement_spot_in_strip(Vector3(x, 0.0, z), 0.016, trect, margin):
				wall.append(Vector3(x, 0.0, z))
			z += 0.9 * INCH
		x += 0.9 * INCH
	var blockers := _reg(E2EBoot.make_unit(_main, 2, "Wall", wall))
	for m in blockers.models:
		(m as ModelInstance).wounds_max = 1
		(m as ModelInstance).wounds_current = 1

	await _main._reinforcement_arrivals(_main.opr_army_manager.current_round + 1)

	var copy: GameUnit = _copy_of(u)
	var text := _log_text()
	if copy == null:
		# Not one model fit anywhere: then the promise must be KEPT for a later round, out loud.
		assert_str(text).contains("no free spot within 12\"")
		assert_int(SoloController.reinforcement_due_round(u)).is_greater(0) \
			.override_failure_message("the promise evaporated instead of waiting for a freer round")
	else:
		assert_int(copy.models.size()).is_less(4) \
			.override_failure_message("the crowded strip somehow fit the whole unit — the fixture is not crowded")
		assert_str(text).contains("forfeited") \
			.override_failure_message("models were forfeited SILENTLY")
	await E2EBoot.settle(get_tree())


# === 7. THE ALTERNATION — the round-start ordering race =====================================

func test_the_arrival_beat_runs_inside_round_start_before_eligibility_is_read() -> void:
	# The race the Ambush beat already solved by construction (main.gd:1846-1854): the round-start
	# sequence is AWAITED so every arrival is on the table before the one-shot human/AI eligibility
	# read. A copy that arrived after that read would be missing from the whole round's alternation.
	var u := _carrier("Clan Rats", 3, 2)          # NACHTMAHR's own unit
	u.is_shaken = true
	_main.solo_begin_reinforcement(u)
	var next_round: int = _main.opr_army_manager.current_round + 1
	_main.opr_army_manager.current_round = next_round

	var before: int = _main.solo_controller.eligible_ai_units().size()
	await _main._solo_round_start(next_round)
	var after: int = _main.solo_controller.eligible_ai_units().size()

	var copy: GameUnit = _copy_of(u)
	assert_object(copy).is_not_null().override_failure_message("the round-start beat never ran the arrival")
	assert_int(after).is_equal(before + 1) \
		.override_failure_message("the copy is on the table but not eligible — the alternation would skip it all round")
	assert_bool(_main.solo_controller.eligible_ai_units().has(copy)).is_true()
	await E2EBoot.settle(get_tree())


func test_a_promise_survives_a_save_taken_before_the_copy_arrives() -> void:
	# The pending state rides in unit_properties on purpose, so it needs no schema of its own.
	var u := _carrier("Clan Rats", 3)
	u.is_shaken = true
	_main.solo_begin_reinforcement(u)
	var due: int = SoloController.reinforcement_due_round(u)
	assert_int(due).is_greater(0)

	var path := "user://e2e_reinforcement_promise_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	await _main.save_manager.load_game(path)
	await _runner.simulate_frames(4)

	var loaded: GameUnit = _main.opr_army_manager.game_units.get(u.unit_id)
	assert_object(loaded).is_not_null()
	assert_int(SoloController.reinforcement_due_round(loaded)).is_equal(due) \
		.override_failure_message("the promised copy was forgotten across the save")
	await E2EBoot.settle(get_tree())
