extends GdUnitTestSuite
## E2E — the SELF-PLAY ARENA round loop grants Second Wind (Inquisitorial Agent / Martial Prowess).
##
## WHY THIS SUITE EXISTS. The human-facing solo path (`main._solo_after_activation`, main.gd:~1743)
## asks `solo_controller.second_wind_candidate()` once both activation pools are empty and spends it
## before ending the round — every arena recording (the reference bundles the fast core is gated
## against) skipped this seam entirely, because `main._solo_run_both_ai_round` (the both-AI driver the
## rating ladder, self-play harness and tactic-audit runs actually play on) returned as soon as both
## pools were empty and never asked the same question.
##
## WHAT IS REAL vs CONSTRUCTED. Real: `scenes/main.tscn` with its real `_ready()`, the real
## OPRArmyManager and phase machine, the real SoloController and its Second Wind bookkeeping, the real
## both-AI driver, the real battle log. Constructed: the GameUnits and their model nodes (importing a
## real Army Forge list needs the network) — placed at genuine table coordinates.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Well inside the real 6x4 ft table rect (±0.914 x ±0.610 m).
const P1_LINE := Vector3(-0.30, 0.0, 0.20)
const P2_LINE := Vector3(0.30, 0.0, -0.20)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
## Every activation the driver made, in order — the alternation's own witness (both sides are AI here,
## so this signal sees the whole round, the Second Wind extra activation included).
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


## A Second Wind carrier — "Inquisitorial Agent" (GF Human Inquisition, book v3.5.3), the registry
## primitive `second_wind_candidate()` reads (assets/solo/rules_mechanics_gf.json). The lookup keys on
## (system, faction), so `faction_folder` must be set — DEFAULT_SYSTEM ("gf") covers `game_system`.
func _carrier(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := _register(pid, unit_name, at)
	u.unit_properties["special_rules"] = ["Inquisitorial Agent"]
	u.unit_properties["faction_folder"] = "human_inquisition"
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


# === the arena driver grants the second activation =============================================

## The core claim. P1 fields one Second Wind carrier against one plain P2 unit. Both pools empty
## after one activation each — the driver must then offer the SAME once-per-game second activation
## `_solo_after_activation` grants the human-facing path, log the same rule line, and return the side
## that actually acted last (the carrier's second activation, not the round's first pass over it).
##
## ROT: without the Second Wind tail in `_solo_run_both_ai_round` the carrier activates once, the
## stamp never lands and the log line never appears (proven — this is the bug NML table arena parity
## step reports).
func test_the_both_ai_driver_grants_second_wind(timeout := 120000) -> void:
	var carrier := _carrier(1, "Missionary", P1_LINE)
	var enemy := _register(2, "Grenzer", P2_LINE)

	var last_side: int = await _main._solo_run_both_ai_round(1)

	assert_int(_count_activations("Missionary")) \
		.override_failure_message("Missionary activated %d time(s) — the arena never granted Second Wind:\n%s" % [
			_count_activations("Missionary"), str(_acted)]) \
		.is_equal(2)
	assert_bool(bool(carrier.unit_properties.get("second_wind_used", false))) \
		.override_failure_message("second_wind_used stamp missing after the extra activation") \
		.is_true()
	assert_str(_log_text()) \
		.override_failure_message("the arena driver never logged the Second Wind rule line:\n%s" % _log_text()) \
		.contains("activates a SECOND time this round (once per game — fatigue cleared)")
	# The carrier's second activation is what actually happened last — not the plain P2 unit's turn
	# that preceded it. A pass or a stale value here would hand the wrong side next round's opener.
	assert_int(last_side) \
		.override_failure_message("round returned opener-side %d — the second activation did not settle last_side" % last_side) \
		.is_equal(1)
	assert_bool((enemy as GameUnit).is_activated) \
		.override_failure_message("Grenzer never activated — the round did not play out").is_true()
	await E2EBoot.settle(get_tree())
