extends GdUnitTestSuite
## Exact striker labels from the pending epoch 94 (Plan H, lead order 20.11.; core twin `rules::is_unlisted_striker_label`, acts.rs `PENDING_EPOCH_EXACT_STRIKER_LABELS`):
## the table's `_solo_striker_has_bane` and the planner's `BattleSim._profiles_of` matched Bane / Lacerate / Rending / Unstoppable by PREFIX at unit level, so a unit carrying
## `Bane Mark`, `Rending Mark`, `Unstoppable Mark` or `Bane in Melee Buff` counted as a bearer. The army-book texts (ds/h_prefix_labels.md) hand the rule once to OTHER units. From 94 only
## the rule and its explicit scoped spellings count; below 94 the old reading stands byte for byte (recorded games). RED: drop the gates -> the 94 rows read as the 93 rows.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

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


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit_with(rules: Array) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties = {"player_id": 1, "name": "Squad", "quality": 4, "defense": 4, "special_rules": rules, "game_system": "gf", "faction_folder": "battle_brothers"}
	for _i in 5:
		var m := ModelInstance.new()
		m.is_alive = true
		gu.models.append(m)
	var src := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 5
	src.weapons.append(w)
	gu.source_type = "opr"
	gu.source_data = src
	return gu


func test_the_label_predicate_lists_the_rule_and_its_scoped_spellings() -> void:
	for listed in ["Bane", "Bane in Melee", "Bane when Shooting", "Bane (spell)", "Lacerate", "Rending", "Rending in Melee", "Rending when Shooting", "Unstoppable", "Unstoppable in Melee", "Unstoppable when Shooting", "Hero", "Tough(3)"]:
		assert_bool(GameUnit.is_unlisted_striker_label(listed)).override_failure_message("%s is the rule, a scoped spelling or no striker rule" % listed).is_false()
	for label in ["Bane Mark", "Bane in Melee Buff", "Bane in Melee Aura", "Rending Mark", "Rending when Shooting Aura", "Unstoppable Mark", "Unstoppable when Shooting Aura"]:
		assert_bool(GameUnit.is_unlisted_striker_label(label)).override_failure_message("%s only labels a grant" % label).is_true()


## The table's dice read: [unit rules, melee?, counts below 94, counts from 94].
func test_the_tables_bane_read_skips_the_labels_from_the_pending_epoch() -> void:
	var rows := [
		[["Bane"], true, true, true], [["Bane"], false, true, true],
		[["Bane in Melee"], true, true, true], [["Bane in Melee"], false, false, false],
		[["Bane when Shooting"], false, true, true], [["Bane when Shooting"], true, false, false],
		[["Bane Mark"], true, true, false], [["Bane Mark"], false, true, false],
		[["Bane in Melee Buff"], true, true, false], [["Bane in Melee Buff"], false, false, false]]
	for row in rows:
		var gu := _unit_with(row[0])
		AiActRecorder.rules_epoch = AiActRecorder.PENDING_EPOCH_EXACT_STRIKER_LABELS - 1
		assert_bool(_main._solo_striker_has_bane(gu, {"rules": []}, row[1])).override_failure_message("below 94: %s melee=%s" % [row[0], row[1]]).is_equal(row[2])
		AiActRecorder.rules_epoch = AiActRecorder.PENDING_EPOCH_EXACT_STRIKER_LABELS
		assert_bool(_main._solo_striker_has_bane(gu, {"rules": []}, row[1])).override_failure_message("from 94: %s melee=%s" % [row[0], row[1]]).is_equal(row[3])


## The planner's unit-level scan (the EV imagination): Rending / Unstoppable / Bane flags OR-ed onto every profile.
func test_the_planner_stamps_no_flag_for_a_label_from_the_pending_epoch() -> void:
	for row in [[["Rending"], "rending"], [["Unstoppable"], "unstoppable"], [["Bane"], "bane"], [["Rending Mark"], "rending"], [["Unstoppable Mark"], "unstoppable"], [["Bane Mark"], "bane"]]:
		var gu := _unit_with(row[0])
		var is_label: bool = GameUnit.is_unlisted_striker_label(row[0][0])
		for epoch in [AiActRecorder.PENDING_EPOCH_EXACT_STRIKER_LABELS - 1, AiActRecorder.PENDING_EPOCH_EXACT_STRIKER_LABELS]:
			AiActRecorder.rules_epoch = epoch
			var profiles: Array = BattleSim._profiles_of({"unit": gu, "alive": 5}, false)
			assert_bool(profiles.size() > 0).override_failure_message("a ranged profile exists").is_true()
			var stamped := bool((profiles[0] as Dictionary).get(row[1], false))
			var want: bool = not (is_label and epoch >= AiActRecorder.PENDING_EPOCH_EXACT_STRIKER_LABELS)
			assert_bool(stamped).override_failure_message("%s -> %s at epoch %d" % [row[0], row[1], epoch]).is_equal(want)
