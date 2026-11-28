extends GdUnitTestSuite
## Feature test FT-12: the even Blast split and the defender's choice, Firefight (gff) and Skirmish (aofs), hot-seat table,
## PINNED to the pending epoch 108 (EPOCH_108_BLAST_EVEN; the table ships 103 - R-FT1). FF36 p.13 l.1156-1161 and its
## example (AS36 the same): each hit is multiplied by X and split evenly between the target and every enemy unit within
## 3 in of it, the DEFENDER picks how, each unit takes at most as many hits as it has models.
## Case 1 (the book's example): P1's Blast(6) 1 hit at Squad (2 models) with three 1-model P2 units within 3 in and one
## 4.2 in away -> 2 on Squad, 1 on each neighbour, the far unit none, one lost; no real choice, so no prompt. Case 2:
## Blast(3) at Squad (2 models) beside Mates (2 models): 3 hits, 1 + 1 and one extra -> P2 is asked and puts it on Mates.
## Tray seed 0, instant: the hit die 6; the table then leaves the headless batch (a batch table never asks). Real: the main
## scene, the card's Activate, the radial targeting and click, the core's volley, the owner-choice door and its prompt card.

const INCH := 0.0254
var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")
	_t.need_epoch(108)


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _place(u: GameUnit, x_in: float, z_in: float) -> void:
	for k in u.models.size():
		(u.models[k] as ModelInstance).node.global_position = Vector3(x_in * INCH, 0, (z_in + k * 1.5) * INCH)


## P1's shot at `target`; a "Blast split" prompt (if any) is answered with `pick` (a unit id, "" = Automatic).
## The hit die rolls instant and seeded (R-FT3); right after its line the table leaves the headless batch, so the owner's
## choice is asked as at a real table (a batch table never asks).
func _shoot(att: GameUnit, target: GameUnit, pick: String) -> bool:
	assert_bool(await _t.start(att)).is_true()
	var off_batch := func(e: Dictionary) -> void:
		if str(e["text"]).begins_with("P1: "):
			SoloHarness.instant(_t.main, false)
	_t.main.battle_log.entry_added.connect(off_batch)
	var done := [false]
	var go := func() -> void:
		await _t.aim(att, target)
		done[0] = true
	go.call()
	var asked := false
	var until := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until and not (done[0] and att.is_activated):
		for c in _t.main.find_children("*", "PromptCard", false, false):
			if str((c as PromptCard).title) == "Blast split" and not asked:
				asked = true
				(c as PromptCard).resolve(pick)
		await get_tree().process_frame
	_t.main.battle_log.entry_added.disconnect(off_batch)
	return asked


func _gunner(sys: String, blast: int) -> GameUnit:
	var a := _t.unit(sys, 1, "Gunner", 1, 1, 0.0, 0.0, {"name": "Mortar", "range_in": 24, "attacks": 1, "count": 1,
		"rules": ["Blast(%d)" % blast]})
	a.unit_properties["quality"] = 2
	_t.main.seed_tray_rng(0)
	return a


## The table side of the spread (LANDING-INVARIANT find): every neighbour keeps on the table exactly the models the core left it -
## its start models less the unsaved hits its "Blast: <unit> takes ... - N unsaved" line names (Tough 1 models).
func _neighbours_match_the_core(units: Array, sys: String) -> void:
	for u in units:
		var gu := u as GameUnit
		var line: Array = _t.lines.filter(func(l: String) -> bool: return l.begins_with("Blast: %s takes " % gu.get_name()))
		var unsaved := int(str(line[0]).get_slice(" - ", 1).get_slice(" ", 0)) if not line.is_empty() else 0
		assert_int(gu.get_alive_count()).override_failure_message("%s: %s on the table after %d unsaved: %s" % [sys, gu.get_name(), unsaved, _t.lines]) \
			.is_equal(maxi(0, gu.models.size() - unsaved))


func _even_split_of_the_books_example(sys: String) -> void:
	var a := _gunner(sys, 6)
	var squad := _t.unit(sys, 2, "Squad", 2, 1, 0.0, 0.0)
	_place(squad, 12.0, 0.0)
	var near: Array = []
	for spec in [["Near A", 12.0, -3.5], ["Near B", 15.5, 0.0], ["Near C", 12.0, 5.0], ["Far", 17.5, 1.5]]:
		var n := _t.unit(sys, 2, spec[0], 1, 1, 0.0, 0.0)
		_place(n, spec[1], spec[2])
		near.append(n)
	var asked := await _shoot(a, squad, "")
	assert_bool(asked).override_failure_message("%s: no real choice, no prompt" % sys).is_false()
	assert_int(_t.count("Blast(6): 1 hit -> 2 on Squad, 3 on units within reach, 1 lost")) \
		.override_failure_message("%s: the split line: %s" % [sys, _t.lines]).is_equal(1)
	for n in ["Near A", "Near B", "Near C"]:
		assert_int(_t.count("Gunner fires Mortar at %s — 1 hit" % n)).override_failure_message("%s: %s takes 1: %s" % [sys, n, _t.lines]).is_equal(1)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("at Far") != -1)).override_failure_message("%s: Far takes none" % sys).is_false()
	_neighbours_match_the_core(near, sys)


func _the_defender_picks(sys: String) -> void:
	var a := _gunner(sys, 3)
	var squad := _t.unit(sys, 2, "Squad", 2, 1, 0.0, 0.0)
	_place(squad, 12.0, 0.0)
	var mates := _t.unit(sys, 2, "Mates", 2, 1, 0.0, 0.0)
	_place(mates, 12.0, 4.0)
	var asked := await _shoot(a, squad, mates.unit_id)
	assert_bool(asked).override_failure_message("%s: P2 is asked: %s" % [sys, _t.lines]).is_true()
	assert_int(_t.count("Blast(3): 1 hit -> 1 on Squad, 2 on units within reach, 0 lost")) \
		.override_failure_message("%s: the extra hit on Mates: %s" % [sys, _t.lines]).is_equal(1)
	_neighbours_match_the_core([mates], sys)


func test_gff_the_books_blast_6_example(timeout := 120000) -> void:
	await _even_split_of_the_books_example("gff")


func test_aofs_the_books_blast_6_example(timeout := 120000) -> void:
	await _even_split_of_the_books_example("aofs")


func test_gff_the_defender_places_the_extra_hit(timeout := 120000) -> void:
	await _the_defender_picks("gff")


func test_aofs_the_defender_places_the_extra_hit(timeout := 120000) -> void:
	await _the_defender_picks("aofs")
