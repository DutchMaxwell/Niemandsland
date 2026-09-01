# GdUnit generated TestSuite
extends GdUnitTestSuite
## D8a (NML-1073 M5) — the rulebook objective layout: the book's three constraints,
## the pinned draw order, and determinism per seed.

const FRONT_LINE := {"zones": {
	"1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
	"2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]]}}
const DUEL := {"markers": {"count": "d3+2", "placement": "alternate"}}
## NML-1140 step 6: the doctrine fixture armies are the smoke's pinned two-unit
## pair — LOADED, not copied: the smoke and the pyo3 reference are the ONE
## fixture in two languages ("change both or neither"), and a third copy here
## would be a third thing to keep in step.
const SMOKE := preload("res://tools/objective_doctrine_smoke.gd")
## The pinned seed block: seeds 20260710..20260714 draw counts 5,3,5,3,5 from
## the D3+2 stream (probe-verified 2026-09-01) — the RED's leverage below rides
## the 5 -> 3 flip between the first seed and its +1 neighbour.
const SEED_BASE := 20260710
## NML-1140 follow-up: the doctrine rung's own answer only exists behind the
## NmlCore GDExtension (core/install_gdextension.sh) — absent in CI and in a
## plain player install. The cases below that assert the ACTUAL doctrine
## answer (not the fallback) skip loudly (gdUnit `do_skip`/`skip_reason`,
## evaluated at scan time — literal text only, gdUnit reads it straight off
## the source, not through the class) rather than fail when it is missing;
## the rulebook/legality/round-trip cases above and `test_an_unplaceable_
## doctrine_falls_back_loudly_and_honestly` below (it tests the FALLBACK
## itself) run unconditionally.


func _armies() -> Array:
	return [SMOKE._army("p1"), SMOKE._army("p2")]


func _cells(pairs: Array = []) -> Dictionary:
	var d := {}
	for p in pairs:
		d[Vector2i(p[0], p[1])] = p[2]
	return d


func test_the_count_is_d3_plus_2_and_the_layout_is_legal() -> void:
	for s in range(30):
		var lay := ObjectiveLayout.generate(20260710 + s, DUEL, FRONT_LINE, _cells(), 30)
		assert_int(int(lay["count_roll"])).is_between(3, 5)
		assert_int((lay["positions"] as Array).size()).is_equal(int(lay["count_roll"]))
		assert_int(int(lay["first_placer"])).is_between(1, 2)
		assert_int(int(lay["swept"])).is_equal(0)
		var pos: Array = lay["positions"]
		for i in range(pos.size()):
			# Every marker must be legal against every OTHER marker, so the placement
			# order cannot hide an illegal pair.
			var others: Array = []
			for j in range(pos.size()):
				if j != i:
					others.append(pos[j])
			assert_bool(ObjectiveLayout.is_legal(int(pos[i][0]), int(pos[i][1]),
				others, FRONT_LINE, _cells(), 30)).is_true()
			assert_int(absi(int(pos[i][0]))).is_less_equal(36 - ObjectiveLayout.EDGE_MARGIN_IN)
			assert_int(absi(int(pos[i][1]))).is_less_equal(24 - ObjectiveLayout.EDGE_MARGIN_IN)


func test_the_placers_alternate_from_the_roll_off_winner() -> void:
	var lay := ObjectiveLayout.generate(20260710, DUEL, FRONT_LINE, _cells(), 30)
	var by: Array = lay["placed_by"]
	var first := int(lay["first_placer"])
	assert_int(by.size()).is_equal(int(lay["count_roll"]))
	for i in range(by.size()):
		assert_int(int(by[i])).is_equal(first if i % 2 == 0 else 3 - first)


func test_the_same_seed_gives_the_same_layout_and_a_different_seed_does_not() -> void:
	var a := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30)
	var b := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30)
	assert_that(a["positions"]).is_equal(b["positions"])
	assert_int(int(a["count_roll"])).is_equal(int(b["count_roll"]))
	var c := ObjectiveLayout.generate(4243, DUEL, FRONT_LINE, _cells(), 30)
	assert_bool(a["positions"] == c["positions"]).is_false()


func test_over_nine_inches_means_nine_exactly_is_illegal() -> void:
	# The one boundary the book states in words, and the one an off-by-one passes.
	assert_bool(ObjectiveLayout.is_legal(9, 0, [[0, 0]], {}, _cells(), 30)).is_false()
	assert_bool(ObjectiveLayout.is_legal(10, 0, [[0, 0]], {}, _cells(), 30)).is_true()


func test_the_deployment_zone_boundary_counts_as_inside() -> void:
	assert_bool(ObjectiveLayout.is_legal(0, -12, [], FRONT_LINE, _cells(), 30)).is_false()
	assert_bool(ObjectiveLayout.is_legal(0, -20, [], FRONT_LINE, _cells(), 30)).is_false()
	assert_bool(ObjectiveLayout.is_legal(0, -11, [], FRONT_LINE, _cells(), 30)).is_true()


func test_an_impassable_cell_is_unreachable() -> void:
	# n = 30, 3" cells: inches (1, 1) fall in cell (15, 15).
	var blocked := _cells([[15, 15, TerrainRules.TerrainType.CONTAINER]])
	assert_bool(ObjectiveLayout.is_legal(1, 1, [], {}, blocked, 30)).is_false()
	var wood := _cells([[15, 15, TerrainRules.TerrainType.FOREST]])
	assert_bool(ObjectiveLayout.is_legal(1, 1, [], {}, wood, 30)).is_true()


func test_a_fixed_count_spec_draws_nothing_and_shifts_no_later_draw() -> void:
	# A NUMBER count must not consume a die — otherwise every later draw moves and the
	# Rust mirror's `count_of` (which mirrors the same type test) diverges.
	var fixed := {"markers": {"count": 4, "placement": "alternate"}}
	var lay := ObjectiveLayout.generate(99, fixed, FRONT_LINE, _cells(), 30)
	assert_int(int(lay["count_roll"])).is_equal(4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# The first draw of the stream must therefore be the ROLL-OFF, not the count.
	assert_int(int(lay["first_placer"])).is_equal(ObjectiveLayout._roll_off(rng))


# === NML-1140 step 6: the doctrine rung =======================================

@warning_ignore('unused_parameter')
func test_the_doctrine_rung_keeps_the_stream_and_places_legal_markers(
		do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded — doctrine rung untestable without it") -> void:
	for s in range(5):
		var lay := ObjectiveLayout.generate(SEED_BASE + s, DUEL, FRONT_LINE, _cells(), 30,
			72.0, 48.0, "search", _armies())
		# The stream contract: same count/roll-off draws as the rulebook of the seed,
		# the rung rides "doctrine" beside "mode": "rulebook" (the twin's stamp key).
		assert_int(int(lay["count_roll"])).is_between(3, 5)
		assert_int(int(lay["first_placer"])).is_between(1, 2)
		assert_str(str(lay["mode"])).is_equal("rulebook")
		assert_str(str(lay["doctrine"])).is_equal("search")
		assert_int((lay["positions"] as Array).size()).is_equal(int(lay["count_roll"]))
		assert_int(int(lay["swept"])).is_equal(0)
		# Every marker legal against every OTHER marker, zones and edges — the
		# table's own re-verification the design mandates.
		var pos: Array = lay["positions"]
		for i in range(pos.size()):
			var others: Array = []
			for j in range(pos.size()):
				if j != i:
					others.append(pos[j])
			assert_bool(ObjectiveLayout.is_legal(int(pos[i][0]), int(pos[i][1]),
				others, FRONT_LINE, _cells(), 30)).is_true()
			assert_int(absi(int(pos[i][0]))).is_less_equal(36 - ObjectiveLayout.EDGE_MARGIN_IN)
			assert_int(absi(int(pos[i][1]))).is_less_equal(24 - ObjectiveLayout.EDGE_MARGIN_IN)


@warning_ignore('unused_parameter')
func test_the_doctrine_rung_is_deterministic_and_the_rulebook_stamps_no_rung(
		do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded — doctrine rung untestable without it") -> void:
	var a := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30,
		72.0, 48.0, "search", _armies())
	var b := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30,
		72.0, 48.0, "search", _armies())
	assert_that(a).is_equal(b)
	var rb := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30)
	assert_bool(rb.has("doctrine")).is_false()


@warning_ignore('unused_parameter')
func test_the_doctrine_respects_the_board_it_is_handed(
		do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded — doctrine rung untestable without it") -> void:
	# The board travels to the doctrine as the act header's terrain line; blocking
	# the open-board answer's cells must MOVE the deterministic answer (or the
	# terrain never reached the Rust search), and the moved answer stays legal.
	var blocked := _cells([[15, 15, TerrainRules.TerrainType.CONTAINER],
		[14, 15, TerrainRules.TerrainType.CONTAINER], [18, 14, TerrainRules.TerrainType.CONTAINER]])
	var open := ObjectiveLayout.generate(SEED_BASE, DUEL, FRONT_LINE, _cells(), 30,
		72.0, 48.0, "search", _armies())
	var on_blocks := ObjectiveLayout.generate(SEED_BASE, DUEL, FRONT_LINE, blocked, 30,
		72.0, 48.0, "search", _armies())
	assert_bool(open["positions"] == on_blocks["positions"]).is_false()
	var pos: Array = on_blocks["positions"]
	for i in range(pos.size()):
		var others: Array = []
		for j in range(pos.size()):
			if j != i:
				others.append(pos[j])
		assert_bool(ObjectiveLayout.is_legal(int(pos[i][0]), int(pos[i][1]),
			others, FRONT_LINE, blocked, 30)).is_true()


func test_an_unplaceable_doctrine_falls_back_loudly_and_honestly() -> void:
	# An unknown rung is refused by the Rust dispatcher (the pyo3 RED of step 5);
	# the table answers with the seed's rulebook draw and stamps "fallback" —
	# the gate reads that RED, so no silent fallback can pass.
	var rb := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30)
	var lay := ObjectiveLayout.generate(4242, DUEL, FRONT_LINE, _cells(), 30,
		72.0, 48.0, "aggressive", _armies())
	assert_str(str(lay["doctrine"])).is_equal("fallback")
	assert_that(lay["positions"]).is_equal(rb["positions"])
	assert_int(int(lay["count_roll"])).is_equal(int(rb["count_roll"]))
	assert_int(int(lay["first_placer"])).is_equal(int(rb["first_placer"]))
	# Same for a draw the doctrine cannot serve at all: the extension refuses
	# count > 5 first (8^count blow-up), the fallback keeps the game honest.
	var six := {"markers": {"count": 6, "placement": "alternate"}}
	var big := ObjectiveLayout.generate(4242, six, FRONT_LINE, _cells(), 30,
		72.0, 48.0, "search", _armies())
	assert_str(str(big["doctrine"])).is_equal("fallback")
	assert_int(int(big["count_roll"])).is_equal(6)


@warning_ignore('unused_parameter')
func test_the_doctrine_matches_the_twin_on_five_seeds(
		do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded — doctrine rung untestable without it") -> void:
	# Gate 2(ii) on the table side: the extension's markers must equal the twin's
	# pyo3 markers for the SAME drawn count, on five pinned seeds (counts 5,3,5,3,5).
	var python := OS.get_environment("NML_DOCTRINE_PYO3_PYTHON")
	assert_str(python).override_failure_message(
		"NML_DOCTRINE_PYO3_PYTHON is unset — point it at a python importing nml_core from this commit (maturin develop -m core/nml-core-py/Cargo.toml), the smoke's own contract") \
		.is_not_empty()
	for s in range(5):
		var lay := ObjectiveLayout.generate(SEED_BASE + s, DUEL, FRONT_LINE, _cells(), 30,
			72.0, 48.0, "search", _armies())
		var ref := _pyo3_reference(python, int(lay["count_roll"]))
		if ref.is_empty():
			return
		var pos: Array = lay["positions"]
		var ref_pos: Array = ref["positions"]
		assert_int(pos.size()).is_equal(ref_pos.size())
		for i in range(ref_pos.size()):
			assert_int(int(pos[i][0])).is_equal(int(ref_pos[i][0]))
			assert_int(int(pos[i][1])).is_equal(int(ref_pos[i][1]))
		assert_int(int(lay["swept"])).is_equal(int(ref.get("swept", 0)))


@warning_ignore('unused_parameter')
func test_red_perturbing_the_seed_on_the_table_side_moves_the_markers(
		do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded — doctrine rung untestable without it") -> void:
	# The doctrine has zero RNG — the seed acts ONLY through the rulebook draw.
	# Perturbing it on the TABLE side alone (SEED_BASE + 1 draws 3, SEED_BASE
	# draws 5) must move the answer away from the twin's; restoring the seed must
	# restore the identity. A compare that cannot tell the two apart has no teeth.
	var python := OS.get_environment("NML_DOCTRINE_PYO3_PYTHON")
	assert_str(python).override_failure_message(
		"NML_DOCTRINE_PYO3_PYTHON is unset — see test_the_doctrine_matches_the_twin_on_five_seeds") \
		.is_not_empty()
	var twin_of_base := _pyo3_reference(python, 5)
	if twin_of_base.is_empty():
		return
	var perturbed := ObjectiveLayout.generate(SEED_BASE + 1, DUEL, FRONT_LINE, _cells(), 30,
		72.0, 48.0, "search", _armies())
	assert_int(int(perturbed["count_roll"])).is_equal(3)
	assert_int((perturbed["positions"] as Array).size()).is_equal(3)
	assert_int((twin_of_base["positions"] as Array).size()).is_equal(5)
	var restored := ObjectiveLayout.generate(SEED_BASE, DUEL, FRONT_LINE, _cells(), 30,
		72.0, 48.0, "search", _armies())
	assert_int((restored["positions"] as Array).size()).is_equal(5)
	for i in range(5):
		assert_int(int((restored["positions"] as Array)[i][0])) \
			.is_equal(int((twin_of_base["positions"] as Array)[i][0]))
		assert_int(int((restored["positions"] as Array)[i][1])) \
			.is_equal(int((twin_of_base["positions"] as Array)[i][1]))


## The twin's answer, through the smoke's FILE handoff (objective_doctrine_smoke.gd):
## the reference script takes the ALREADY-drawn count as argv[2] (default 3 = the
## pinned fixture). The file is removed before the call so a stale answer can
## never pass, and is the only channel — OS.execute's stdout capture comes back
## empty on this Godot 4.6 build (step 10a).
func _pyo3_reference(python: String, count: int) -> Dictionary:
	var script := ProjectSettings.globalize_path(
		"res://core/nml-core-py/tools/objective_doctrine_reference.py")
	var out_path := OS.get_user_data_dir().path_join("objective_doctrine_pyo3_test.json")
	DirAccess.remove_absolute(out_path)
	var rc := OS.execute(python, [script, out_path, str(count)], [])
	if rc != 0 or not FileAccess.file_exists(out_path):
		assert_bool(false).override_failure_message(
			"the pyo3 reference rc=%d — run it by hand for the traceback: %s %s" % [rc, python, script]) \
			.is_true()
		return {}
	var text := FileAccess.open(out_path, FileAccess.READ).get_as_text()
	DirAccess.remove_absolute(out_path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and parsed.has("positions"):
		return parsed
	assert_bool(false).override_failure_message("the pyo3 reference wrote no JSON object: %s" % text) \
		.is_true()
	return {}
