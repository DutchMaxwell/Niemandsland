extends GdUnitTestSuite
## NML-1046 M2a: tools/core_selfplay.gd played spell casts SILENTLY — back then
## the cast folded into the shoot volley inside BattleSim.resolve() (a rider
## NML-1069 replaced with the _cast_phase sub-phase) and the result JSON never
## carried a counter. This suite drives the pieces directly: _magic_init
## (roster-time granted/caster/book counts), _magic_tally (the played-actions-
## only per-cast counter), _spells_by_kind_tally (NML-1069: WHICH kind was
## cast) and the "magic" key landing in _write_result's JSON stamp.
##
## Fixture recipe mirrors test/core_selfplay_caster_test.gd: a NON-RUNNING
## SceneTree.new() instance of core_selfplay.gd, _units_from_list() parenting
## model nodes under `root` (valid even though the tree never runs as the
## main loop). Each test frees that tree at the end so gdUnit samples 0
## orphans.

const CoreSelfplayScript := preload("res://tools/core_selfplay.gd")

var _seq := 0


## Filename drives faction resolution the same way the real CLI args do
## (_units_from_list: faction = basename with its last "_"-segment stripped),
## so the fixture picks its faction by CHOOSING the path, not by stamping a
## property after the fact.
func _write_faction_list(faction: String, units: Array, gsys: String = "gf") -> String:
	_seq += 1
	var path := "user://%s_seq%d.json" % [faction, _seq]
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"gameSystem": gsys, "units": units}))
	fa.close()
	return path


func _unit_spec(id: String, size: int, rules: Array) -> Dictionary:
	return {"id": id, "name": id, "size": size, "quality": 4, "defense": 4,
		"rules": rules, "weapons": [], "selectionId": "", "joinToUnit": null,
		"combined": false}


## (a) A resolvable-faction caster fixture (p1: battle_brothers, a faction the
## committed gf spell map fields) vs. a non-caster fixture (p2): granted,
## casters and books_resolved land on p1 only, and p2 stays all-zero.
func test_magic_init_counts_granted_casters_and_books_for_resolving_faction() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var caster_path := _write_faction_list("battle_brothers",
		[_unit_spec("Wizard", 1, [{"name": "Caster", "rating": 2, "label": "Caster(2)"}])])
	var plain_path := _write_faction_list("no_such_faction",
		[_unit_spec("Grunts", 5, [{"name": "Tough", "rating": 3, "label": "Tough(3)"}])])
	var units1: Array = cs._units_from_list(caster_path, 1)
	var units2: Array = cs._units_from_list(plain_path, 2)
	var magic: Dictionary = cs._magic_init(units1, units2)
	assert_int(int((magic["granted"] as Dictionary)["p1"])).is_equal(2)
	assert_int(int((magic["casters"] as Dictionary)["p1"])).is_equal(1)
	assert_int(int((magic["books_resolved"] as Dictionary)["p1"])).is_equal(1)
	assert_int(int((magic["granted"] as Dictionary)["p2"])).is_equal(0)
	assert_int(int((magic["casters"] as Dictionary)["p2"])).is_equal(0)
	assert_int(int((magic["books_resolved"] as Dictionary)["p2"])).is_equal(0)
	cs.free()


## (b) Discriminator: a caster fixture under a faction_folder with NO
## committed spell map ("no_such_faction") is still a caster (tokens granted,
## casters counted) but books_resolved must stay 0 — the count needs BOTH
## casts_current > 0 AND a non-empty SpellsRegistry.spells_for_unit() list.
func test_magic_init_books_resolved_zero_without_a_committed_spell_map() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_faction_list("no_such_faction",
		[_unit_spec("Wizard", 1, [{"name": "Caster", "rating": 3, "label": "Caster(3)"}])])
	var units1: Array = cs._units_from_list(path, 1)
	var magic: Dictionary = cs._magic_init(units1, [])
	assert_int(int((magic["granted"] as Dictionary)["p1"])).is_equal(3)
	assert_int(int((magic["casters"] as Dictionary)["p1"])).is_equal(1)
	assert_int(int((magic["books_resolved"] as Dictionary)["p1"])).is_equal(0)
	cs.free()


## (c) Tally: a positive token delta across the played apply is exactly one
## cast event, counted with its cost.
func test_magic_tally_counts_a_positive_delta_as_one_cast() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var magic := {"casts": {"p1": 0, "p2": 0}, "tokens_spent": {"p1": 0, "p2": 0}}
	cs._magic_tally(magic, "p1", 4, 2)
	assert_int(int((magic["casts"] as Dictionary)["p1"])).is_equal(1)
	assert_int(int((magic["tokens_spent"] as Dictionary)["p1"])).is_equal(2)
	cs.free()


## (d) An unchanged token count (no spell cast this activation) leaves the
## tally untouched.
func test_magic_tally_ignores_an_unchanged_token_count() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var magic := {"casts": {"p1": 0, "p2": 0}, "tokens_spent": {"p1": 0, "p2": 0}}
	cs._magic_tally(magic, "p1", 2, 2)
	assert_int(int((magic["casts"] as Dictionary)["p1"])).is_equal(0)
	assert_int(int((magic["tokens_spent"] as Dictionary)["p1"])).is_equal(0)
	cs.free()


## (e) A negative delta (tokens went UP, e.g. a round refresh landing between
## reads) must never be mistaken for a cast.
func test_magic_tally_ignores_a_negative_delta() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var magic := {"casts": {"p1": 0, "p2": 0}, "tokens_spent": {"p1": 0, "p2": 0}}
	cs._magic_tally(magic, "p1", 2, 3)
	assert_int(int((magic["casts"] as Dictionary)["p1"])).is_equal(0)
	assert_int(int((magic["tokens_spent"] as Dictionary)["p1"])).is_equal(0)
	cs.free()


## NML-1069: the per-kind split counts ONLY the events this activation added —
## `from` is the round log's size read pre-apply, so the round's earlier casts
## (and any kind the ledger does not carry) never double-count.
func test_spells_by_kind_counts_only_this_activations_events() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var magic := {"spells_by_kind": {"p1": {"damage": 0, "buff": 0, "debuff": 0},
		"p2": {"damage": 0, "buff": 0, "debuff": 0}}}
	var events := [{"kind": "damage"}, {"kind": "buff"}, {"kind": "debuff"}, {"kind": "???"}]
	cs._spells_by_kind_tally(magic, "p1", events, 1)
	var by_kind: Dictionary = (magic["spells_by_kind"] as Dictionary)["p1"]
	assert_int(int(by_kind["damage"])).is_equal(0)   # index 0 predates this apply
	assert_int(int(by_kind["buff"])).is_equal(1)
	assert_int(int(by_kind["debuff"])).is_equal(1)
	assert_int(int((magic["spells_by_kind"] as Dictionary)["p2"]["buff"])).is_equal(0)
	cs.free()


## (f) The result stamp: _write_result must land a "magic" key in the JSON
## it writes, carrying the harness's live _magic dict through unchanged.
func test_write_result_stamps_the_magic_block() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var out_dir := ProjectSettings.globalize_path("user://test_magic_stamp_out")
	cs._out = out_dir
	cs._army1 = "a1"
	cs._army2 = "a2"
	cs._magic = {"granted": {"p1": 3, "p2": 0}, "casters": {"p1": 1, "p2": 0},
		"books_resolved": {"p1": 1, "p2": 0}, "casts": {"p1": 2, "p2": 0},
		"tokens_spent": {"p1": 3, "p2": 0}}
	cs._write_result(4242, [], [])
	var f := FileAccess.open(out_dir.path_join("core_s4242.json"), FileAccess.READ)
	assert_bool(f != null).is_true()
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_bool(data is Dictionary).is_true()
	var d := data as Dictionary
	assert_bool(d.has("magic")).is_true()
	var magic := d["magic"] as Dictionary
	assert_int(int((magic["casts"] as Dictionary)["p1"])).is_equal(2)
	assert_int(int((magic["tokens_spent"] as Dictionary)["p1"])).is_equal(3)
	assert_int(int((magic["granted"] as Dictionary)["p1"])).is_equal(3)
	cs.free()


## NML-1064 (a): the round-start refill helper syncs the sim's decremented
## su["casts"] onto the live GameUnit, calls add_round_caster_points() (the
## SAME accumulate+cap-6 method the real game calls each round,
## game_unit.gd:426) and writes the refreshed value back onto BOTH su["casts"]
## and the GameUnit — a Caster(2) unit that the sim had spent down to 1 token
## refills to 3 (1 + 2), not back up to the build-time 2.
func test_refill_round_caster_points_adds_the_per_round_grant() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_faction_list("battle_brothers",
		[_unit_spec("Wizard", 1, [{"name": "Caster", "rating": 2, "label": "Caster(2)"}])])
	var units: Array = cs._units_from_list(path, 1)
	var gu := units[0] as GameUnit
	var magic: Dictionary = cs._magic_init(units, [])
	var su := {"unit": gu, "casts": 1, "player": 1}
	cs._refill_round_caster_points(su, magic, "p1")
	assert_int(int(su["casts"])).is_equal(3)
	assert_int(gu.casts_current).is_equal(3)
	cs.free()


## NML-1064 (b): the same cap the real game enforces (Caster(X): "can't hold
## more than 6 tokens at once") — 5 unspent tokens plus a Caster(2) refill
## clamps to 6, not 7.
func test_refill_round_caster_points_caps_at_six() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_faction_list("battle_brothers",
		[_unit_spec("Wizard", 1, [{"name": "Caster", "rating": 2, "label": "Caster(2)"}])])
	var units: Array = cs._units_from_list(path, 1)
	var gu := units[0] as GameUnit
	var magic: Dictionary = cs._magic_init(units, [])
	var su := {"unit": gu, "casts": 5, "player": 1}
	cs._refill_round_caster_points(su, magic, "p1")
	assert_int(int(su["casts"])).is_equal(6)
	assert_int(gu.casts_current).is_equal(6)
	cs.free()


## NML-1064 (c): a non-caster (casts_per_round stays 0, add_round_caster_points'
## own guard is a no-op) must stay at 0 tokens through a refill — no duplicated
## guard logic in the helper, just the method's existing behaviour.
func test_refill_round_caster_points_leaves_a_non_caster_at_zero() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var path := _write_faction_list("no_such_faction",
		[_unit_spec("Grunts", 5, [{"name": "Tough", "rating": 3, "label": "Tough(3)"}])])
	var units: Array = cs._units_from_list(path, 1)
	var gu := units[0] as GameUnit
	var magic: Dictionary = cs._magic_init(units, [])
	var su := {"unit": gu, "casts": 0, "player": 1}
	cs._refill_round_caster_points(su, magic, "p1")
	assert_int(int(su["casts"])).is_equal(0)
	assert_int(gu.casts_current).is_equal(0)
	cs.free()


## NML-1064 (d): eligibility counters — "never eligible" (no tokens, or no
## living enemy within spell range) vs "eligible but chose not to cast" needs
## its own denominator. A hand-built two-unit state: the actor carries 1 token
## and a fixture spell book with ONE range_in(12) entry. An enemy at 6" is
## within range (both counters tick); the SAME actor re-probed against an
## enemy at 30" is still a caster activation but NOT an in-range one.
func test_magic_eligibility_tally_counts_caster_and_in_range_activations() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	SpellsRegistry.reset_cache()
	var gf_map: Dictionary = (SpellsRegistry.map_for("gf") as Dictionary).duplicate(true)
	var factions: Dictionary = gf_map.get("factions", {})
	factions["nml_1064_fixture"] = {"spells": [{"name": "Fixture Bolt", "threshold": 1,
		"range_in": 12, "target": {"side": "enemy", "count": 1, "kind": "unit"},
		"effect": {"kind": "damage", "hits": 1}, "status": "modeled"}]}
	gf_map["factions"] = factions
	SpellsRegistry._cache["gf"] = gf_map
	var actor := GameUnit.new()
	actor.unit_id = "actor"
	actor.unit_properties = {"player_id": 1, "name": "Actor", "quality": 4, "defense": 4,
		"special_rules": ["Caster(1)"], "game_system": "gf", "faction_folder": "nml_1064_fixture"}
	var magic: Dictionary = cs._magic_init([], [])
	var im: float = CoreSelfplayScript.IN2M
	var state_near := {"units": {
		"actor": {"unit": actor, "casts": 1, "player": 1, "alive": 1, "positions": [Vector3.ZERO]},
		"enemy": {"player": 2, "alive": 1, "positions": [Vector3(6.0 * im, 0, 0)]}}}
	cs._magic_eligibility_tally(magic, "p1", state_near, "actor")
	assert_int(int((magic["caster_activations"] as Dictionary)["p1"])).is_equal(1)
	assert_int(int((magic["in_range_activations"] as Dictionary)["p1"])).is_equal(1)
	var state_far := {"units": {
		"actor": {"unit": actor, "casts": 1, "player": 1, "alive": 1, "positions": [Vector3.ZERO]},
		"enemy": {"player": 2, "alive": 1, "positions": [Vector3(30.0 * im, 0, 0)]}}}
	cs._magic_eligibility_tally(magic, "p1", state_far, "actor")
	assert_int(int((magic["caster_activations"] as Dictionary)["p1"])).is_equal(2)
	assert_int(int((magic["in_range_activations"] as Dictionary)["p1"])).is_equal(1)
	SpellsRegistry.reset_cache()
	cs.free()
