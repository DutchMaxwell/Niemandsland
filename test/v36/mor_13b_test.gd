extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-13b (lead ruling D-SPELL-LOS): MOR-13 let casters within 18" boost or resist
## a cast without a line of sight, so the token card the player sees must stop asking for one. Rules 3.5
## (the frozen EPOCH_72 leg) keeps today's wording byte for byte; those cases are `_at_epoch_72` controls.
## Each case opens the real InterferenceDialog card, reads its words, then answers it so the await ends.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests: restore


## Every label text under `n`, one per line.
func _texts(n: Node) -> String:
	var out := ""
	for c in n.get_children():
		if c is Label:
			out += (c as Label).text + "\n"
		out += _texts(c)
	return out


## Opens the card in `mode` with a pool of 3 tokens, returns its words and closes it with "no tokens".
func _card_text(mode: String) -> String:
	var dlg := InterferenceDialog.new()
	add_child(dlg)
	var out: Array = []
	(func() -> void: out.append(await dlg.ask("Shaman", "Fireball", "Guards", 4, 0, 3, mode))).call()
	var text := _texts(dlg)
	for c in dlg.get_children():
		if c is PromptCard:
			(c as PromptCard).resolve(0)
	while out.is_empty():
		await get_tree().process_frame
	return text


# Controls first: see the declaration-order note in test/solo_shaken_caster_support_test.gd.
func test_the_resist_card_keeps_its_line_of_sight_words_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var text: String = await _card_text("interfere")
	assert_str(text).override_failure_message("rules 3.5 wording changed:\n%s" % text).contains(
		"Spell tokens in 18\" line of sight: 3 — each spent token gives -1 to the cast roll.")


func test_the_boost_card_keeps_its_line_of_sight_words_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var text: String = await _card_text("boost")
	assert_str(text).override_failure_message("rules 3.5 wording changed:\n%s" % text).contains(
		"Friendly spell tokens in 18\" line of sight: 3 — each spent token gives +1 to the cast roll.")


func test_the_resist_card_drops_line_of_sight_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var text: String = await _card_text("interfere")
	assert_str(text).override_failure_message("rules 3.6: resisting needs no line of sight:\n%s" % text) \
		.not_contains("line of sight")
	assert_str(text).override_failure_message("rules 3.6: the card must still name the 18\" reach:\n%s" % text) \
		.contains("within 18\"")


func test_the_boost_card_drops_line_of_sight_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var text: String = await _card_text("boost")
	assert_str(text).override_failure_message("rules 3.6: boosting needs no line of sight:\n%s" % text) \
		.not_contains("line of sight")
	assert_str(text).override_failure_message("rules 3.6: the card must still name the 18\" reach:\n%s" % text) \
		.contains("within 18\"")
