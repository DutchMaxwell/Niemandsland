extends GdUnitTestSuite
## Shipped-base drift guard (konrad ORDER 476c3390, step 1). The base an A/B runs
## against MUST equal the game's own shipped header knobs — the block
## tools/shipped_base_dump.gd emits from SoloDifficulty planner_v0 + SoloController
## ._apply_aifix + AiActRecorder._header_line, the same path the live core reads.
##
## RED today: point NML_BATCH_BASE at the hand copy prep_batch built
## (BB.cand.json + leaf_opener_only). It predates #1724 (table_fidelity) and #1728
## (breadth 128), so it is MISSING top_k 128 / horizon 3 and the eight
## table-fidelity keys — the failure message names every missing key. GREEN once
## prep_batch generates the base from the pinned commit's own game files.
##
## Run (heavy.sh, one suite):
##   NML_BATCH_BASE=<base.json> godot --headless --path . \
##     -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
##     -a res://test/shipped_base_header_test.gd

const Dump := preload("res://tools/shipped_base_dump.gd")


func after_test() -> void:
	BattleSim._core_env = -1
	AiMissionEval.eval_variant = 0


func _shipped() -> Dictionary:
	return Dump.shipped_knobs()


## The base file prep_batch actually built, compared key-for-key to the header.
func test_the_prep_base_equals_the_game_shipped_header() -> void:
	var path := OS.get_environment("NML_BATCH_BASE")
	assert_bool(path.is_empty()).override_failure_message(
		"set NML_BATCH_BASE to the base file prep_batch built (BATCH.base.json)").is_false()
	var f := FileAccess.open(path, FileAccess.READ)
	assert_object(f).override_failure_message("cannot open NML_BATCH_BASE=%s" % path).is_not_null()
	var base: Dictionary = JSON.parse_string(f.get_line())
	f.close()
	var shipped := _shipped()
	var missing := []
	var extra := []
	var mismatch := []
	for k in shipped:
		if not base.has(k):
			missing.append(k)
		elif base[k] != shipped[k]:
			mismatch.append("%s base=%s shipped=%s" % [str(k), str(base[k]), str(shipped[k])])
	for k in base:
		if not shipped.has(k):
			extra.append(k)
	missing.sort()
	extra.sort()
	mismatch.sort()
	assert_bool(missing.is_empty()).override_failure_message(
		"base is MISSING %d shipped key(s): %s" % [missing.size(), str(missing)]).is_true()
	assert_bool(mismatch.is_empty()).override_failure_message(
		"base VALUE mismatch: %s" % str(mismatch)).is_true()
	assert_bool(extra.is_empty()).override_failure_message(
		"base has %d key(s) not in the shipped header: %s" % [extra.size(), str(extra)]).is_true()


## Documents the exact defect the hand copy carried (#1724/#1728): the shipped
## header stamps these keys and the hand copy never did. Fails loudly if the game
## ever stops stamping one, so a promotion can't silently run on a thinner base.
func test_the_shipped_header_carries_the_1724_1728_keys() -> void:
	var k := _shipped()
	assert_int(int(k.get("top_k", 0))).is_equal(128)
	assert_int(int(k.get("horizon", 0))).is_equal(3)
	assert_int(int(k.get("eval_variant", 0))).is_equal(4)
	for key in ["table_fidelity", "range_by_base_edge", "fire_in_range_only",
			"casualties_bearers_last", "hero_counts_in_size", "reply_threat_by_speed",
			"charge_needs_path", "fearless_roll_when_shaken"]:
		assert_bool(bool(k.get(key, false))).override_failure_message(
			"shipped header lost table-fidelity key %s" % key).is_true()
