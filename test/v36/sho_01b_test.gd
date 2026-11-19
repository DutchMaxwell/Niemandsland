extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-01b: an Indirect weapon keeps the target's terrain cover at epoch 73 —
## the entry lifts only sight-blocker cover and the table grants Cover terrain only, so a Hold no
## longer matters (FAB-A3 corrects the earlier Hold reading). At EPOCH_72_PLAYTEST_RULES the old
## reading stands (every Indirect shot drops cover). Blast(X > 1) and Ignores Cover drop cover at every
## epoch, moved or held. Drives the real AI volley (_solo_resolve_ai_volley) over main.tscn, the same
## path the AI and the human save resolution share, and reads the battle log the rule writes.

func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func test_the_shipped_indirect_entries_ask_for_a_hold_before_dropping_cover() -> void:
	for sys in ["gf", "aof"]:
		assert_bool(bool(RulesRegistry.param(sys, "", "Indirect", "cover_needs_hold", false))) \
			.override_failure_message("%s common Indirect must carry cover_needs_hold = true" % sys).is_true()
