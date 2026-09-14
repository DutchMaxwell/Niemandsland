extends GdUnitTestSuite
## EPOCH 37 UNSTOPPABLE AURA (STANDALONE_SWEEP_C_2026-09-14, row
## `Unstoppable when Shooting Aura`) — the TABLE layer's scope split.
##
## The aura's Utility-Buff record carries its scope
## (`{grants_rule: "Unstoppable", scope: "shooting"}`), but the table read the
## grant scope-blind: `_solo_ignores_regen`'s exact-name line answered in BOTH
## halves (melee Regeneration bypass — the leak), and the bridge's own-store
## loop never folded "unstoppable" at all, so the clamp half never fired. From
## 37 both reads consult the live record's scope:
##
## - test_the_aura_arms_the_shooting_clamp_only — the bridge folds the flag at
##   the SHOOTING seam and refuses it at the melee seam.
## - test_the_auras_regeneration_half_answers_shooting_only — the regen read
##   answers the shooting half and refuses melee, with the printed plain
##   "Unstoppable" rule as the both-halves CONTROL.
##
## Drives the REAL `_solo_apply_utility_buffs` -> `_solo_record_spell_mod` ->
## spell_records mirror path over main.tscn; the registry map is synthetic
## (RulesRegistry._cache injection, the e2e_vs_mark_los_test.gd pattern).

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


## Synthetic map: the aura entry exactly as the sweep row quotes it — a
## "Utility Buff" with the grant name and the shooting scope, persistent.
func _inject_aura_map() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {"testfac": {
		"Unstoppable when Shooting Aura": {"primitive": "Utility Buff",
			"params": {"range_in": 12.0, "grants_rule": "Unstoppable",
				"scope": "shooting", "once": false}},
	}}, "common": {}}


## The carrier (player 1) — the only friendly unit, so the aura's own pick is
## the carrier itself. `special_rules` also receives an optional extra rule.
func _aura_carrier(extra: Array = []) -> GameUnit:
	var carrier := E2EBoot.make_unit(_main, 1, "Carrier", [Vector3(0.0, 0, 0)])
	carrier.unit_properties["game_system"] = "gf"
	carrier.unit_properties["faction_folder"] = "testfac"
	carrier.unit_properties["special_rules"] = ["Unstoppable when Shooting Aura"] + extra
	_main.opr_army_manager.game_units[carrier.unit_id] = carrier   # the NML-949 mirror walks the manager
	_main.opr_army_manager.current_round = 1
	return carrier


func _record_scopes(unit: GameUnit) -> Array:
	var out: Array = []
	for rd in unit.unit_properties.get("spell_records", []):
		out.append("%s|%s" % [str((rd as Dictionary).get("grants_rule", "")),
			str((rd as Dictionary).get("scope", ""))])
	return out


## The record lands on the carrier with its scope, and the two reads split:
## the bridge arms `unstoppable` at the shooting seam only, the Regeneration
## bypass answers the shooting half only.
func test_the_aura_arms_the_shooting_clamp_only() -> void:
	_inject_aura_map()
	var carrier := _aura_carrier()
	_main._solo_apply_utility_buffs(carrier)
	var scopes := _record_scopes(carrier)
	assert_array(scopes) \
		.override_failure_message("the aura's record must land on the carrier with its scope " +
			"(records: %s)" % str(scopes)) \
		.contains(["Unstoppable|shooting"])
	var shot: Dictionary = _main._solo_bridge_granted_flags(carrier, {"range": 24}, null)
	assert_bool(bool(shot.get("unstoppable", false))) \
		.override_failure_message("the shooting-scoped aura must arm the SHOOTING clamp " +
			"(bridged profile: %s)" % str(shot)) \
		.is_true()
	var strike: Dictionary = _main._solo_bridge_granted_flags(carrier, {"range": 0}, null)
	assert_bool(bool(strike.get("unstoppable", false))) \
		.override_failure_message("the shooting-scoped aura must NOT arm the MELEE clamp " +
			"(bridged profile: %s)" % str(strike)) \
		.is_false()


func test_the_auras_regeneration_half_answers_shooting_only() -> void:
	_inject_aura_map()
	var carrier := _aura_carrier()
	_main._solo_apply_utility_buffs(carrier)
	assert_bool(_main._solo_ignores_regen(carrier, {"range": 24})) \
		.override_failure_message("the aura's Regeneration half must fire when shooting") \
		.is_true()
	assert_bool(_main._solo_ignores_regen(carrier, {"range": 0})) \
		.override_failure_message("the shooting-scoped aura must NOT cut through MELEE " +
			"Regeneration (the defect)") \
		.is_false()
	# CONTROL — the printed plain rule answers BOTH halves, before and after
	# the split: only the live grant's scope decides.
	var printed := _aura_carrier_printer()
	assert_bool(_main._solo_ignores_regen(printed, {"range": 24})) \
		.override_failure_message("control: the printed rule answers when shooting") \
		.is_true()
	assert_bool(_main._solo_ignores_regen(printed, {"range": 0})) \
		.override_failure_message("control: the printed rule answers in melee too") \
		.is_true()


## The both-halves control: a unit whose own rule is the plain printed
## "Unstoppable" — no aura, no record.
func _aura_carrier_printer() -> GameUnit:
	var carrier := E2EBoot.make_unit(_main, 1, "Printed", [Vector3(0.5, 0, 0.5)])
	carrier.unit_properties["game_system"] = "gf"
	carrier.unit_properties["faction_folder"] = "testfac"
	carrier.unit_properties["special_rules"] = ["Unstoppable"]
	return carrier


## The actual leak, pinned: a RECIPIENT of the aura grant — its overlay
## "Unstoppable (spell)" made `has_exact_rule` answer in both halves on main,
## so a friendly unit granted the shooting aura cut through MELEE
## Regeneration. The record's scope is what closes it.
func test_the_granted_overlay_stays_out_of_melee_regeneration() -> void:
	_inject_aura_map()
	var ally := E2EBoot.make_unit(_main, 1, "Ally", [Vector3(0.5, 0, 0.5)])
	ally.unit_properties["game_system"] = "gf"
	ally.unit_properties["faction_folder"] = "testfac"
	_main.opr_army_manager.game_units[ally.unit_id] = ally
	_main.opr_army_manager.current_round = 1
	# The same record seam `_solo_apply_utility_buffs` drives, aimed at the
	# recipient: overlay "Unstoppable (spell)" + the scoped record.
	_main._solo_record_spell_mod(ally, "Unstoppable when Shooting Aura",
		{"grants_rule": "Unstoppable", "scope": "shooting", "duration": "round"})
	assert_bool(_main._solo_ignores_regen(ally, {"range": 24})) \
		.override_failure_message("the granted overlay must bypass Regeneration when shooting") \
		.is_true()
	assert_bool(_main._solo_ignores_regen(ally, {"range": 0})) \
		.override_failure_message("the granted overlay must NOT bypass MELEE Regeneration " +
			"(the scope-blind exact-name line answered both halves)") \
		.is_false()
