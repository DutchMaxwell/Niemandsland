extends GdUnitTestSuite
## Missions wave M5 — the table-side Mission selector (design doc
## DESIGN_missions_2026-09-02.md §1/§2). The panel offered no choice at all before this
## (MissionCatalog had zero consumers under scripts/), so "how often players pick a mission" had
## no answer. This suite drives the REAL left-menu panel and the REAL mission-apply seam a
## "Start Deployment" click runs — a catalog pick must reach SoloController's live statics exactly
## the way tools/arena_match.gd:302-321's own constant-placement path does; Duel (no mission, the
## selector's default) must leave them untouched.

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
	_main.solo_ai_slots = {2: true}   # plan 2.2: no implicit NACHTMAHR — this table designates player 2 explicitly
	_main.opr_army_manager.armies = {1: null, 2: null}
	_main._refresh_solo_panel()


func after_test() -> void:
	SoloController.mission_reset("end", {})   # statics: never leak this game's mission into the next suite
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _log_text() -> String:
	var lines: PackedStringArray = []
	for e in _main.battle_log.entries():
		lines.append(str((e as Dictionary).get("text", "")))
	return "\n".join(lines)


## The panel must offer exactly "Duel (no mission)" + one entry per catalog mission — no more, no
## fewer (a hard-coded list would silently drift from the catalog the moment it grows).
func test_mission_option_list_matches_the_catalog_plus_duel() -> void:
	assert_object(_main.solo_mission_option).is_not_null()
	assert_int(_main.solo_mission_option.item_count).is_equal(MissionCatalog.mission_ids().size() + 1)
	assert_str(_main.solo_mission_option.get_item_text(0)).is_equal("Duel (no mission)")


## Picking "sabotage" must reach SoloController's live statics through the SAME path
## tools/arena_match.gd:302-321 drives: scoring + owned/destructible marker metadata straight from
## the catalog, plus the one battle-log line every applied rule gets.
func test_starting_with_a_mission_arms_the_controller_statics() -> void:
	SoloController.mission_reset("PRE_EXISTING", {"marker": "sentinel"}, [{"sentinel": true}])
	_main._solo_mission_id = "sabotage"
	_main._solo_apply_mission_if_chosen()
	assert_str(SoloController.mission_scoring).is_equal("sabotage")
	assert_int(SoloController.mission_markers.size()).is_equal(2)
	var m0: Dictionary = SoloController.mission_markers[0]
	assert_int(int(m0.get("owned_by", 0))).is_equal(1)
	assert_bool(bool(m0.get("destructible", false))).is_true()
	assert_str(_log_text()).contains("Mission: Sabotage")


## D14.6: Smash & Grab's marker count is a dice term, so the table arms NO markers up front (the old
## int(spec) read "d3+2" as 32); once the markers are placed and the roles are set the list is sized to
## the objectives and the AI defender hides a relic and a trap.
func test_smash_and_grab_sizes_its_secret_markers_to_the_placed_objectives() -> void:
	_main._ensure_solo_controller()
	_main._solo_mission_id = "smash_and_grab"
	_main._solo_apply_mission_if_chosen()
	assert_int(SoloController.mission_markers.size()).is_equal(0)
	assert_int(_main.solo_controller.game_rounds).is_equal(6)
	_main.terrain_overlay.update_objectives([Vector3.ZERO, Vector3(30 * 0.0254, 0, 0), Vector3(-34 * 0.0254, 0, 0),
		Vector3(0, 0, 10 * 0.0254)])
	_main.solo_ai_slots = {2: true}
	_main.solo_controller.human_slot = 1
	_main._solo_batch = true   # no pick UI for the human defender: the AI rule hides trap and relic
	_main._solo_roles_set(2, "attacker")   # NACHTMAHR attacks, the human defends and keeps the 4 markers he placed
	assert_int(SoloController.mission_markers.size()).is_equal(4)
	var kinds := SoloController.mission_markers.map(func(m: Variant) -> String: return str((m as Dictionary)["secret"]))
	assert_int(kinds.count("relic")).is_equal(1)
	assert_int(kinds.count("trap")).is_equal(1)


## D14.3: Last Stand plays six rounds; once the roles are set the table reads its two phases and its
## recycling reserve rule from the catalog (the defender holds the centre, the attacker's dead return).
func test_last_stand_reads_its_phases_and_recycling_reserve_from_the_catalog() -> void:
	_main._ensure_solo_controller()
	_main._solo_mission_id = "last_stand"
	_main._solo_apply_mission_if_chosen()
	assert_int(_main.solo_controller.game_rounds).is_equal(6)
	_main.solo_ai_slots = {2: true}
	_main._solo_roles_set(1, "attacker")
	assert_int(SoloController.deploy_phases_of(MissionCatalog.get_mission("last_stand")).size()).is_equal(2)
	var cfg: Dictionary = _main._solo_reserve_cfg()
	assert_bool(bool(cfg.get("recycle", false))).is_true()
	assert_that(_main._solo_reserve_slots(cfg)).is_equal([1])   # the attacker's slot
	assert_that(_main._solo_deploy_gates_for(1)).is_equal({})


## D14.2: Ambush plays six rounds; once the roles are set the table reads its three phases, the attacker
## phase carrying its own gates (not the role's), and no reserve rule.
func test_ambush_reads_its_three_phases_with_their_own_gates() -> void:
	_main._ensure_solo_controller()
	_main._solo_mission_id = "ambush"
	_main._solo_apply_mission_if_chosen()
	assert_int(_main.solo_controller.game_rounds).is_equal(6)
	_main.solo_ai_slots = {2: true}
	_main._solo_roles_set(1, "attacker")
	var ph: Array = SoloController.deploy_phases_of(MissionCatalog.get_mission("ambush"))
	assert_int(ph.size()).is_equal(3)
	var g: Dictionary = _main._solo_phase_gates(ph[1], 1)
	assert_float(float(g["min_from_enemy_in"])).is_equal(12.0)
	assert_float(float(g["max_from_friend_in"])).is_equal(6.0)
	assert_that(_main._solo_phase_gates(ph[0], 2)).is_equal({})   # the defender's half: no gate
	assert_bool(_main._solo_reserve_cfg().is_empty()).is_true()


## D14.1: The Raid plays six rounds; the defender's rest phase (and only it) carries the 12" enemy and
## marker gates, the disc and frame phases none.
func test_the_raid_gates_only_the_defenders_rest_phase() -> void:
	_main._ensure_solo_controller()
	_main._solo_mission_id = "the_raid"
	_main._solo_apply_mission_if_chosen()
	assert_int(_main.solo_controller.game_rounds).is_equal(6)
	_main.solo_ai_slots = {2: true}
	_main._solo_roles_set(1, "attacker")
	var ph: Array = SoloController.deploy_phases_of(MissionCatalog.get_mission("the_raid"))
	assert_int(ph.size()).is_equal(3)
	assert_that(_main._solo_phase_gates(ph[0], 2)).is_equal({})
	assert_that(_main._solo_phase_gates(ph[1], 1)).is_equal({})
	var g: Dictionary = _main._solo_phase_gates(ph[2], 2)
	assert_float(float(g["min_from_enemy_in"])).is_equal(12.0)
	assert_float(float(g["min_from_marker_in"])).is_equal(12.0)


## D14.5: The Rescue plays six rounds, arms ONE attacker-only carry marker that drops 6", and (once the
## roles are set) covers BOTH sides with the 4+ reserve rule.
func test_the_rescue_arms_an_attacker_only_marker_and_reserves_for_both_sides() -> void:
	_main._ensure_solo_controller()
	_main._solo_mission_id = "the_rescue"
	_main._solo_apply_mission_if_chosen()
	assert_int(_main.solo_controller.game_rounds).is_equal(6)
	assert_int(SoloController.mission_markers.size()).is_equal(1)
	var mk: Dictionary = SoloController.mission_markers[0]
	assert_bool(bool(mk.get("carry", false))).is_true()
	assert_bool(bool(mk.get("attacker_only", false))).is_true()
	assert_float(float(mk.get("drop_in", 0.0))).is_equal(6.0)
	_main.solo_ai_slots = {2: true}
	_main._solo_roles_set(1, "attacker")
	var cfg: Dictionary = _main._solo_reserve_cfg()
	assert_that(_main._solo_reserve_slots(cfg)).is_equal([1, 2])
	assert_int(int(cfg["arrive_on"])).is_equal(4)


func test_relic_hunt_arms_three_carried_markers() -> void:
	_main._solo_mission_id = "relic_hunt"
	_main._solo_apply_mission_if_chosen()
	assert_int(SoloController.mission_markers.size()).is_equal(3)
	for marker in SoloController.mission_markers:
		assert_bool(bool((marker as Dictionary).get("carry", false))).is_true()
		assert_str(str((marker as Dictionary).get("carried_by", "missing"))).is_equal("")


## Duel — the selector's default ("" = no mission) — is a true no-op: today's live table
## (SoloController's statics) stays exactly what it already was, byte-identical.
func test_duel_leaves_the_live_statics_untouched() -> void:
	SoloController.mission_reset("PRE_EXISTING", {"marker": "sentinel"}, [{"sentinel": true}])
	_main._solo_mission_id = ""
	_main._solo_apply_mission_if_chosen()
	assert_str(SoloController.mission_scoring).is_equal("PRE_EXISTING")
	assert_that(SoloController.mission_vp_flavour).is_equal({"marker": "sentinel"})
	assert_that(SoloController.mission_markers).is_equal([{"sentinel": true}])
