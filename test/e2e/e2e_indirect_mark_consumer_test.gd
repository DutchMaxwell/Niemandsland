extends GdUnitTestSuite
## Indirect Mark (STANDALONE_SWEEP row "Indirect Mark", CORE-ONLY) — the table consumes the
## mark's "Indirect" grant the way the core does (volley sight seam + AI targeting gate:
## mods::granted_vs(state, ti, "Indirect"), gated EPOCH_6_TABLE_RULES).
##
## Book (gf 1 book): "Once per activation, before attacking, pick one enemy unit within 18" in
## line of sight, which friendly units get Indirect against once (next time the effect would
## apply)." The pick already lands its once-record on the MARKED ENEMY (#845 option (b),
## beneficiary "attackers", main.gd _solo_apply_vs_marks) — but nothing read it: "Indirect" was
## not in AiSpell.BRIDGE_FLAGS and the targeting-time gates only read the shooter's own token
## (SoloController.granted_indirect_of). The marked enemy stayed untargetable without line of
## sight and the mark was spent for nothing.
##
## Fixture: the REAL mark path (_solo_apply_vs_marks over a synthetic gf/testfac registry map,
## the e2e_vs_mark_los_test.gd pattern) places the record in the open; the wall (same
## _wall_between shape) then blocks the lane for the marking side's friendly shooter — the
## grant's own scenario ("next time the effect would apply").

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._ensure_solo_controller()


func after_test() -> void:
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A solid container block painted across the bearer-target lane — the same synthetic-terrain
## idiom as e2e_vs_mark_los_test.gd's proven wall/patch helpers (the volume cache is dropped by
## hand because painting straight into grid_cells skips every registration seam).
func _wall_between(o: Node3D) -> void:
	for i in range(31):
		var t := float(i) / 30.0
		var p := Vector3(-0.12, 0.0, 0.0).lerp(Vector3(0.12, 0.0, 0.0), t)
		o.grid_cells[o.world_to_cell(p)] = o.TerrainType.CONTAINER
	o._los_volumes_dirty = true


## Synthetic map: the registry entry's own shape (gf/robot_legions "Indirect Mark": the Utility
## Buff primitive, vs_target, grants_rule "Indirect", scope shooting, once, 18", needs_los).
func _inject_mark_map() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {"testfac": {
		"Indirect Mark": {"primitive": "Utility Buff", "params": {"vs_target": true,
			"grants_rule": "Indirect", "scope": "shooting", "range_in": 18.0}},
	}}, "common": {}}


## Bearer (player 1, carries "Indirect Mark", armed with a plain long gun) and its would-be
## target (player 2), 0.6 m ≈ 23.6" apart — inside the mark's 18"... no: inside the GUN's reach
## but a hair over the mark's band, so the mark is placed with dist_in passed explicitly (6.0),
## the way e2e_vs_mark_los_test.gd keeps the range gate out of the LOS question.
func _bearer_and_target() -> Array:
	var bearer := E2EBoot.make_unit(_main, 1, "Bearer", [Vector3(-0.3, 0, 0)])
	bearer.unit_properties["game_system"] = "gf"
	bearer.unit_properties["faction_folder"] = "testfac"
	bearer.unit_properties["special_rules"] = ["Indirect Mark"]
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Long Gun"
	w.range_value = 36
	w.attacks = 2
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	src.weapons = ws
	bearer.source_type = "opr"
	bearer.source_data = src
	var target := E2EBoot.make_unit(_main, 2, "Marked", [Vector3(0.3, 0, 0)])
	target.unit_properties["game_system"] = "gf"
	target.unit_properties["faction_folder"] = "testfac"
	_main.opr_army_manager.game_units[bearer.unit_id] = bearer
	_main.opr_army_manager.game_units[target.unit_id] = target   # the NML-949 mirror walks the manager
	_main.opr_army_manager.current_round = 1
	return [bearer, target]


## The grants of the mark path exactly where #845 option (b) puts them: attacker-side records
## on the TARGET (read back through _solo_mods_of_chain, the seam the consumers use).
func _attacker_records(member: GameUnit) -> Array:
	var out: Array = []
	for m in _main._solo_mods_of_chain(member):
		if str((m as Dictionary).get("beneficiary", "")) == "attackers":
			out.append(str((m as Dictionary).get("grants_rule", "")))
	return out


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


# --- CONTROLS (green before and after the fix; declared first, see the discovery-order note
# --- in e2e_vs_mark_los_test.gd). ---------------------------------------------------------------

func test_control_the_mark_lands_on_the_target_in_the_open() -> void:
	_inject_mark_map()
	var pair := _bearer_and_target()
	_main._solo_apply_vs_marks(pair[0] as GameUnit, pair[1] as GameUnit, 6.0)
	var granted := _attacker_records(pair[1] as GameUnit)
	assert_array(granted) \
		.override_failure_message("control fixture: an UNBLOCKED mark within range must land its " +
			"attackers-side record on the TARGET (records: %s)" % str(granted)) \
		.contains(["Indirect"])


func test_control_an_unmarked_enemy_stays_illegal_behind_the_wall() -> void:
	_inject_mark_map()
	_wall_between(_main.terrain_overlay)
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	assert_int(_main._solo_sighted_count(bearer, target, 36)) \
		.override_failure_message("control fixture: the wall must block the lane — without a real " +
			"sight blocker the marked case below proves nothing") \
		.is_equal(0)
	var why: String = _main._solo_validate_target(bearer, target, false)
	assert_str(why) \
		.override_failure_message("control fixture: WITHOUT the mark the enemy behind the sight " +
			"blocker must stay an illegal target (refusal: '%s')" % why) \
		.is_not_empty()


# --- THE DEFECT (RED until the consumer lands). --------------------------------------------------

func test_a_marked_enemy_behind_a_sight_blocker_becomes_a_legal_shooting_target() -> void:
	# The book's own sequence: the bearer picks the enemy IN LINE OF SIGHT (the mark lands),
	# then the next friendly volley against the marked enemy waives the LOS test — ONCE.
	_inject_mark_map()
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main._solo_apply_vs_marks(bearer, target, 6.0)
	_wall_between(_main.terrain_overlay)
	assert_int(_main._solo_sighted_count(bearer, target, 36)) \
		.override_failure_message("fixture: the sight blocker must be real even for the marked case") \
		.is_equal(0)
	var why: String = _main._solo_validate_target(bearer, target, false)
	assert_str(why) \
		.override_failure_message("STANDALONE_SWEEP Indirect Mark — the marked enemy behind a sight " +
			"blocker must be a LEGAL shooting target for the marking side (the mark's attackers-side " +
			"once-record names \"Indirect\"), but the per-target validity gate refused: '%s'" % why) \
		.is_empty()


func test_the_marks_record_arms_the_volleys_indirect_facet() -> void:
	# The volley half: with the mark on the target the shooter's profiles carry the plain
	# "indirect" facet (AiSpell.BRIDGE_FLAGS → _solo_bridge_granted_flags) — the same facet
	# weapon-level Indirect rides (sight waiver, cover ignored, moved -1), once.
	_inject_mark_map()
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main._solo_apply_vs_marks(bearer, target, 6.0)
	var profile: Dictionary = _main._solo_bridge_granted_flags(bearer, {}, target)
	assert_bool(bool(profile.get("indirect", false))) \
		.override_failure_message("STANDALONE_SWEEP Indirect Mark — the mark's attackers-side record " +
			"must arm the volley's indirect facet via the bridge (profile: %s) — LOS waiver, cover " +
			"ignored and moved -1 all read that facet" % str(profile)) \
		.is_true()


func test_the_ai_can_pick_the_marked_enemy_without_line_of_sight() -> void:
	# The AI targeting half (the core's own second consumer, sim.rs AI targeting gate): the
	# marked enemy is a LEGAL target for the AI's target pick without sight.
	_inject_mark_map()
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main._solo_apply_vs_marks(bearer, target, 6.0)
	_wall_between(_main.terrain_overlay)
	var picked: GameUnit = _main.solo_controller.best_shoot_target_now(bearer)
	assert_object(picked) \
		.override_failure_message("STANDALONE_SWEEP Indirect Mark — the AI target pick must accept the " +
			"marked enemy behind the sight blocker (the mark's once-record names \"Indirect\"); got: %s"
			% (str(picked.get_name()) if picked != null else "null")) \
		.is_equal(target)
