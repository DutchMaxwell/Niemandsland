extends GdUnitTestSuite
## NML-1046 M1: tools/core_selfplay.gd hand-builds GameUnits via GameUnit.new()
## in _units_from_list(), bypassing the equipment-import path that normally
## calls initialize_caster_points() (scripts/equipment_distributor.gd:394).
## Without the grant, every core-generated unit entered BattleSim.capture()
## with casts_current == 0 and BattleSim.spell_ev_of() always saw tokens <= 0
## — thousands of core games, zero spells.
##
## This suite drives a NON-RUNNING SceneTree.new() instance of
## core_selfplay.gd directly: _units_from_list() is an INSTANCE method that
## parents model nodes under `root` (the SceneTree's own root Window, valid
## even when the tree is never started as the main loop). Each test frees
## that tree at the end of its body so gdUnit samples 0 orphans.

const CoreSelfplayScript := preload("res://tools/core_selfplay.gd")

var _seq := 0


func _write_list(units: Array, gsys: String = "gf") -> String:
	_seq += 1
	var path := "user://test_caster_list_%d.json" % _seq
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"gameSystem": gsys, "units": units}))
	fa.close()
	return path


func _unit_spec(id: String, size: int, rules: Array, sel: String = "",
		join: Variant = null, combined: bool = false) -> Dictionary:
	return {"id": id, "name": id, "size": size, "quality": 4, "defense": 4,
		"rules": rules, "weapons": [], "selectionId": sel, "joinToUnit": join,
		"combined": combined}


## Adds ONE selectedUpgrades entry (option label only — this fixture format
## never carries typed "gains", see core_selfplay.gd:_rules_in_upgrade_label).
func _with_upgrade(spec: Dictionary, option_label: String) -> Dictionary:
	spec["selectedUpgrades"] = [{"option": {"label": option_label}}]
	return spec


## (a) A Caster(X) list unit is granted X tokens after the build.
func test_caster_list_unit_gets_tokens() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_unit_spec("Wizard", 1,
		[{"name": "Caster", "rating": 2, "label": "Caster(2)"}])])
	var units: Array = cs._units_from_list(path, 1)
	assert_int(units.size()).is_equal(1)
	assert_int((units[0] as GameUnit).casts_current).is_equal(2)
	cs.free()


## (b) Discriminator: a unit with no caster rule stays at 0 tokens. This case
## must stay GREEN under the red toggle that stubs the grant body with `pass`.
func test_non_caster_list_unit_keeps_zero_tokens() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_unit_spec("Grunts", 5,
		[{"name": "Tough", "rating": 3, "label": "Tough(3)"}])])
	var units: Array = cs._units_from_list(path, 1)
	assert_int(units.size()).is_equal(1)
	assert_int((units[0] as GameUnit).casts_current).is_equal(0)
	cs.free()


## (c) Ordering guard: Caster Group's X is the ALIVE MODEL COUNT of the unit
## (game_unit.gd get_caster_value), and a combined pair folds its partner's
## models into the host in the pass just above the grant loop. The grant must
## run AFTER that fold, or it only sees the host's own pre-combine models.
func test_caster_group_grant_counts_the_combined_models() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var host := _unit_spec("Musician", 2,
		[{"name": "Caster Group", "label": "Caster Group"}], "hostSel")
	var partner := _unit_spec("Musician_B", 3,
		[{"name": "Caster Group", "label": "Caster Group"}], "partnerSel", "hostSel", true)
	var path := _write_list([host, partner])
	var units: Array = cs._units_from_list(path, 1)
	assert_int(units.size()).is_equal(1)   # the combined partner folds into the host
	assert_int((units[0] as GameUnit).casts_current).is_equal(5)   # 2 + 3 combined models
	cs.free()


## (d) Per-model grant semantics: Caster Group's X is the unit's ALIVE model
## count (game_unit.gd get_caster_value), re-evaluated on each grant, not a
## count frozen at build time. Killing a model and re-granting must drop the
## pool — the same shared method the fix now calls stays correct under
## casualties, the exact quantity the build-time ordering guard (c) depends on.
func test_caster_group_tokens_recount_after_casualties() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_unit_spec("Musician", 4,
		[{"name": "Caster Group", "label": "Caster Group"}])])
	var units: Array = cs._units_from_list(path, 1)
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(4)
	(unit.models[0] as ModelInstance).is_alive = false
	unit.initialize_caster_points()
	assert_int(unit.casts_current).is_equal(3)
	cs.free()


## NML-1066 (a): an UPGRADE-granted Caster (selectedUpgrades option label, not
## a printed unit rule) must reach the unit and grant its tokens — the real
## import path resolves this from the option's typed "gains"
## (opr_api_client.gd:850); the trainer's list fixture only carries the label.
func test_upgrade_granted_caster_gets_tokens() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_with_upgrade(
		_unit_spec("Master Brother", 1, []), "Archivist (Caster(2))")])
	var units: Array = cs._units_from_list(path, 1)
	assert_int(units.size()).is_equal(1)
	assert_int((units[0] as GameUnit).casts_current).is_equal(2)
	cs.free()


## NML-1066 (b): an option label with NO parenthesized tail is a plain
## weapon/item swap (e.g. "Replace CCW" -> "Iron Sights"), not a rule grant.
func test_upgrade_option_without_parens_grants_nothing() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_with_upgrade(
		_unit_spec("Trooper", 1, []), "Iron Sights")])
	var units: Array = cs._units_from_list(path, 1)
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(0)
	assert_array(unit.get_special_rules()).is_empty()
	cs.free()


## NML-1066 (c): a printed Caster(1) AND an upgrade-granted "Seer (Caster(2))"
## both land in special_rules (printed rule first, upgrade rule appended after
## it), but game_unit.gd:get_caster_value() returns on the FIRST "Caster("
## match it finds — so the PRINTED value wins, not the higher one. Pinning
## this actual (first-listed) behavior, not a max/combine that doesn't exist.
func test_upgrade_caster_alongside_printed_caster_keeps_printed_value() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_with_upgrade(_unit_spec("Hybrid Caster", 1,
		[{"name": "Caster", "rating": 1, "label": "Caster(1)"}]), "Seer (Caster(2))")])
	var units: Array = cs._units_from_list(path, 1)
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(1)
	var rules := unit.get_special_rules()
	assert_bool(rules.has("Caster(1)")).is_true()
	assert_bool(rules.has("Caster(2)")).is_true()
	cs.free()


## NML-1066 (d): a multi-rule option label grants EVERY comma-separated rule
## inside the outer parentheses, e.g. "Champion (Fear, Caster(1))" grants both
## "Fear" and "Caster(1)" (the inner "(1)" stays part of the Caster label).
func test_upgrade_multi_rule_label_grants_all_of_them() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_with_upgrade(
		_unit_spec("Champion Bearer", 1, []), "Champion (Fear, Caster(1))")])
	var units: Array = cs._units_from_list(path, 1)
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(1)
	assert_bool(unit.has_special_rule("Fear")).is_true()
	assert_bool(unit.has_special_rule("Caster(1)")).is_true()
	cs.free()


## NML-1066: the combined-partner second pass (_append_selection at the
## joinToUnit fold, core_selfplay.gd ~line 393) must ALSO pick up its OWN
## selectedUpgrades rules onto the shared host — a caster hero folded into a
## unit via combined:true must not lose its upgrade-granted Caster.
func test_combined_partner_upgrade_caster_reaches_the_host() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var host := _unit_spec("Grunts", 2, [], "hostSel")
	var partner := _with_upgrade(
		_unit_spec("Archivist", 1, [], "partnerSel", "hostSel", true), "Archivist (Caster(2))")
	var path := _write_list([host, partner])
	var units: Array = cs._units_from_list(path, 1)
	assert_int(units.size()).is_equal(1)
	assert_int((units[0] as GameUnit).casts_current).is_equal(2)
	cs.free()


## NML-1066 (e) guard: a WEAPON-SWAP option's label also carries a parenthesized
## tail (its profile) — "Energy Sword (A2, AP(1), Rending)" must grant NOTHING,
## not leak "A2"/"AP(1)"/"Rending" into unit-wide special_rules.
func test_upgrade_weapon_swap_profile_grants_nothing() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_with_upgrade(
		_unit_spec("Swordsman", 1, []), "Energy Sword (A2, AP(1), Rending)")])
	var units: Array = cs._units_from_list(path, 1)
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(0)
	assert_array(unit.get_special_rules()).is_empty()
	cs.free()


## NML-1066 (f) guard: same, for a RANGED weapon profile — the leading `24"`
## range figure must also void the whole label.
func test_upgrade_weapon_swap_with_range_grants_nothing() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_list([_with_upgrade(
		_unit_spec("Rifleman", 1, []), "Heavy Rifle (24\", A1, AP(1))")])
	var units: Array = cs._units_from_list(path, 1)
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(0)
	assert_array(unit.get_special_rules()).is_empty()
	cs.free()
