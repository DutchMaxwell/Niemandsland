extends GdUnitTestSuite
## E2E — NML-937: the five registry knobs that NO GDScript read, driven on the REAL scenes/main.tscn.
##
## WHY THIS SUITE EXISTS. `hits_per_wound`, `dice_count`, `min_enemy_dist_in`, `army_cap_fraction`
## and `defense_per_two` sit in the emitted mechanics maps (assets/solo/rules_mechanics_*.json) and
## were read by nobody — so whether the five rules they describe played by their v3.5.3 wording was
## an UNTESTED HYPOTHESIS. Three of them turned out to be right by hardcoding (Retaliate already
## scaled per wound, Infiltrate already used 3", Second Wind already capped at a third) and two
## turned out to be WRONG (a boosted blink placed 1D3" instead of 2D3"; Defensive Growth granted NO
## Defense at all, because the reader only knew the older `defense_per_marker` shape). Every knob is
## wired to the registry now — the registry is the truth — and every claim below is pinned here.
##
## THE FIVE CLAIMS UNDER TEST (v3.5.3 wording):
##   1. Retaliate(X)     "the attacker takes X hits PER WOUND TAKEN" — and the wounds are counted
##                       per CHAIN MEMBER (NML-241: the unit-level gate over-triggered on a joined
##                       hero's wounds and never fired for a hero's own Retaliate).
##   2. Rapid Blink Boost / Wave-Step Boost — placement within 2D3", not a flat D3".
##   3. Infiltrate       "may be deployed anywhere over 3\" away from enemy units".
##   4. Inquisitorial Agent / Martial Prowess — a SECOND activation for up to one THIRD of the
##                       carriers per round (the older books said half).
##   5. Defensive Growth — max 4 markers, +1 Defense per TWO markers, one marker at the start of
##                       each round, and Shaken BLOCKS the marker instead of clearing the pile.
##
## WHAT IS REAL vs CONSTRUCTED. Real: main.tscn with its real _ready(), the real OPRArmyManager,
## the real SoloController, the real wound landing, the real save batch, the real battle log, and
## the REAL emitted mechanics maps (book-true faction slugs — human_inquisition, alien_hives,
## elven_jesters …). Constructed: the GameUnits and their model nodes, plus three deliberately
## SYNTHETIC maps where the point is that a CHANGED registry value changes the game (the flip that
## proves the number is read rather than hardcoded).
##
## No assertion sits behind a dice roll: every number below is placement, state or arithmetic, and
## the one save batch that rolls is asserted on its LOG LINE, which is written before any die.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TRAY := Vector3(5.0, 0.0, 0.0)   # far outside any table rect — the reserve tray side

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	# Batch dice: _solo_tray_roll draws faces from the RNG instead of awaiting the physics tray,
	# which headless would never settle.
	_main._solo_batch = true


func after_test() -> void:
	RulesRegistry.reset_cache()   # the synthetic maps never outlive their test
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === fixture helpers ==========================================================================

func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## `models` models in a row, registered, with the model indices the wound landing needs.
func _unit(pid: int, unit_name: String, faction: String, rules: Array, models: int = 2,
		at: Vector3 = Vector3(0.2, 0.0, 0.2)) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := _reg(E2EBoot.make_unit(_main, pid, unit_name, positions))
	for i in range(u.models.size()):
		(u.models[i] as ModelInstance).model_index = i
	u.unit_properties["special_rules"] = rules
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	return u


## A joined hero with Tough(3), so the wound landing's spill has somewhere to go.
func _joined_hero(host: GameUnit, hero_name: String, faction: String, rules: Array) -> GameUnit:
	var h := _unit(int(host.unit_properties.get("player_id", 1)), hero_name, faction, rules, 1,
		Vector3(0.4, 0.0, 0.2))
	var m := h.models[0] as ModelInstance
	m.wounds_max = 3
	m.wounds_current = 3
	h.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [h]
	return h


## A synthetic gf map for `faction` — the flip seam: the SAME code with a DIFFERENT registry value.
func _inject_gf_map(faction: String, entries: Dictionary) -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {faction: entries}, "common": {}}


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _count(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


## First defense part's bonus, 0 when the list is empty — a FAILED gdUnit assert does not stop the
## test body, so a red run must not crash the whole suite on an index that is legitimately missing.
func _bonus_of(parts: Array) -> int:
	return 0 if parts.is_empty() else int((parts[0] as Dictionary)["bonus"])


# === 1. Retaliate — hits_per_wound, per chain member ==========================================

## The v3.5.3 scale itself: X hits PER WOUND TAKEN. Two wounds on a Retaliate(3) carrier are six
## hits, not three — and the registry's `hits_per_wound: "X"` is what says "X = the rule's rating".
## The wounds are landed by the REAL wound landing, so the tally reads real model state.
func test_retaliate_throws_x_hits_for_every_wound_taken() -> void:
	var squad := _unit(1, "Klauenbrut", "alien_hives", ["Retaliate(3)"], 3)
	assert_bool(RulesRegistry.unit_rule_active(squad, "Retaliate")) \
		.override_failure_message("fixture: the emitted gf map must field Retaliate for alien_hives") \
		.is_true()
	assert_str(str(RulesRegistry.unit_param(squad, "Retaliate", "hits_per_wound", ""))) \
		.override_failure_message("fixture: the knob under test must exist in the emitted map") \
		.is_equal("X")

	var pools: Array = _main._solo_wound_pools(squad)
	await _main._solo_apply_wounds(squad, 2)

	var rt: Dictionary = _main._solo_retaliate_hits(pools)
	assert_int(int(rt["hits"])) \
		.override_failure_message("v3.5.3 scales PER WOUND: 2 wounds × Retaliate(3) = 6 hits, got %d" % int(rt["hits"])) \
		.is_equal(6)
	assert_str(str(rt["detail"])) \
		.override_failure_message("rules-must-log: the log line must show WHOSE wounds bought the hits") \
		.is_equal("Klauenbrut: 2 wounds × 3")
	# One wound is one trigger — the same carrier, a smaller tally.
	var pools2: Array = _main._solo_wound_pools(squad)
	await _main._solo_apply_wounds(squad, 1)
	assert_int(int(_main._solo_retaliate_hits(pools2)["hits"])).is_equal(3)
	# Nothing taken, nothing thrown back (the rule is reactive).
	assert_int(int(_main._solo_retaliate_hits(_main._solo_wound_pools(squad))["hits"])).is_equal(0)
	await E2EBoot.settle(get_tree())


## The knob is READ, not derived from the rating: a book that ever says "2 hits per wound" on a
## Retaliate(3) profile gets 2, not 3. (Before the wiring the rating alone decided — this case is
## the one a hardcoded reader can never satisfy.)
func test_a_numeric_hits_per_wound_beats_the_rules_rating() -> void:
	_inject_gf_map("testfac", {"Retaliate": {"primitive": "Retaliate",
		"params": {"rating": "X", "hits_per_wound": 2}}})
	var squad := _unit(1, "Prüfstand", "testfac", ["Retaliate(3)"], 3)
	var pools: Array = _main._solo_wound_pools(squad)
	await _main._solo_apply_wounds(squad, 2)
	assert_int(int(_main._solo_retaliate_hits(pools)["hits"])) \
		.override_failure_message("the registry's hits_per_wound (2) must win over the rating (3)") \
		.is_equal(4)
	await E2EBoot.settle(get_tree())


## NML-241 — the OVER-trigger. A joined hero without Retaliate soaks two wounds inside a Retaliate
## squad: those two wounds belong to a NON-carrier and must buy nothing. The wound landing is the
## real one (own models first, the hero last), so the spill is production behaviour, not a fixture.
func test_a_non_carrier_heros_wounds_do_not_feed_the_squads_retaliate() -> void:
	var squad := _unit(1, "Klauenbrut", "alien_hives", ["Retaliate(3)"], 2)
	var hero := _joined_hero(squad, "Brutvater", "alien_hives", ["Hero"])
	var pools: Array = _main._solo_wound_pools(squad)
	assert_int(pools.size()) \
		.override_failure_message("fixture: the chain must contain BOTH members, or nothing is mixed") \
		.is_equal(2)

	await _main._solo_apply_wounds(squad, 4)   # 2 kill the squad, 2 spill into the Tough(3) hero

	assert_int(_main._solo_unit_wound_pool(squad)) \
		.override_failure_message("fixture: the squad must be the one that emptied first").is_equal(0)
	assert_int(_main._solo_unit_wound_pool(hero)) \
		.override_failure_message("fixture: exactly 2 wounds must have spilled onto the hero").is_equal(1)
	var rt: Dictionary = _main._solo_retaliate_hits(pools)
	assert_int(int(rt["hits"])) \
		.override_failure_message("only the CARRIER's 2 wounds may count: 2 × 3 = 6 (the chain took 4)") \
		.is_equal(6)
	assert_str(str(rt["detail"])).is_equal("Klauenbrut: 2 wounds × 3")
	await E2EBoot.settle(get_tree())


## NML-241 — the UNDER-trigger, the same defect from the other side: a Retaliate HERO joined to a
## plain squad used to lash back never, because the gate asked the squad. His own wounds now answer.
func test_a_retaliate_hero_in_a_plain_squad_lashes_back_for_his_own_wounds() -> void:
	var squad := _unit(1, "Wachtrupp", "alien_hives", [], 2)
	var hero := _joined_hero(squad, "Klauenherr", "alien_hives", ["Hero", "Retaliate(2)"])
	assert_bool(RulesRegistry.unit_rule_active(squad, "Retaliate")) \
		.override_failure_message("fixture: the SQUAD must not carry the rule, or this proves nothing") \
		.is_false()
	var pools: Array = _main._solo_wound_pools(squad)
	await _main._solo_apply_wounds(squad, 4)

	var rt: Dictionary = _main._solo_retaliate_hits(pools)
	assert_int(int(rt["hits"])) \
		.override_failure_message("the hero's own 2 wounds × Retaliate(2) = 4 hits") \
		.is_equal(4)
	assert_str(str(rt["detail"])).contains("Klauenherr: 2 wounds × 2")
	assert_bool(hero.get_alive_count() > 0) \
		.override_failure_message("fixture: the hero must survive, or he took a different number of wounds") \
		.is_true()
	await E2EBoot.settle(get_tree())


# === 2. Rapid Blink Boost — dice_count ========================================================

## The pure seam: how many D3 a Bounding-family placement rolls. `dice_count` (GF/GFF) and the
## "NdM" shape in `place_die` (AoF) are both DATA; an entry that names neither keeps the single die.
func test_bounding_dice_count_reads_both_registry_shapes() -> void:
	assert_int(SoloController.bounding_dice_count({"dice_count": 2})).is_equal(2)
	assert_int(SoloController.bounding_dice_count({"place_die": "2d3"})).is_equal(2)
	assert_int(SoloController.bounding_dice_count({"place_d3_plus": 1})).is_equal(1)
	assert_int(SoloController.bounding_dice_count({})).is_equal(1)
	assert_int(SoloController.bounding_dice_count({"dice_count": 0})).is_equal(1)
	# The emitted maps really do carry the v3.5.3 upgrade — in both encodings.
	assert_int(int(RulesRegistry.param("gf", "elven_jesters", "Rapid Blink Boost", "dice_count", 0))).is_equal(2)
	assert_str(str(RulesRegistry.param("aof", "deep_sea_elves", "Wave-Step Boost", "place_die", ""))).is_equal("2d3")


## The rule in the real activation: a boosted blinker rolls TWO dice, and the note says 2D3. The
## controller's own seeded RNG makes the number exact — a one-die reader can only produce the first
## draw, which for this seed is a different number.
func test_a_boosted_blink_rolls_two_d3_and_says_so() -> void:
	_unit(1, "Grenzer", "alien_hives", [], 1, Vector3(-0.3, 0.0, 0.0))   # something to walk toward
	var jester := _unit(2, "Springer", "elven_jesters", ["Rapid Blink", "Rapid Blink Boost"], 2,
		Vector3(0.3, 0.0, 0.0))
	var solo = _main.solo_controller
	solo._rng.seed = 4242
	var ref := RandomNumberGenerator.new()
	ref.seed = 4242
	var d1: int = ref.randi_range(1, 3)
	var d2: int = ref.randi_range(1, 3)
	assert_int(d1 + d2) \
		.override_failure_message("fixture: pick a seed where two dice differ from one") \
		.is_not_equal(d1)

	var report: Dictionary = solo._act(jester)

	var notes: Array = report.get("rule_notes", [])
	var joined := ""
	for n in notes:
		# G5 (NML-963): notes are {text, travels}; read the text either way.
		joined += (str((n as Dictionary).get("text", "")) if n is Dictionary else str(n)) + "\n"
	assert_str(joined) \
		.override_failure_message("the boosted blink must place within 2D3\", not D3\":\n%s" % joined) \
		.contains("Rapid Blink Boost: rolled %d\" of 2D3\"" % (d1 + d2))
	await E2EBoot.settle(get_tree())


# === 3. Infiltrate — min_enemy_dist_in ========================================================

## The ring is DATA. Infiltrate arrives over 3" from the enemy, plain Ambush over 9" — and a map
## that says 5" moves the ring to 5" (the flip a hardcoded constant cannot follow).
func test_the_infiltrate_arrival_ring_comes_from_the_registry() -> void:
	var solo = _main.solo_controller
	var inf := _unit(2, "Schleicher", "alien_hives", ["Infiltrate"], 2, TRAY)
	var amb := _unit(2, "Springer", "alien_hives", ["Ambush"], 2, TRAY)
	assert_float(solo._reserve_min_enemy_dist_m(inf)) \
		.override_failure_message("v3.5.3 Infiltrate: over 3\" from enemy units") \
		.is_equal_approx(3.0 * INCH, 0.0005)
	assert_float(solo._reserve_min_enemy_dist_m(amb)) \
		.override_failure_message("plain Ambush keeps the core rules' 9\"") \
		.is_equal_approx(9.0 * INCH, 0.0005)

	_inject_gf_map("testfac", {"Infiltrate": {"primitive": "Infiltrate",
		"params": {"counts_as": "Ambush", "min_enemy_dist_in": 5.0}}})
	var far := _unit(2, "Fernschleicher", "testfac", ["Infiltrate"], 2, TRAY)
	assert_float(solo._reserve_min_enemy_dist_m(far)) \
		.override_failure_message("the ring must follow the registry, not the constant") \
		.is_equal_approx(5.0 * INCH, 0.0005)


## The same ring in the REAL arrival: an Infiltrate reserve lands inside the 9" an Ambush unit could
## never enter, and still outside its own 3". Its ROT case is the plain Ambusher, pushed out past 9"
## by the identical search on the identical table.
func test_an_infiltrator_arrives_inside_nine_inches_but_outside_three() -> void:
	var solo = _main.solo_controller
	var enemy := _unit(1, "Wachposten", "alien_hives", [], 1, Vector3.ZERO)
	var inf := _unit(2, "Schleicher", "alien_hives", ["Infiltrate"], 2, TRAY)
	inf.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [inf]
	solo._deploy_objectives = [Vector2.ZERO]   # pull the search straight at the enemy

	var arrived: GameUnit = solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 2, [])
	assert_object(arrived).is_equal(inf)
	var gap_in: float = _gap_in(inf)
	assert_float(gap_in) \
		.override_failure_message("the 3\" ring must let the infiltrator inside the Ambush 9\" (landed %.1f\")" % gap_in) \
		.is_less(9.0)
	assert_float(gap_in) \
		.override_failure_message("…but never inside its own 3\" (landed %.1f\")" % gap_in) \
		.is_greater_equal(3.0)

	# ROT case: the identical search for a PLAIN ambusher stays outside 9".
	var amb := _unit(2, "Springer", "alien_hives", ["Ambush"], 2, TRAY)
	amb.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [amb]
	var arrived2: GameUnit = solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 2, [])
	assert_object(arrived2).is_equal(amb)
	assert_float(_gap_in(amb)) \
		.override_failure_message("plain Ambush must stay outside 9\" — the ring was applied to the wrong unit") \
		.is_greater(9.0)


## The whole 4x4 ft table as the arrival zone (the same rect main builds from table.table_size).
func _zone() -> Rect2:
	return Rect2(Vector2(-0.61, -0.61), Vector2(1.22, 1.22))


## Enemy no-go entries exactly as _solo_ambush_enemy_positions builds them (per model, edge-true).
func _enemy_entries(enemy: GameUnit) -> Array:
	var out: Array = []
	for m in enemy.get_alive_models():
		var mi := m as ModelInstance
		out.append({"pos": Vector2(mi.node.global_position.x, mi.node.global_position.z),
			"min_dist_m": 0.0, "pad_m": SoloController.model_base_radius_m(mi)})
	return out


## Centre-to-origin gap in inches (the enemy stands at the origin).
func _gap_in(u: GameUnit) -> float:
	var c: Vector3 = _main.solo_controller.unit_centre(u)
	return Vector2(c.x, c.z).length() / INCH


# === 4. Inquisitorial Agent / Second Wind — army_cap_fraction =================================

## v3.5.3: at most ONE THIRD of the carriers (rounded up) buys a second activation per round. Six
## carriers = two — the third is refused although two unused carriers are standing right there.
func test_second_wind_is_capped_at_one_third_of_the_carriers() -> void:
	var solo = _main.solo_controller
	var carriers: Array = []
	for i in range(6):
		var c := _unit(2, "Agent%d" % i, "human_inquisition", ["Inquisitorial Agent"], 1,
			Vector3(0.1 * i - 0.3, 0.0, 0.3))
		c.is_activated = true
		carriers.append(c)
	assert_int(int(RulesRegistry.param("gf", "human_inquisition", "Inquisitorial Agent", "army_cap_fraction", 0))) \
		.override_failure_message("fixture: the knob under test must exist in the emitted map").is_equal(3)

	var first: GameUnit = solo.second_wind_candidate()
	assert_object(first).is_not_null()
	solo.spend_second_wind(first)
	first.is_activated = true
	var second: GameUnit = solo.second_wind_candidate()
	assert_object(second) \
		.override_failure_message("6 carriers / 3 = 2 uses per round — the second must be allowed") \
		.is_not_null()
	solo.spend_second_wind(second)
	second.is_activated = true
	assert_object(solo.second_wind_candidate()) \
		.override_failure_message("the cap is one THIRD: a third use in the same round must be refused") \
		.is_null()
	# The next round opens the cap again (the cap is per round; the once-per-game flag is per unit).
	_main.opr_army_manager.current_round = 2
	assert_object(solo.second_wind_candidate()) \
		.override_failure_message("the cap must not outlive its round") \
		.is_not_null()


## The denominator is READ: a book that says "half" (army_cap_fraction 2) gets three uses out of the
## same six carriers, where v3.5.3's third gets two. Same code, different registry.
func test_the_cap_denominator_comes_from_the_registry() -> void:
	_inject_gf_map("testfac", {"Martial Prowess": {"primitive": "Second Wind",
		"params": {"uses_per_game": 1, "army_cap_fraction": 2}}})
	var solo = _main.solo_controller
	for i in range(6):
		var c := _unit(2, "Fechter%d" % i, "testfac", ["Martial Prowess"], 1,
			Vector3(0.1 * i - 0.3, 0.0, 0.3))
		c.is_activated = true
	for use in range(3):
		var cand: GameUnit = solo.second_wind_candidate()
		assert_object(cand) \
			.override_failure_message("a half-army cap must allow 3 of 6 carriers (use %d refused)" % (use + 1)) \
			.is_not_null()
		if cand == null:
			break   # a failed assert does not stop a gdUnit test — do not crash the run on top of it
		solo.spend_second_wind(cand)
		cand.is_activated = true
	assert_object(solo.second_wind_candidate()) \
		.override_failure_message("…and not a fourth: the denominator, not the count, decides") \
		.is_null()


# === 5. Defensive Growth and its siblings — defense_per_two ===================================

## The knob that granted NOTHING: Defensive Growth is "+1 Defense per TWO markers", and the reader
## only knew the older per-marker shape. Four markers = +2 Defense, and it reaches the real save
## target through _solo_defense_vs.
func test_defensive_growth_gives_one_defense_per_two_markers() -> void:
	var u := _unit(2, "Wächterorden", "human_inquisition", ["Defensive Growth"], 2)
	u.unit_properties["defense"] = 5
	assert_int(int(RulesRegistry.param("gf", "human_inquisition", "Defensive Growth", "defense_per_two", 0))) \
		.override_failure_message("fixture: the knob under test must exist in the emitted map").is_equal(1)

	assert_int(_main._solo_growth_defense_parts(u).size()) \
		.override_failure_message("no markers, no bonus").is_equal(0)
	u.unit_properties["growth_defensive_growth"] = 1
	assert_int(_main._solo_growth_defense_parts(u).size()) \
		.override_failure_message("ONE marker is not two — no bonus yet").is_equal(0)
	u.unit_properties["growth_defensive_growth"] = 2
	var parts: Array = _main._solo_growth_defense_parts(u)
	assert_int(parts.size()) \
		.override_failure_message("two markers must earn a part — the per-two shape was unread").is_equal(1)
	assert_int(_bonus_of(parts)).is_equal(1)
	assert_str("" if parts.is_empty() else str((parts[0] as Dictionary)["name"])).is_equal("Defensive Growth")
	u.unit_properties["growth_defensive_growth"] = 4
	assert_int(_bonus_of(_main._solo_growth_defense_parts(u))) \
		.override_failure_message("4 markers = two pairs = +2 Defense").is_equal(2)
	# …and it lands on the real save target (Defense 5 saves on 3+ with two pairs up).
	assert_int(_main._solo_defense_vs(u)) \
		.override_failure_message("the marker bonus never reached the save target") \
		.is_equal(3)


## The whole v3.5.3 growth cycle on the real round-start hook: a marker per round, capped at 4,
## Shaken BLOCKS the tick without clearing the pile, and every step says so in the log.
func test_growth_markers_tick_per_round_cap_at_four_and_shaken_only_blocks() -> void:
	var u := _unit(2, "Wächterorden", "human_inquisition", ["Defensive Growth"], 2)
	for i in range(4):
		_main._solo_growth_round_start()
		assert_int(int(u.unit_properties.get("growth_defensive_growth", 0))) \
			.override_failure_message("round %d must add exactly one marker" % (i + 1)).is_equal(i + 1)
	assert_int(_count("Defensive Growth: Wächterorden gains a marker")).is_equal(4)
	assert_str(_log_text()).contains("Defensive Growth: Wächterorden gains a marker (4/4)")

	_main._solo_growth_round_start()
	assert_int(int(u.unit_properties["growth_defensive_growth"])) \
		.override_failure_message("max 4 markers — the cap must hold").is_equal(4)
	assert_str(_log_text()) \
		.override_failure_message("rules-must-log: a capped pile that silently stops reads as broken") \
		.contains("Defensive Growth: Wächterorden is at the cap — no further marker (4/4)")

	# Shaken: no new marker, and the earned ones SURVIVE (the v3.5.3 change — the older books
	# removed the markers instead).
	var s := _unit(2, "Zweiter Orden", "human_inquisition", ["Defensive Growth"], 2, Vector3(-0.3, 0.0, 0.3))
	_main._solo_growth_round_start()
	_main._solo_growth_round_start()
	assert_int(int(s.unit_properties["growth_defensive_growth"])).is_equal(2)
	s.is_shaken = true
	_main._solo_growth_round_start()
	assert_int(int(s.unit_properties["growth_defensive_growth"])) \
		.override_failure_message("Shaken must BLOCK the new marker and KEEP the old ones") \
		.is_equal(2)
	assert_str(_log_text()).contains("Defensive Growth: Zweiter Orden is Shaken — no marker this round (keeps 2/4)")
	s.is_shaken = false
	_main._solo_growth_round_start()
	assert_int(int(s.unit_properties["growth_defensive_growth"])) \
		.override_failure_message("the block lasts exactly as long as the Shaken state").is_equal(3)


## The siblings, both generations at once: Piercing/Precision GROWTH scale per two markers (v3.5.3),
## Piercing/Precision FRENZY per marker (the older kill-fed books) — the second shape was unread too.
func test_the_growth_siblings_scale_in_both_registry_generations() -> void:
	var piercing := _unit(2, "Brutschwarm", "alien_hives", ["Piercing Growth"], 2)
	piercing.unit_properties["growth_piercing_growth"] = 4
	assert_int(int(_main._solo_growth_attack_bonus(piercing)["ap"])) \
		.override_failure_message("Piercing Growth: +1 AP per two markers").is_equal(2)
	var precision := _unit(2, "Seuchenherde", "infected_colonies", ["Precision Growth"], 2, Vector3(-0.3, 0.0, 0.2))
	precision.unit_properties["growth_precision_growth"] = 3
	assert_int(int(_main._solo_growth_attack_bonus(precision)["hit"])) \
		.override_failure_message("Precision Growth: +1 to hit per two markers (3 markers = one pair)").is_equal(1)
	var frenzy := _unit(2, "Schattenklingen", "dark_elf_raiders", ["Piercing Frenzy"], 2, Vector3(-0.3, 0.0, -0.2))
	frenzy.unit_properties["growth_piercing_frenzy"] = 2
	assert_int(int(_main._solo_growth_attack_bonus(frenzy)["ap"])) \
		.override_failure_message("Piercing Frenzy: +1 AP PER MARKER — the per-marker shape was unread") \
		.is_equal(2)
	var pf := _unit(2, "Gildenschützen", "dwarf_guilds", ["Precision Frenzy"], 2, Vector3(0.3, 0.0, -0.2))
	pf.unit_properties["growth_precision_frenzy"] = 2
	assert_int(int(_main._solo_growth_attack_bonus(pf)["hit"])).is_equal(2)


## Fortified Growth — the growth family's defensive sibling ("enemy AP counts as -1 per two markers,
## min AP(0)"): unread, so it did nothing at all. The reduction reaches the REAL save batch, and the
## log line (written before any die) is the proof.
func test_fortified_growth_softens_incoming_ap_per_two_markers() -> void:
	var u := _unit(1, "Seuchenwall", "wormhole_daemons_of_plague", ["Fortified Growth"], 2)
	u.unit_properties["growth_fortified_growth"] = 4
	var fg: Dictionary = _main._solo_growth_incoming_ap(u)
	assert_bool(fg.is_empty()) \
		.override_failure_message("4 markers = two pairs = AP(-2)").is_false()
	assert_int(int(fg.get("delta", 0))).is_equal(-2)
	u.unit_properties["growth_fortified_growth"] = 1
	assert_bool(_main._solo_growth_incoming_ap(u).is_empty()) \
		.override_failure_message("one marker is not a pair — nothing to reduce yet").is_true()

	# The all-models gate: a joined hero WITHOUT the rule switches the unit trigger off.
	u.unit_properties["growth_fortified_growth"] = 4
	var hero := _joined_hero(u, "Seuchenfürst", "wormhole_daemons_of_plague", ["Hero"])
	assert_object(hero).is_not_null()
	assert_bool(_main._solo_growth_incoming_ap(u).is_empty()) \
		.override_failure_message("\"all models have this rule\" is a UNIT trigger — a plain hero breaks it") \
		.is_true()
	u.unit_properties["attached_heroes"] = []

	# …and it lands in the real save batch: AP(3) arrives as AP(1) and the log says so.
	var striker := _unit(2, "Sturmtrupp", "alien_hives", [], 2, Vector3(0.5, 0.0, 0.5))
	var profile := {"name": "Klaue", "ap": 3, "deadly": 0, "rules": []}
	var wounds: int = await _main._solo_save_batch(striker, u, "Klaue", 3, 4, 3, profile, false, false)
	assert_int(wounds).is_between(0, 3)   # the dice decide this one — the LINE below does not
	assert_str(_log_text()) \
		.override_failure_message("rules-must-log: a save that lands two better without a word reads as broken dice:\n%s" % _log_text()) \
		.contains("Fortified Growth: Seuchenwall takes the hits at AP(1) instead of AP(3) — saves on 5+")
	# ROT direction — the prefix trap: "Fortified Growth" must NOT also collect the flat Fortified
	# AP(-1) (has_special_rule matches by prefix; the base rule needs its exact name).
	assert_int(_count("Fortified: Seuchenwall takes the hits")) \
		.override_failure_message("the plain Fortified reduction fired for a Fortified GROWTH carrier:\n%s" % _log_text()) \
		.is_equal(0)
	await E2EBoot.settle(get_tree())
