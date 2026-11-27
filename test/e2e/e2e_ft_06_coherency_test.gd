extends GdUnitTestSuite
## Feature test FT-6: unit coherency on a hot-seat table, Firefight (gff) and Skirmish (aofs). FF36 p.7 l.517-521 / AS36
## p.7 l.542: every model within 1 in of another model of its unit and within the chain of all others - 9 in gff, 6 in
## aofs (read from CHAIN below, per book).
## Scene: a row of models with every link under 1 in, spanning (chain - 1) in. Start; the player drags the last two models
## 0.5 in along the row, then the last one 0.5 in more, so the row spans `span` with every link still under 1 in. Third
## case: a 3-model row whose last model is dragged 1.5 in off model 2.
## FINDING #3843 (R-FT2): the table only flags a broken coherency (the card's "Out of coherency" strip) - the drop stands
## and End spends the unit. The book cases stay here, skipped with that issue; unskip with the fix.
## Real: the main scene, the card's Activate / End, the real drag and drop door, the unit card.

const INCH := 0.0254
const BASE_IN := 32.0 / 25.4   # the fixture's default round base
const CHAIN := {"gff": 9.0, "aofs": 6.0}   # FF36 p.7 l.518-519; AS36 p.7 l.542
const MODELS := {"gff": 7, "aofs": 5}      # enough models to span the chain with every link under 1 in
const FLAG := "Out of coherency"
const FINDING := "FINDING #3843: the table only flags broken coherency; the drop stands and End spends the unit"

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


## A row of `n` models of `sys` spanning `span_in` (edge to edge), plus two P2 units far off.
func _row(sys: String, n: int, span_in: float) -> GameUnit:
	var u := _t.unit(sys, 1, "Line", n, 1, -10.0, 0.0)
	_t.unit(sys, 2, "Foe", 1, 1, 20.0, 0.0)
	_t.unit(sys, 2, "Foe2", 1, 1, 20.0, 10.0)
	var step := (span_in + BASE_IN) / float(n - 1)
	for i in n:
		(u.models[i] as ModelInstance).node.global_position = Vector3(-10.0 * INCH, 0.0, i * step * INCH)
	return u


## The row spanning `span` after the two drags (every link stays under 1 in).
func _stretch(sys: String, span: float) -> GameUnit:
	var n: int = MODELS[sys]
	var u := _row(sys, n, span - 1.0)
	assert_bool(await _t.start(u)).override_failure_message("%s: Start" % sys).is_true()
	await _t.walk(u, 0.0, 0.5, CoreActivation.CAP_ADVANCE, [u.models[n - 2], u.models[n - 1]])
	await _t.walk(u, 0.0, 0.5, CoreActivation.CAP_ADVANCE, [u.models[n - 1]])
	return u


func _within(sys: String) -> void:
	var u := await _stretch(sys, CHAIN[sys] - 0.5)
	assert_bool(_t.card_shows(u, FLAG)).override_failure_message("%s: no flag at chain - 0.5 in" % sys).is_false()
	await _t.end(u)
	assert_bool(u.is_activated).override_failure_message("%s: End spends it: %s" % [sys, _t.lines]).is_true()


## The table's flag (green today): the card warns at chain + 0.5 in.
func _flagged(sys: String) -> void:
	var u := await _stretch(sys, CHAIN[sys] + 0.5)
	assert_bool(_t.card_shows(u, FLAG)).override_failure_message("%s: the card warns at chain + 0.5 in" % sys).is_true()


## The book: a drop that leaves `u` out of coherency is not kept - it snaps back, or End leaves the unit open.
func _refused(sys: String, u: GameUnit) -> void:
	await _t.end(u)
	var broken: bool = _t.card_shows(u, FLAG)
	assert_bool(broken and u.is_activated).override_failure_message("%s: spent out of coherency: %s" % [sys, _t.lines]).is_false()
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.findn("coheren") != -1)) \
		.override_failure_message("%s: one line names coherency: %s" % [sys, _t.lines]).is_true()


func test_gff_within_9_in_ends(timeout := 120000) -> void:
	await _within("gff")


func test_aofs_within_6_in_ends(timeout := 120000) -> void:
	await _within("aofs")


func test_gff_over_9_in_is_flagged(timeout := 120000) -> void:
	await _flagged("gff")


func test_aofs_over_6_in_is_flagged(timeout := 120000) -> void:
	await _flagged("aofs")


@warning_ignore("unused_parameter")
func test_gff_over_9_in_is_refused(timeout := 120000, do_skip := true, skip_reason := FINDING) -> void:
	await _refused("gff", await _stretch("gff", 9.5))


@warning_ignore("unused_parameter")
func test_aofs_over_6_in_is_refused(timeout := 120000, do_skip := true, skip_reason := FINDING) -> void:
	await _refused("aofs", await _stretch("aofs", 6.5))


## A 3-model row of `sys`, links 0.5 in; model 3 dragged 1 in further off (its link 1.5 in).
func _off_link(sys: String) -> GameUnit:
	var u := _t.unit(sys, 1, "Trio", 3, 1, -10.0, 0.0)
	_t.unit(sys, 2, "Foe", 1, 1, 20.0, 0.0)
	_t.unit(sys, 2, "Foe2", 1, 1, 20.0, 10.0)
	for i in 3:
		(u.models[i] as ModelInstance).node.global_position = Vector3(-10.0 * INCH, 0.0, i * (0.5 + BASE_IN) * INCH)
	assert_bool(await _t.start(u)).override_failure_message("%s: Start" % sys).is_true()
	await _t.walk(u, 0.0, 1.0, CoreActivation.CAP_ADVANCE, [u.models[2]])
	return u


@warning_ignore("unused_parameter")
func test_gff_a_model_1_5_in_off_is_refused(timeout := 120000, do_skip := true, skip_reason := FINDING) -> void:
	await _refused("gff", await _off_link("gff"))


@warning_ignore("unused_parameter")
func test_aofs_a_model_1_5_in_off_is_refused(timeout := 120000, do_skip := true, skip_reason := FINDING) -> void:
	await _refused("aofs", await _off_link("aofs"))
