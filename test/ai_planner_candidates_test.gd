extends GdUnitTestSuite
## What is left of the AiPlanner.candidates suite (P4.D-86): the candidate menu itself (hold, one rush per objective, hurtable
## charge, retreat, best-shoot, the holders and wide menus, the reach gate) is the core's, pinned by core/nml-core tests/menu.rs
## G1/G2 (the recorded menus), src/tests/menu/holders.rs, menu_wide.rs and the immobile menu tests. This file keeps the teacher
## label writer (SoloController.label_shoot_for) and the NML_MENU_WIDE switch, which have no Rust side.

## THE SEAM, not the part (17.08.). The 16.08. commit added the shot-preference
## in menu_covers_in and a test that hand-built {"kind": ADVANCE, "shoot": ...}
## — a move dictionary the PRODUCTION caller could not produce, because
## _menu_probe gated the recorded shot on `action == HOLD`. The test was green
## and the fix was dead. These pin the writer itself.
func test_the_recorded_move_keeps_its_shot_when_the_unit_advanced() -> void:
	# advancing and firing is the teacher's most common combined move: the label
	# must carry the victim, or the clone can never learn it exists
	assert_str(SoloController.label_shoot_for(
		AiDecision.Action.ADVANCE, "Foe", true)).is_equal("Foe")
	assert_str(SoloController.label_shoot_for(
		AiDecision.Action.HOLD, "Foe", true)).is_equal("Foe")
	# not firing means no victim, whatever the action
	assert_str(SoloController.label_shoot_for(
		AiDecision.Action.ADVANCE, "Foe", false)).is_equal("")
	# a charge's victim belongs in the "charge" field, never in "shoot"
	assert_str(SoloController.label_shoot_for(
		AiDecision.Action.CHARGE, "Foe", true)).is_equal("")
	assert_str(SoloController.label_shoot_for(
		AiDecision.Action.RUSH, "", true)).is_equal("")


func before_test() -> void:
	# The suite was written against the narrow menu: pin it (and the env caches) per test.
	AiPlanner.menu_holders = false
	AiPlanner._mh_env = 0
	AiPlanner.menu_wide = false
	AiPlanner._mw_env = 0


func after_test() -> void:
	# Statics leak across suites in one process: restore the SHIPPED defaults (menu_holders off,
	# menu_wide on, env caches unread), not the values the tests pin for themselves.
	AiPlanner.menu_holders = false
	AiPlanner._mh_env = -1
	AiPlanner.menu_wide = true
	AiPlanner._mw_env = -1


## S5 (22.09.): the ADVANCE+shoot leg is ON by default; NML_MENU_WIDE=0 is the explicit off,
## =1 the explicit on, anything else leaves the static default alone. (Confirmation run
## 22.09.: +4.70 points [+2.77, +6.83] over 2,000 pairs on fresh seeds.)
func test_menu_wide_env_switch_and_default() -> void:
	var saved_env := OS.get_environment("NML_MENU_WIDE")
	var saved_static := AiPlanner.menu_wide
	OS.set_environment("NML_MENU_WIDE", "0")
	AiPlanner._mw_env = -1
	AiPlanner.menu_wide = true
	assert_bool(AiPlanner.menu_wide_on()).is_false()
	OS.set_environment("NML_MENU_WIDE", "1")
	AiPlanner._mw_env = -1
	AiPlanner.menu_wide = false
	assert_bool(AiPlanner.menu_wide_on()).is_true()
	OS.set_environment("NML_MENU_WIDE", "")
	AiPlanner._mw_env = -1
	AiPlanner.menu_wide = true
	assert_bool(AiPlanner.menu_wide_on()).is_true()   # unset: the shipped default (on) stands
	OS.set_environment("NML_MENU_WIDE", saved_env)
	AiPlanner._mw_env = -1
	AiPlanner.menu_wide = saved_static
