extends GdUnitTestSuite
## E2E — DEFECT 1: play could be STARTED with units still standing on their tray.
##
## The maintainer's report (2026-07-27): "Ich konnte das Deployment einfach umgehen. Ich habe die
## Einheit einfach nach vorne geschoben und Start Game gedrückt. Kein Deployment notwendig." The units
## left on the tray kept their TRAY coordinates, so NACHTMAHR targeted and charged them out there and he
## had to delete his own units by hand to keep playing.
##
## There are FOUR doors into play and every one of them had to be closed:
##   1. the Start/Ready button          — _on_start_game_pressed        (main.gd:11429)
##   2. the first solo activation       — _on_solo_human_activated      (main.gd:994)
##   3. the guided deployment FSM       — _solo_deploy_phase_advance    (main.gd:1991)
##   4. the F11 hotkey                  — _run_solo_ai_turn             (main.gd:777)
## All four funnel through _deployment_gate_refuses_start (main.gd:11395), so this suite drives each
## DOOR (not the shared predicate) and asserts the door's OWN side effects — a gate that returns true
## while its caller ignores it is exactly the shape of the original bug.
##
## WHAT IS REAL vs CONSTRUCTED. Real: scenes/main.tscn with its real _ready(), the real
## OPRArmyManager + phase machine, the real table geometry (_table_rect over the real 6x4 ft table), the
## real SoloController, the real toast + battle log, and the real door functions. Constructed: the
## GameUnits and their model nodes — importing a real Army Forge list needs the network, and spawning a
## real army needs R2 GLBs, neither of which may touch CI. The units are placed at genuine world
## coordinates and judged by the game's own on-table test, so the geometry is not faked.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Well inside the real 6x4 ft table rect (±0.914 x ±0.610 m).
const ON_TABLE := Vector3(0.2, 0.0, -0.2)
const ON_TABLE_2 := Vector3(-0.2, 0.0, 0.2)
## Where OPRArmyManager parks an army tray: strictly outside the rect. This is the maintainer's bug.
const ON_TRAY := Vector3(3.0, 0.0, 0.0)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	# Solo, player 2 = NACHTMAHR — the configuration every one of these doors ships in.
	_main.solo_ai_slots = {2: true}


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Register a unit with the REAL army manager, exactly as the import/restore path does.
func _register(pid: int, unit_name: String, at: Vector3, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var out := ""
	for e in _main.battle_log.entries():
		out += str((e as Dictionary)["text"]) + "\n"
	return out


func _toast_text() -> String:
	var t := _main.get_node_or_null("UI/SoloActionToast") as Label
	return "" if t == null else t.text


func _is_deployment() -> bool:
	return _main.opr_army_manager.is_deployment_phase()


# ===== Door 1 — the Start / Ready button =====

func test_start_button_refuses_while_a_unit_is_still_on_the_tray(timeout := 120000) -> void:
	_register(1, "Wachtturm", ON_TABLE)
	var stranded := _register(1, "Vergessene", ON_TRAY)
	assert_bool(_is_deployment()).is_true()

	_main._on_start_game_pressed()

	# The evidence the gate collects...
	var left: Array = _main._units_still_on_tray(-1)
	assert_int(left.size()).is_equal(1)
	assert_that(left[0]).is_same(stranded)
	# ...the phase it must NOT have flipped (this is the maintainer's exact bug)...
	assert_bool(_is_deployment()) \
		.override_failure_message("Start Game began play with a unit still on its tray — the deployment gate is bypassable again; the AI will target that unit at its TRAY coordinates") \
		.is_true()
	# ...and the two places the player is told why.
	assert_str(_toast_text()) \
		.override_failure_message("the start was refused SILENTLY — no toast; a silently-refused button reads as a broken button") \
		.contains("Vergessene")
	assert_str(_log_text()) \
		.override_failure_message("the refusal never reached the battle log (rules-must-log: every applied rule states its line)") \
		.contains("Start refused")


## The negative control. Without this the suite would also pass on a Start button that never starts.
func test_start_button_starts_play_once_every_unit_stands_on_the_table(timeout := 120000) -> void:
	_register(1, "Wachtturm", ON_TABLE)
	var stranded := _register(1, "Vergessene", ON_TRAY)
	_main._on_start_game_pressed()
	assert_bool(_is_deployment()).is_true()          # refused, as above

	E2EBoot.place_unit_at(stranded, ON_TABLE_2)      # the player deploys it for real
	_main._on_start_game_pressed()

	assert_int(_main._units_still_on_tray(-1).size()).is_equal(0)
	assert_bool(_is_deployment()) \
		.override_failure_message("every unit stands on the table and Start Game STILL refuses — the gate has become unsatisfiable and the game cannot be started at all") \
		.is_false()


# ===== Door 2 — the first solo activation =====

func test_first_solo_activation_refuses_and_does_not_spend_the_unit(timeout := 120000) -> void:
	var mover := _register(1, "Wachtturm", ON_TABLE)
	_register(1, "Vergessene", ON_TRAY)
	# The radial marks the unit activated BEFORE it emits unit_activated — so a bare refusal used to
	# leave it spent: it entered round 1 already used and dropped out of the eligible list.
	mover.is_activated = true

	await _main._on_solo_human_activated(mover)

	assert_bool(_is_deployment()) \
		.override_failure_message("activating a unit began play with the rest of the army on the tray — a second, button-free way around deployment") \
		.is_true()
	assert_bool(mover.is_activated) \
		.override_failure_message("the refused activation STUCK: the unit stays marked activated, so it enters round 1 already spent and cannot act") \
		.is_false()


# ===== Door 3 — the guided deployment FSM completing =====

func test_deployment_fsm_reopens_the_human_turn_instead_of_completing(timeout := 120000) -> void:
	_main._ensure_solo_controller()
	_register(1, "Wachtturm", ON_TABLE)
	_register(1, "Vergessene", ON_TRAY)
	# "No units left" / "✔ Done" is the player ASSERTING he is finished — nothing was verified.
	_main._solo_deploy_fsm = {"phase": "scout", "human_out": true, "winner_is_ai": false}

	_main._solo_deploy_phase_advance()

	assert_str(str(_main._solo_deploy_fsm.get("phase", ""))) \
		.override_failure_message("the deployment FSM closed the phase with a unit still on the tray — and it hides the deployment panel on the way, so the player cannot even place it afterwards") \
		.is_not_equal("done")
	assert_bool(bool(_main._solo_deploy_fsm.get("human_out", true))) \
		.override_failure_message("the human's 'I am done' assertion was not taken back — the turn is not re-opened, so the tray unit can never be placed") \
		.is_false()
	assert_bool(_is_deployment()).is_true()


# ===== Door 4 — the F11 hotkey (the worst door: it runs the WHOLE AI side at once) =====

func test_f11_ai_turn_refuses_and_moves_nothing(timeout := 120000) -> void:
	var ai_unit := _register(2, "Nachtzehrer", ON_TABLE)
	_register(1, "Wachtturm", ON_TABLE_2)
	_register(1, "Vergessene", ON_TRAY)
	var before: Vector3 = (ai_unit.models[0] as ModelInstance).node.global_position

	await _main._run_solo_ai_turn()

	assert_bool(_is_deployment()) \
		.override_failure_message("F11 flipped the game to PLAYING with a unit on the tray — _solo_ensure_playing_phase deploys the AI's remainder and the whole AI side then runs against an army still on its tray") \
		.is_true()
	assert_vector((ai_unit.models[0] as ModelInstance).node.global_position) \
		.override_failure_message("an AI model MOVED although the start was refused — the AI turn ran past the gate") \
		.is_equal(before)


## Negative control for door 4: with the table clear, F11 must get through. The AI army is deliberately
## empty so the turn finds nothing to activate and returns at once — this asserts the GATE let it pass,
## not the AI's behaviour (which the solo suites cover).
func test_f11_ai_turn_proceeds_once_the_table_is_clear(timeout := 120000) -> void:
	_register(1, "Wachtturm", ON_TABLE)

	await _main._run_solo_ai_turn()

	assert_bool(_is_deployment()) \
		.override_failure_message("the table is clear and F11 still refuses — the gate has become unsatisfiable") \
		.is_false()


# ===== Exemptions the rules require (a gate that refuses too much is also broken) =====

## GF/AoF v3.5.1 p.13: Ambush units MAY be held back and arrive from round 2, so they are allowed to be
## off the table when play begins. The second half matters just as much: main.gd must FORMALLY set them
## aside, because that flag is what makes them off-table to the rest of the game — without it the AI
## still saw them standing at their tray coordinates, which is the charge the maintainer watched.
func test_ambush_units_may_stay_on_the_tray_and_are_formally_set_aside(timeout := 120000) -> void:
	# _set_aside_offtable_ambush is a no-op without a controller — build it, or this passes vacuously.
	_main._ensure_solo_controller()
	_register(1, "Wachtturm", ON_TABLE)
	var amb := _register(1, "Hinterhalt", ON_TRAY)
	amb.unit_properties["special_rules"] = ["Ambush"]

	_main._on_start_game_pressed()

	assert_bool(_is_deployment()) \
		.override_failure_message("an army holding an Ambush unit cannot be started at all — the gate refuses a unit the rules allow to stay off the table (GF/AoF v3.5.1 p.13)") \
		.is_false()
	assert_bool(bool(amb.unit_properties.get("ambush_reserve", false))) \
		.override_failure_message("the off-table Ambush unit was NOT set aside as a reserve — to the rest of the game it is still a normal unit standing at its TRAY coordinates, which is exactly what the AI charged") \
		.is_true()
	assert_str(_log_text()) \
		.override_failure_message("holding a unit in reserve is a rule being applied and must state its battle-log line") \
		.contains("Ambush unit(s) in reserve")


## Unattended both-AI runs (the arena / self-play harness) deploy themselves — nobody is there to place
## anything, so the gate must stand aside or every headless batch deadlocks.
func test_unattended_both_ai_runs_are_exempt(timeout := 120000) -> void:
	_register(1, "Wachtturm", ON_TRAY)
	_register(2, "Nachtzehrer", ON_TRAY)
	assert_bool(_main._deployment_gate_refuses_start()).is_true()   # …as a normal solo game

	_main._solo_both_ai = true

	assert_bool(_main._deployment_gate_refuses_start()) \
		.override_failure_message("the gate refuses an unattended both-AI run — no human is present to place anything, so every self-play batch would deadlock on it") \
		.is_false()
