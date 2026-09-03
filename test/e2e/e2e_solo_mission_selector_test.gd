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


## Duel — the selector's default ("" = no mission) — is a true no-op: today's live table
## (SoloController's statics) stays exactly what it already was, byte-identical.
func test_duel_leaves_the_live_statics_untouched() -> void:
	SoloController.mission_reset("PRE_EXISTING", {"marker": "sentinel"}, [{"sentinel": true}])
	_main._solo_mission_id = ""
	_main._solo_apply_mission_if_chosen()
	assert_str(SoloController.mission_scoring).is_equal("PRE_EXISTING")
	assert_that(SoloController.mission_vp_flavour).is_equal({"marker": "sentinel"})
	assert_that(SoloController.mission_markers).is_equal([{"sentinel": true}])
