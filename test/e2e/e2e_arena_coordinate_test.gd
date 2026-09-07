extends GdUnitTestSuite
## E2E — the SELF-PLAY ARENA round loop resolves Coordinate (wave 4, GF/AoF Human Defense Force).
##
## WHY THIS SUITE EXISTS. The live table resolves a Coordinate hand-over at the end of the BEARER's
## activation (main `_solo_try_coordinate_ai`, called from the AI activation body): the receiver is
## stamped `activated_via_coordinate` and activates IMMEDIATELY, riding the bearer's own beat. The
## both-AI arena driver (`main._solo_run_both_ai_round`) is the loop every recorded corpus game is
## played through — if it does not run the same seam, no recorded game can ever show a hand-over on
## the table side and the core plays a rule the corpus never contains (table-parity audit B, 07.09.).
##
## WHAT IS REAL vs CONSTRUCTED. Real: `scenes/main.tscn` with its real `_ready()`, the real
## OPRArmyManager and phase machine, the real SoloController and its Coordinate bookkeeping, the
## real both-AI driver, the real battle log. Constructed: the GameUnits and their model nodes
## (importing a real Army Forge list needs the network) — placed at genuine table coordinates.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Well inside the real 6x4 ft table rect (±0.914 x ±0.610 m).
const P1_LINE := Vector3(-0.30, 0.0, 0.20)
const P2_LINE := Vector3(0.30, 0.0, -0.20)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
## Every activation the driver made, in order.
var _acted: PackedStringArray = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}   # BOTH sides on the AI — the arena/ladder configuration
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true                   # no dialogs, no per-unit frame yield in a headless sweep
	_acted = PackedStringArray()
	_main.solo_controller.ai_unit_activated.connect(func(gu: GameUnit) -> void:
		_acted.append(gu.get_name()))


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === fixture helpers ==========================================================================

func _register(pid: int, unit_name: String, at: Vector3, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Coordinate carrier — the registry primitive `SoloController.carries_coordinate` reads
## (assets/solo/rules_mechanics_gf.json, gf/human_defense_force). The lookup keys on
## (system, faction), so `faction_folder` must be set — DEFAULT_SYSTEM ("gf") covers `game_system`.
func _carrier(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := _register(pid, unit_name, at)
	u.unit_properties["special_rules"] = ["Coordinate"]
	u.unit_properties["faction_folder"] = "human_defense_force"
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _count_activations(unit_name: String) -> int:
	var n := 0
	for a in _acted:
		if a == unit_name:
			n += 1
	return n


# === the arena driver resolves the Coordinate hand-over ========================================

## The core claim. P1 fields one Coordinate carrier against one plain P2 unit, with one friendly
## receiver right beside the carrier. The receiver is Shaken, so the seeded pick activates the
## carrier first (fresh units before Shaken idlers) and the driver must then run the SAME end-of-
## activation seam the live table runs: stamp the receiver `activated_via_coordinate` and activate
## it IMMEDIATELY, riding the carrier's own activation.
##
## ROT: without the seam in the arena driver's activation loop the receiver is a Shaken idler the
## round loop never picks (fresh units first, both pools empty after one activation each) — it
## never activates, the stamp never lands and the rule line never appears (proven — table-parity
## audit B, 07.09.).
func test_the_arena_driver_resolves_a_coordinate_handover(timeout := 120000) -> void:
	var carrier := _carrier(1, "Line Officer", P1_LINE)
	var receiver := _register(1, "Line Troops", P1_LINE + Vector3(0.05, 0.0, 0.0))
	receiver.is_shaken = true   # idler: the round loop alone would never activate it
	var enemy := _register(2, "Grenzer", P2_LINE)

	await _main._solo_run_both_ai_round(1)

	assert_bool(SoloController.carries_coordinate(carrier)) \
		.override_failure_message("fixture broken — the carrier does not read as a Coordinate carrier") \
		.is_true()
	assert_int(_count_activations("Line Officer")) \
		.override_failure_message("carrier activated %d time(s):\n%s" % [_count_activations("Line Officer"), str(_acted)]) \
		.is_equal(1)
	# The receiver activated IMMEDIATELY off the hand-over — not left as a Shaken idler the round
	# loop would never have picked.
	assert_int(_count_activations("Line Troops")) \
		.override_failure_message("receiver activated %d time(s) — the arena driver never resolved the Coordinate hand-over:\n%s" % [
			_count_activations("Line Troops"), str(_acted)]) \
		.is_equal(1)
	assert_bool(receiver.was_activated_via_coordinate()) \
		.override_failure_message("activated_via_coordinate stamp missing — the activation was not a Coordinate hand-over") \
		.is_true()
	assert_str(_log_text()) \
		.override_failure_message("the arena driver never logged the Coordinate rule line:\n%s" % _log_text()) \
		.contains("hands off to")
	assert_bool((enemy as GameUnit).is_activated) \
		.override_failure_message("Grenzer never activated — the round did not play out").is_true()
	await E2EBoot.settle(get_tree())


# === no carrier — the round behaves exactly as before ==========================================

## The parity pin. With NO Coordinate carrier on the table the arena round is unchanged: the plain
## one-for-one alternation, each unit activated exactly once, and not one Coordinate line in the
## battle log — the seam must stay silent when nothing carries the rule.
func test_a_round_without_a_carrier_is_unchanged(timeout := 120000) -> void:
	var plain1 := _register(1, "Line Troops", P1_LINE)
	var plain2 := _register(2, "Grenzer", P2_LINE)

	var last_side: int = await _main._solo_run_both_ai_round(1)

	assert_int(_count_activations(plain1.get_name())) \
		.override_failure_message("P1 unit activated %d time(s) without any carrier:\n%s" % [
			_count_activations(plain1.get_name()), str(_acted)]) \
		.is_equal(1)
	assert_int(_count_activations(plain2.get_name())) \
		.override_failure_message("P2 unit activated %d time(s) without any carrier:\n%s" % [
			_count_activations(plain2.get_name()), str(_acted)]) \
		.is_equal(1)
	assert_bool(plain1.was_activated_via_coordinate()) \
		.override_failure_message("a plain unit carries the activated_via_coordinate stamp") \
		.is_false()
	assert_bool(plain2.was_activated_via_coordinate()) \
		.override_failure_message("a plain unit carries the activated_via_coordinate stamp") \
		.is_false()
	var log_text := _log_text()
	for e in _main.battle_log.entries():
		assert_str(str((e as Dictionary)["text"])) \
			.override_failure_message("a Coordinate rule line appeared in a carrierless round:\n%s" % log_text) \
			.contains("Coordinate").is_false()
	assert_int(last_side) \
		.override_failure_message("round returned %d — the plain alternation did not settle last_side" % last_side) \
		.is_equal(2)
	await E2EBoot.settle(get_tree())
