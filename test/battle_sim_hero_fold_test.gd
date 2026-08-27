extends GdUnitTestSuite
## NML-1073 M5 BUG-3 — the JOINED-HERO FOLD knob (`hero_fold`, default OFF).
##
## The shipped planner imagines an army with MORE activations than it has: a
## joined hero gets its own turn in every playout (ai_planner.gd:27/:131/:645,
## battle_sim.gd resolve moves `su["positions"]` alone), while the real table
## refuses it — `SoloController.can_activate` (solo_controller.gd:405-419) ends
## on `not u.is_attached()`. With the knob ON the imagination mirrors the table
## in the same three places the Rust `Seams::hero_attach` does: the pool refuses
## the hero (state.rs:414), the host's move carries it (sim.rs:940) and the
## host's activation spends it (sim.rs:1122).
##
## Fixture recipe mirrors test/battle_sim_resolve_test.gd; the knob reset mirrors
## test/battle_sim_cast_phase_test.gd (BattleSim.new().set("_hero_fold_env", -1)).

const IN2M := 0.0254


func before_test() -> void:
	BattleSim.hero_fold = false
	OS.set_environment("NML_HERO_FOLD", "")
	BattleSim.new().set("_hero_fold_env", -1)


func after_test() -> void:
	BattleSim.hero_fold = false
	OS.set_environment("NML_HERO_FOLD", "")
	BattleSim.new().set("_hero_fold_env", -1)


func _unit(pid: int, uid: String, xs: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for x in xs:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.wounds_max = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(float(x) * IN2M, 0, 0)
		m.node = n
		u.models.append(m)
	return u


## Host (2 models) + a HERO joined to it + one far-off enemy, so nothing the
## fold does can be confused with the 1" spacing clamp.
func _state() -> Dictionary:
	var host := _unit(2, "Host", [0.0, 1.0])
	var hero := _unit(2, "Hero", [0.5])
	var foe := _unit(1, "Foe", [40.0])
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Host": host, "Hero": hero, "Foe": foe}
	return BattleSim.capture(army)


func _pos(state: Dictionary, key: String) -> Vector3:
	return ((state["units"][key] as Dictionary)["positions"] as Array)[0] as Vector3


# === the POOL half ==========================================================

## The capture carries the attachment either way — the knob decides what the
## pool does with it, not whether the planner can see it.
func test_the_capture_carries_the_attachment() -> void:
	var state := _state()
	assert_str(str((state["units"]["Hero"] as Dictionary)["attached_to"])).is_equal("Host")
	assert_array((state["units"]["Host"] as Dictionary)["attached"]).contains(["Hero"])


## KNOB OFF (the shipped behaviour): with the host already spent, the hero is
## still offered its own activation — plan() picks it.
func test_the_pool_offers_a_joined_hero_when_the_knob_is_off() -> void:
	var state := _state()
	(state["units"]["Host"] as Dictionary)["activated"] = true
	assert_bool(AiPlanner._can_activate(state["units"]["Hero"], 2)).is_true()
	var pick := AiPlanner.plan(state, 2)
	assert_bool(bool(pick.get("used", false))).is_true()
	assert_str(str(pick["unit_key"])).is_equal("Hero")


## KNOB ON: the same pool is EMPTY — a joined hero has no activation of its own,
## exactly as SoloController.can_activate rules on the table.
func test_the_pool_refuses_a_joined_hero_when_the_knob_is_on() -> void:
	BattleSim.hero_fold = true
	var state := _state()
	(state["units"]["Host"] as Dictionary)["activated"] = true
	assert_bool(AiPlanner._can_activate(state["units"]["Hero"], 2)).is_false()
	assert_bool(bool(AiPlanner.plan(state, 2).get("used", false))) \
		.override_failure_message("a joined hero was still given its own imagined activation") \
		.is_false()
	# The HOST is never touched by the fold — only the hero term is added.
	(state["units"]["Host"] as Dictionary)["activated"] = false
	assert_bool(AiPlanner._can_activate(state["units"]["Host"], 2)).is_true()


# === the RESOLVE half =======================================================

## KNOB ON: the host's activation carries the hero's models along its own rigid
## delta and SPENDS the hero. OFF: the hero is left standing where it was, fresh.
func test_the_hosts_activation_moves_and_spends_its_hero_only_under_the_knob() -> void:
	var state := _state()
	var act := {"unit": "Host", "kind": AiDecision.Action.ADVANCE,
		"dest": Vector3(20.0 * IN2M, 0, 0)}
	var off := BattleSim.resolve(state, act)
	assert_that(_pos(off, "Hero")).is_equal(_pos(state, "Hero"))
	assert_bool(bool((off["units"]["Hero"] as Dictionary)["activated"])).is_false()

	BattleSim.hero_fold = true
	var on := BattleSim.resolve(state, act)
	var delta: Vector3 = _pos(on, "Host") - _pos(state, "Host")
	assert_float(delta.length() / IN2M).is_equal_approx(6.0, 0.01)   # the advance band
	assert_that(_pos(on, "Hero")).is_equal(_pos(state, "Hero") + delta)
	assert_bool(bool((on["units"]["Hero"] as Dictionary)["activated"])) \
		.override_failure_message("the host went and its joined hero still looked fresh") \
		.is_true()


# === the KNOB's three doors =================================================

## The preset door: planner_v0_herofold is planner_v0 plus the fold, and plain
## planner_v0 keeps it off.
func test_the_preset_carries_the_knob() -> void:
	assert_bool(SoloDifficulty.for_grade("planner_v0_herofold").hero_fold).is_true()
	assert_bool(SoloDifficulty.for_grade("planner_v0_herofold").planner).is_true()
	assert_bool(SoloDifficulty.for_grade("planner_v0").hero_fold).is_false()


## THE FOUR A/B ARMS. `arena_match.gd` FATALs on a grade that is not in PRESETS (the
## label-bug guard), and `for_grade` silently falls back to nachtmahr for an unknown name —
## so a typo'd arm would play the wrong AI under the right label. Pin all four by name.
func test_all_four_ab_arms_resolve_with_the_expected_flags() -> void:
	for row in [["planner_v0", false, false], ["planner_v0_herofold", false, true],
			["planner_v0_pool1", true, false], ["planner_v0_both", true, true]]:
		var name: String = row[0]
		assert_bool(SoloDifficulty.PRESETS.has(name)) \
			.override_failure_message("arena_match would FATAL on grade '%s'" % name).is_true()
		var d := SoloDifficulty.for_grade(name)
		assert_str(d.grade_name).is_equal(name)          # no silent nachtmahr fallback
		assert_bool(d.planner).is_true()
		assert_bool(d.pool1_rollout).is_equal(bool(row[1]))
		assert_bool(d.hero_fold).is_equal(bool(row[2]))


## THE SHIPPED-GRADE PAIR: nachtmahr_herofold is nachtmahr plus the fold, nothing else — the
## tree-vs-tree A/B the maintainer wants BEFORE any default flip, since ALBTRAUM lookahead
## also runs on BattleSim.
func test_the_nachtmahr_herofold_preset_pairs_with_nachtmahr() -> void:
	assert_bool(SoloDifficulty.PRESETS.has("nachtmahr_herofold")).is_true()
	var d := SoloDifficulty.for_grade("nachtmahr_herofold")
	assert_str(d.grade_name).is_equal("nachtmahr_herofold")   # no silent nachtmahr fallback
	assert_bool(d.planner).is_false()
	assert_bool(d.hero_fold).is_true()
	var paired: Dictionary = (SoloDifficulty.PRESETS["nachtmahr_herofold"] as Dictionary).duplicate()
	paired.erase("hero_fold")
	assert_dict(paired).is_equal(SoloDifficulty.PRESETS["nachtmahr"])


## The env door (headless runs): NML_HERO_FOLD=1 pins the fold process-wide.
func test_the_env_seam_turns_the_fold_on() -> void:
	assert_bool(BattleSim.hero_fold_enabled()).is_false()
	OS.set_environment("NML_HERO_FOLD", "1")
	BattleSim.new().set("_hero_fold_env", -1)
	assert_bool(BattleSim.hero_fold_enabled()).is_true()


## The HEADER door: the Rust seam reads `Seams::hero_attach` out of this key
## (nml-core-godot/src/plain.rs knobs_of), so an NML_CORE=1 game folds with us.
func test_the_header_stamps_hero_attach_for_the_rust_seam() -> void:
	var state := _state()
	var knobs_off: Dictionary = AiActRecorder._header_line(state, Callable())["knobs"]
	assert_bool(bool(knobs_off["hero_attach"])).is_false()
	BattleSim.hero_fold = true
	var knobs_on: Dictionary = AiActRecorder._header_line(state, Callable())["knobs"]
	assert_bool(bool(knobs_on["hero_attach"])).is_true()
