extends GdUnitTestSuite
## Rules 3.6 row MOR-14 (lead ruling D-SPELL-LOS): a spell needs line of sight only when its own entry
## carries `needs_los: true`; everything else reaches a target in range even when nobody can see it.
## Rules 3.5 (the frozen EPOCH_72 leg) still required sight for every spell — the `_at_epoch_72`
## controls below pin that, read through the real engine's live seam (the twin's version of these three
## rules is the core's: core/nml-core/src/tests/sim/v36_mor_14.rs).

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests: restore


func _unit(pid: int, uid: String, positions: Array, rules: Array = [],
		faction: String = "", tokens: int = 0) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules, "faction_folder": faction, "game_system": "gf"}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.wounds_max = 1
		m.unit = u
		var n: Node3D = auto_free(Node3D.new())
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	u.casts_current = tokens
	u.casts_per_round = tokens
	return u


## The real-engine fixture: the SoloController fixture style, P1 caster vs P2 enemy 3" away, with a
## sight checker that answers "no" for every pair.
func _solo_hidden() -> Dictionary:
	var caster := _unit(1, "caster", [Vector3.ZERO])
	var foe := _unit(2, "foe", [Vector3(3.0 * IN2M, 0, 0)])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {caster.unit_id: caster, foe.unit_id: foe}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.unit_los_checker = func(_a: GameUnit, _b: GameUnit) -> bool: return false
	return {"solo": solo, "caster": caster}


func _candidate_ids(table: Dictionary, entry: Dictionary) -> Array:
	var ids: Array = []
	for c in (table["solo"] as SoloController).spell_candidates(
			table["caster"] as GameUnit, entry, 1, 2):
		ids.append((c as GameUnit).unit_id)
	return ids


# --- the real engine (SoloController.spell_candidates) ----------------------------------------

func test_a_spell_without_the_clause_targets_a_hidden_unit_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var entry := SpellsRegistry.entry_for("gf", "dao_union", "Deadly Surge")
	assert_array(_candidate_ids(_solo_hidden(), entry)).contains(["foe"])


func test_a_spell_with_the_clause_refuses_a_hidden_unit_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var entry := SpellsRegistry.entry_for("gf", "alien_hives", "Hive Shriek")
	assert_array(_candidate_ids(_solo_hidden(), entry)).not_contains(["foe"])


func test_every_spell_needs_sight_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var entry := SpellsRegistry.entry_for("gf", "dao_union", "Deadly Surge")
	assert_array(_candidate_ids(_solo_hidden(), entry)).not_contains(["foe"])
