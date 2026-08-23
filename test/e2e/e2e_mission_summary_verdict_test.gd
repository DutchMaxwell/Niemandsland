extends GdUnitTestSuite
## NML-1048 — the END-OF-GAME SUMMARY must name the winner the game actually BOOKED.
##
## THE DEFECT. main._solo_show_game_summary() built its verdict from the objective markers still held
## at the buzzer and never looked at the mission VP ledger main._solo_book_mission_vp() fills every
## round. On the four progressive missions (pitched_battle, domination, headquarters, mosh_pit) the
## ledger is the rule — held markers are only its last instalment — so the two verdicts drift apart.
## MEASURED over the 633 finished self-play games in ~/selfplay_out (c8_old + c8_new): of the 233 games
## on a round_vp mission, 55 had the summary declare a different side than the referee that wrote the
## result. Seed 3003000 (pitched_battle, dark_elves vs sky_city_dwarves) is the sharpest of them: the
## final board is P1 1 marker : P2 2 markers, the ledger is P1 6 VP : P2 5 VP, the result JSON says
## "winner": "p1" — and the summary told the table P2 had won.
##
## WHAT IS REAL vs CONSTRUCTED. Real: scenes/main.tscn with its real _ready(), the real terrain overlay
## and its objective owners, the real SoloController mission ledger, the real battle log and the real
## summary function. Constructed: the final board state, transcribed from that game's result JSON
## instead of replaying 17 minutes of dice.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Final board + ledger of self-play seed 3003000 — see the header.
const SEED_3003000_OWNERS := [1, 2, 2]
const SEED_3003000_VP := [6, 5]
## Three marker positions well inside the real 6x4 ft table; only their OWNERS carry meaning here.
const MARKER_POSITIONS := [Vector3(-0.3, 0.0, 0.1), Vector3(0.0, 0.0, -0.2), Vector3(0.3, 0.0, 0.2)]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.current_round = 4


func after_test() -> void:
	SoloController.mission_reset("end", {})   # statics: never leak this game's mission into the next suite
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


## Puts the seed-3003000 endgame on the table: three markers with their final owners and the VP ledger
## the round-end bookkeeping had banked by the last round.
func _arm_progressive_endgame() -> void:
	_main.terrain_overlay.update_objectives(MARKER_POSITIONS, SEED_3003000_OWNERS)
	SoloController.mission_reset("round_vp", {"majority": "end"})
	SoloController.mission_vp = SEED_3003000_VP.duplicate()


## The text the player reads in the "Game over" dialog.
func _summary_dialog_text() -> String:
	for c in _main.get_children():
		if c is AcceptDialog:
			return (c as AcceptDialog).dialog_text
	return "<no summary dialog>"


## The whole GAME OVER block as it lands in the exported battle log.
func _summary_log() -> String:
	var lines: PackedStringArray = []
	for e in _main.battle_log.entries():
		lines.append(str((e as Dictionary).get("text", "")))
	return "\n".join(lines)


## The arena referee (tools/arena_match.gd) reads the ledger: 6 VP beats 5 VP, so P1 won this game.
## The summary is shown to BOTH AI sides by name here — the configuration the 633 measured games ran in.
func test_arena_summary_names_the_vp_winner_not_the_marker_holder() -> void:
	_main._solo_both_ai = true
	_main.solo_ai_slots = {1: true, 2: true}
	_arm_progressive_endgame()
	_main._solo_show_game_summary()
	await _runner.simulate_frames(2)
	assert_str(_summary_dialog_text()).contains("P1 wins")
	assert_str(_summary_log()).contains("P1 wins")


## Same endgame in the shipped human-vs-NACHTMAHR seating (the player holds P1): the player banked the
## most VP, so the verdict is a win — even though NACHTMAHR ended the game standing on more markers.
func test_human_summary_names_the_vp_winner_not_the_marker_holder() -> void:
	_main._solo_both_ai = false
	_main.solo_ai_slots = {2: true}
	_arm_progressive_endgame()
	_main._solo_show_game_summary()
	await _runner.simulate_frames(2)
	assert_str(_summary_dialog_text()).contains("You win")


## GUARD for the other 400 measured games: a face-off mission has no ledger ("end" scoring, VP 0:0),
## and there held markers ARE the rule — the fix must not hand those games to a draw.
func test_face_off_summary_still_decides_by_held_markers() -> void:
	_main._solo_both_ai = false
	_main.solo_ai_slots = {2: true}
	_main.terrain_overlay.update_objectives(MARKER_POSITIONS, [1, 2, 2])
	SoloController.mission_reset("end", {})
	_main._solo_show_game_summary()
	await _runner.simulate_frames(2)
	assert_str(_summary_dialog_text()).contains("NACHTMAHR claims the field.")
