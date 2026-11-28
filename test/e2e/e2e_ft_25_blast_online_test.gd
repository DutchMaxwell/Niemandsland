extends GdUnitTestSuite
## Feature test FT-25: the Blast split's defender choice online, Firefight (gff), PINNED to the pending epoch 108 (R-FT1).
## An agreed Automatic room: this table = the host on slot 1 shooting; Squad and Mates (2 models each) belong to slot 2,
## a human guest. FF36 p.13 l.1156-1161: the DEFENDER picks how the hits are split.
## Asserted: exactly one owner request `blast_split:<shooter>:<target>` goes to the guest and no prompt opens on the
## host; the guest's answer frame (Mates) puts the extra hit on Mates (FT-12's line); with no answer inside the timeout
## the automatic split stands (the extra hit on the target) with one line naming the missing answer.
## Tray seed 0, instant: the hit die 6.
## Real: the main scene, the REAL NetworkManager (transport swapped), the owner-request door and its receive door, the
## card's Activate, the radial targeting and click, the core's volley.

const INCH := 0.0254

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "O")
	_t.need_epoch(108)


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _place(u: GameUnit, x_in: float, z_in: float) -> void:
	for k in u.models.size():
		(u.models[k] as ModelInstance).node.global_position = Vector3(x_in * INCH, 0, (z_in + k * 1.5) * INCH)


## The host's Blast(3) shot at Squad beside Mates; `answer` = the guest's reply (null = none). Returns the requests sent.
func _volley(answer: Variant, timeout_s: float) -> Array:   # answer: "mates" or null
	_t.seat_guest(timeout_s)
	var a := _t.unit("gff", 1, "Gunner", 1, 1, 0.0, 0.0, {"name": "Mortar", "range_in": 24, "attacks": 1, "count": 1, "rules": ["Blast(3)"]})
	a.unit_properties["quality"] = 2
	var squad := _t.unit("gff", 2, "Squad", 2, 1, 0.0, 0.0)
	_place(squad, 12.0, 0.0)
	var mates := _t.unit("gff", 2, "Mates", 2, 1, 0.0, 0.0)
	_place(mates, 12.0, 4.0)
	_t.main.seed_tray_rng(0)
	assert_bool(await _t.start(a)).is_true()
	var done := [false]
	var go := func() -> void:
		await _t.aim(a, squad)
		done[0] = true
	go.call()
	var asked: Array = []
	var seen: Array = []
	var prompts := 0
	var until := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until and not (done[0] and a.is_activated):
		for f in _t.net.wire:
			if str(f["t"]) != "request_roll" or seen.has(int(f["p"]["req"])):
				continue
			seen.append(int(f["p"]["req"]))
			if str(f["p"]["kind"]) == "choice":
				asked.append(f)
				if answer != null:
					_t.answer_owner(int(f["p"]["req"]), [mates.unit_id])
			else:   # the guest rolls its own saves: it answers with its faces (all 6s here; the split is asserted, not the saves)
				var sixes: Array = []
				sixes.resize(int(f["p"]["count"]))
				sixes.fill(6)
				_t.answer_owner(int(f["p"]["req"]), sixes)
		prompts += _t.main.find_children("*", "PromptCard", false, false).size()
		await get_tree().process_frame
	assert_int(prompts).override_failure_message("no prompt on the host").is_equal(0)
	return asked


func test_the_guest_answers_and_the_extra_hit_lands_on_its_pick(timeout := 120000) -> void:
	var asked := await _volley("mates", 10.0)
	assert_int(asked.size()).override_failure_message("one owner request: %s" % [_t.net.wire]).is_equal(1)
	if asked.size() == 1:
		assert_int(int(asked[0]["to"])).override_failure_message("to the guest").is_equal(2)
		assert_str(str(asked[0]["p"]["ask"]["choice"]["id"])).starts_with("blast_split:e2e_p1_Gunner:e2e_p2_Squad")
	assert_int(_t.count("Blast(3): 1 hit -> 1 on Squad, 2 on units within reach, 0 lost")) \
		.override_failure_message("the guest's pick: %s" % [_t.lines]).is_equal(1)


func test_no_answer_keeps_the_automatic_split(timeout := 120000) -> void:
	var asked := await _volley(null, 0.5)
	assert_int(asked.size()).override_failure_message("one owner request: %s" % [_t.net.wire]).is_equal(1)
	assert_int(_t.count("Blast(3): 1 hit -> 2 on Squad, 1 on units within reach, 0 lost")) \
		.override_failure_message("the automatic split: %s" % [_t.lines]).is_equal(1)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("no answer to the") != -1 and l.find("automatic pick stands") != -1)) \
		.override_failure_message("one line names the missing answer: %s" % [_t.lines]).is_true()
