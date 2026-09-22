extends GdUnitTestSuite
## E2E — the battle log speaks to the PLAYER, not to the trainer (release week 25.09.2026).
##
## The maintainer's real game (battle_log_2026-09-22_20-33-29.txt) exported, with "AI reasoning in the
## log" switched on, three kinds of line no player can read:
##   1. "AI [brain]  — rule: developer leaf evaluator — … [name=onnx, hash=<64 hex>, batch_us=…]"
##   2. the unit-pick record and a "leaf row: … (training data)" record, each with a 30-number
##      "features={ … }" dump,
##   3. 96 empty trace records: "AI [dice] ?", "AI [digest] ?", "AI [rng] ?".
## Project rule: a working name is never a display label. The toggle is a PLAYER option (NML-1084), so
## everything it shows — the live panel and the export, including its decision-records appendix — is
## player text. The raw records stay intact for the developer lane (SoloController.render_decision,
## used by the self-play harness, and the decision_sink capture).
##
## Driven on the real main.tscn: the real _solo_flush_dev (panel) and the real _on_battle_log_export
## (file on disk, read back). Constructed: the records, copied from the maintainer's exported file.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const HASH := "bb5568f646d97295b9f460254305ef6d18a9e830924a984b237651116b1e5e36"
const DIGEST_SHA := "4f2c9a0d6e1b83f7a5c2d9e0b4a61f3c8e7d2b5a9c0f1e4d3b6a8c2e9f0d1a7b"
## Every token that must never reach the player view.
const FORBIDDEN := ["developer", "training data", "leaf row", "features={", "batch_us", HASH, DIGEST_SHA]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _written: Array[String] = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	for p in _written:
		DirAccess.remove_absolute(p)
	_written.clear()
	if _main != null:
		_main.solo_controller = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


static func _features(round_frac: float) -> Dictionary:
	return {"round_frac": round_frac, "my_wounds": 58.0, "their_wounds": 32.0, "my_units": 7.0,
		"their_units": 5.0, "presence_mine": 46.4166666666667, "my_incoming": 3.33333333333333}


## The record shapes of the maintainer's export, plus one ordinary rule record as the control.
static func _records() -> Array:
	return [
		{"kind": "brain", "unit": "", "rule": "developer leaf evaluator", "candidates": [], "chosen": "",
			"why": "Rust search consumed leaf values",
			"data": {"name": "onnx", "hash": HASH, "batches": 2, "batch_us": 146653}},
		{"kind": "planner", "unit": "Veterans",
			"rule": "PLANNER_V0 unit pick (NML-995): the round is played out for the best openers; the strongest end-of-round position activates first",
			"candidates": [], "chosen": "activates next", "why": "Veterans: fall back — win 0.73 → 1.35",
			"data": {"kept_back": 4, "value": 0.73, "features": _features(0.25)}},
		{"kind": "planner", "unit": "Veterans",
			"rule": "leaf row: winning candidate's horizon-end position (training data)",
			"candidates": [], "chosen": "", "why": "leaf", "data": {"leaf": true, "features": _features(0.75)}},
		{"kind": "dice", "seq": 1, "roll_kind": "attack", "owner": "AI (Veterans)", "target": 6, "count": 3,
			"faces": [6, 5, 4]},
		{"kind": "digest", "seq": 3, "sha": DIGEST_SHA},
		{"kind": "rng", "tag": "roll_off", "value": 3, "lo": 1, "hi": 6},
		{"kind": "target", "unit": "Veterans", "rule": "Solo v3.5.0 p.2: nearest valid target, not-activated first",
			"candidates": [{"name": "Snipers", "ev": 1.99}, {"name": "Warriors"}], "chosen": "Snipers",
			"why": "official: nearest, not-activated first", "data": {"considered": 4}},
	]


func _arm_ai_log() -> SoloController:
	var sc: SoloController = auto_free(SoloController.new())
	_main.solo_controller = sc
	_main._solo_dev = true
	return sc


func _ai_lines(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		var s := str(l)
		var at := s.find("AI [")
		if at >= 0:
			out.append(s.substr(at))
	return out


## The player-facing assertions shared by the panel and the export.
func _assert_player_text(where: String, lines: Array) -> void:
	var ai := _ai_lines(lines)
	var empty_record := RegEx.create_from_string("^AI \\[[a-z_]+\\]\\s*\\??\\s*$")
	for l in ai:
		assert_bool(empty_record.search(str(l)) == null) \
			.override_failure_message("%s shows an empty record to the player: '%s'" % [where, l]) \
			.is_true()
	var text := "\n".join(PackedStringArray(ai))
	for tok in FORBIDDEN:
		assert_bool(text.contains(str(tok))) \
			.override_failure_message("%s shows '%s' to the player:\n%s" % [where, tok, text]) \
			.is_false()
	var long_hex := RegEx.create_from_string("[0-9a-f]{32,}")
	assert_object(long_hex.search(text)) \
		.override_failure_message("%s shows a raw hash to the player:\n%s" % [where, text]) \
		.is_null()
	# Every rule line survives — only debug records are relabelled or routed.
	assert_str(text).contains("chose Snipers")
	assert_str(text).contains("chose activates next")
	# The brain record is still announced, in plain words.
	assert_str(text).contains("trained evaluator")


func test_the_live_panel_shows_plain_player_text() -> void:
	var sc := _arm_ai_log()
	sc.drain_decisions()
	for rec in _records():
		sc.record_decision(rec)
	_main._solo_flush_dev()
	var lines: Array = []
	for e in _main.battle_log.entries():
		lines.append(str((e as Dictionary)["text"]))
	_assert_player_text("the battle-log panel", lines)


func test_the_export_and_its_records_appendix_show_plain_player_text() -> void:
	var sc := _arm_ai_log()
	sc.drain_decisions()
	for rec in _records():
		sc.record_decision(rec)
	_main._solo_flush_dev()                  # body: the flushed records
	for rec in _records():
		sc.record_decision(rec)              # appendix: records still buffered at export time
	_main._on_battle_log_export()
	var path := ""
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.begins_with("Battle Log exported → "):
			path = t.trim_prefix("Battle Log exported → ")
	assert_str(path).override_failure_message("the export did not run").is_not_empty()
	_written.append(path)
	var body := FileAccess.get_file_as_string(path)
	assert_str(body).contains("--- AI decision records ---")
	var appendix := body.substr(body.find("--- AI decision records ---"))
	_assert_player_text("the exported file", Array(body.split("\n")))
	_assert_player_text("the export's decision-records appendix", Array(appendix.split("\n")))


## The developer lane keeps every field: the raw records are untouched and the harness renderer
## (tools/solo_selfplay.gd) still prints hash, timings and feature vectors.
func test_the_developer_renderer_keeps_the_raw_fields() -> void:
	var recs := _records()
	assert_str(SoloController.render_decision(recs[0])).contains(HASH)
	assert_str(SoloController.render_decision(recs[0])).contains("batch_us")
	assert_str(SoloController.render_decision(recs[1])).contains("features={")
	assert_str(SoloController.render_decision(recs[2])).contains("training data")
