extends GdUnitTestSuite
## The NACHTMAHR difficulty ladder (grill 25.09.2026, NML-1018): five player-facing grades bottom-up.
## Dämmerung / Zwielicht / Finsternis are decision-tree presets on every platform (the documented
## rekrut / veteran / kriegsherr knob vectors, docs/SOLO_AI_RULES_COVERAGE.md), Albtraum is Erlkönig
## 10/3 where the core and its brain are up, else the tree's ceiling; NACHTMAHR is reserved. The
## three lower grades never reach the planner (the only road to the net).

const CFG := "user://test_solo_grade.cfg"
const HARNESS := "niemandsland/harness_mode"


func before_test() -> void:
	ProjectSettings.set_setting(SoloGrade.CFG_OVERRIDE_SETTING, CFG)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func after_test() -> void:
	ProjectSettings.set_setting(SoloGrade.CFG_OVERRIDE_SETTING, "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func test_five_grades_bottom_up_and_nachtmahr_is_not_selectable() -> void:
	assert_array(SoloGrade.GRADES).contains_exactly(["daemmerung", "zwielicht", "finsternis", "albtraum", "nachtmahr"])
	assert_str(SoloGrade.DEFAULT).is_equal("albtraum")
	for g in ["daemmerung", "zwielicht", "finsternis", "albtraum"]:
		assert_bool(SoloGrade.selectable(g)).override_failure_message("%s must be selectable" % g).is_true()
	assert_bool(SoloGrade.selectable("nachtmahr")).is_false()
	assert_str(SoloGrade.sanitize("nachtmahr")).is_equal("albtraum")
	assert_str(SoloGrade.sanitize(" Zwielicht ")).is_equal("zwielicht")
	assert_str(SoloGrade.display_name("daemmerung")).is_equal("Dämmerung")
	assert_str(SoloGrade.display_name("nachtmahr")).is_equal("NACHTMAHR")


## Core AND brain up on every call — the strongest case for a lower grade leaking into the net.
func test_grades_map_to_presets_and_only_albtraum_reaches_the_planner() -> void:
	assert_str(SoloGrade.preset_for("daemmerung", true, true)).is_equal("daemmerung")
	assert_str(SoloGrade.preset_for("zwielicht", true, true)).is_equal("zwielicht")
	assert_str(SoloGrade.preset_for("finsternis", true, true)).is_equal("finsternis")
	assert_str(SoloGrade.preset_for("albtraum", true, true)).is_equal("planner_v0")
	assert_str(SoloGrade.preset_for("albtraum", false, false)).is_equal("nachtmahr")
	assert_str(SoloGrade.base_preset("albtraum")).is_equal("nachtmahr")   # today's pin, unchanged
	for g in ["daemmerung", "zwielicht", "finsternis"]:
		var d := SoloDifficulty.for_grade(SoloGrade.preset_for(g, true, true))
		assert_str(d.grade_name).override_failure_message("%s fell back to another preset" % g).is_equal(g)
		assert_bool(d.planner).override_failure_message("%s routes through the planner (the net)" % g).is_false()


## The probe itself can say yes: the same controller check is true for Albtraum on the planner.
func test_a_lower_grade_never_activates_the_planner_seam() -> void:
	var sc: SoloController = auto_free(SoloController.new())
	sc.ai_slot = 2
	for g in ["daemmerung", "zwielicht", "finsternis"]:
		sc.set_difficulty(2, SoloDifficulty.for_grade(SoloGrade.preset_for(g, true, true)))
		assert_bool(sc._planner_active()).override_failure_message("%s activated the planner" % g).is_false()
	sc.set_difficulty(2, SoloDifficulty.for_grade(SoloGrade.preset_for("albtraum", true, true)))
	assert_bool(sc._planner_active()).is_true()


func _assert_knobs(g: String, noise: float, exploit: float, focus: float, coord: float, persist: float) -> void:
	var d := SoloDifficulty.for_grade(g)
	assert_float(d.ev_noise).override_failure_message("%s ev_noise" % g).is_equal(noise)
	assert_float(d.rule_exploitation).override_failure_message("%s rule_exploitation" % g).is_equal(exploit)
	assert_float(d.mission_focus).override_failure_message("%s mission_focus" % g).is_equal(focus)
	assert_float(d.coordination).override_failure_message("%s coordination" % g).is_equal(coord)
	assert_float(d.persistence).override_failure_message("%s persistence" % g).is_equal(persist)
	assert_bool(d.lookahead or d.avoid_overkill or d.endgame_convergence).override_failure_message("%s carries an Albtraum-only knob" % g).is_false()


func test_lower_grades_carry_the_documented_tree_knobs() -> void:
	_assert_knobs("daemmerung", 0.40, 0.0, 0.35, 0.0, 0.0)   # rekrut
	_assert_knobs("zwielicht", 0.15, 0.5, 0.70, 0.60, 0.5)   # veteran
	_assert_knobs("finsternis", 0.0, 1.0, 1.0, 1.0, 1.0)     # kriegsherr
	# The legacy names keep resolving to the ceiling (arena tools and saved invocations pass them).
	assert_str(SoloDifficulty.for_grade("kriegsherr").grade_name).is_equal("nachtmahr")


func _write(grade: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("solo", "solo_grade", grade)
	cfg.save(CFG)


func test_solo_grade_defaults_to_albtraum_and_reads_the_saved_choice() -> void:
	assert_str(SoloGrade.load_saved()).is_equal("albtraum")   # no file yet
	_write("finsternis")
	assert_str(SoloGrade.load_saved()).is_equal("finsternis")
	_write("nachtmahr")   # reserved, not selectable
	assert_str(SoloGrade.load_saved()).is_equal("albtraum")
	_write("kriegsherr")   # a stale / hand-edited value
	assert_str(SoloGrade.load_saved()).is_equal("albtraum")


func test_harness_mode_without_an_override_never_touches_the_players_file() -> void:
	var was: bool = bool(ProjectSettings.get_setting(HARNESS, false))
	ProjectSettings.set_setting(SoloGrade.CFG_OVERRIDE_SETTING, "")
	ProjectSettings.set_setting(HARNESS, true)
	var path := SoloGrade._path()
	ProjectSettings.set_setting(HARNESS, was)
	assert_str(path).is_empty()


func test_start_line_names_grade_and_brain() -> void:
	assert_str(SoloGrade.start_line({"engine": "erlkoenig", "id": "onnx", "hash": "ab"}, false)).is_equal("NACHTMAHR — Albtraum (Erlkönig)")
	assert_str(SoloGrade.start_line({"engine": "classic", "id": "nachtmahr", "hash": ""}, false)).is_equal("NACHTMAHR — Albtraum (decision tree)")
	assert_str(SoloGrade.start_line({"engine": "classic", "id": "nachtmahr", "hash": ""}, true)) \
		.is_equal("NACHTMAHR — Albtraum (decision tree — on macOS still without Erlkönig)")
	assert_str(SoloGrade.start_line({"engine": "classic", "id": "zwielicht", "hash": ""}, true)).is_equal("NACHTMAHR — Zwielicht (decision tree)")
	assert_str(SoloGrade.start_line({"engine": "classic", "id": "daemmerung", "hash": ""}, false)).is_equal("NACHTMAHR — Dämmerung (decision tree)")
	assert_str(SoloGrade.start_line({}, false)).is_empty()   # no graded AI seat
	assert_str(SoloGrade.start_line({"engine": "classic", "id": "veteran", "hash": ""}, false)).is_empty()   # not a ladder grade
