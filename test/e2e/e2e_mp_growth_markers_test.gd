extends GdUnitTestSuite
## E2E — coverage wave: per-round Growth Markers tick in a PLAIN multiplayer room.
##
## THE GAP. The per-round growth tick (_solo_growth_round_start) only ever ran behind the solo
## alternation machinery, so a human-vs-human multiplayer room silently got none of it (audit
## row 25). The audit's literally-cited gate (the early return inside _solo_round_start) is a
## dead end: that function is only ever reached via _solo_end_round <- _do_next_round's SOLO
## branch, so in a plain MP room it is never invoked at all. The real fix wires
## _solo_growth_round_start into the TWO places a plain-MP round advance actually runs: the
## pressing peer's _do_next_round MP branch and the receiving peer's _on_remote_round_advanced.
##
## WHY NO WIRE TRAFFIC. The tick is deterministic per-unit bookkeeping (alive count, reserve
## status, attached-ness, Shaken flag, existing counter — all already synced state); run once
## per round advance on EACH peer, the counters converge without a broadcast. The battle log
## names every tick.
##
## THE FIXTURE. A plain MP room: solo_ai_slots empty, no solo controller, a live FakeNet
## session — exactly the configuration the gap blocks today. "Piercing Growth" is the gf
## ALIEN HIVES book's per_round Growth Markers rule (assets/solo/rules_mechanics_gf.json):
## +1 marker per round while the unit stands, cap 4.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const GROWTH_KEY := "growth_piercing_growth"


## Stand-in for NetworkManager at main's seam: a live session that records outbound frames.
## _do_next_round's MP branch broadcasts the round advance, so the fake must take that call.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func broadcast_round_advance() -> void:
		sent.append({"kind": "round_advance"})


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	# PLAIN MP room: no AI slot, no solo controller, live session — _solo_alternation_active()
	# must be false so _do_next_round takes its MP branch.
	_main.solo_ai_slots = {}
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


func _at(inches_x: float) -> Vector3:
	return Vector3(inches_x * INCH, 0.0, 0.0)


## Register a fixture unit and stamp the book that actually FIELDS these rules — the registry
## gate is system-scoped, so an unstamped unit resolves no primitive at all (same seam as the
## utility buff wave's suite). The faction stamp is "alien_hives" because that is the only gf
## book section whose per_round Growth Markers entry ("Piercing Growth") this fixture tick reads.
func _reg(pid: int, unit_name: String, positions: Array, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "alien_hives"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _growth_of(u: GameUnit) -> int:
	return int(u.unit_properties.get(GROWTH_KEY, 0))


# === 1. The pressing peer =========================================================================

## THE CLAIM: the peer that presses "Next Round" ticks per-round growth in a plain MP room.
## Before this wave the counter stayed 0 — MP had no round-start sequence at all.
func test_local_next_round_ticks_per_round_growth_in_plain_mp(timeout := 120000) -> void:
	var u := _reg(1, "Riflemen", [_at(6.0)], ["Piercing Growth"])
	assert_int(RulesRegistry.unit_rules_of_primitive(u, "Growth Markers").size()) \
		.override_failure_message("fixture check: Piercing Growth did not resolve as a Growth Markers rule") \
		.is_greater_equal(1)
	assert_bool(_main._solo_alternation_active()) \
		.override_failure_message("fixture check: the room must be plain MP (no solo alternation active)") \
		.is_false()
	assert_int(_growth_of(u)).is_equal(0)

	await _main._do_next_round()

	assert_int(_growth_of(u)) \
		.override_failure_message("the local peer's round advance did not tick per-round growth in MP") \
		.is_equal(1)
	assert_array(_fake.sent) \
		.override_failure_message("fixture check: the MP branch must still broadcast the round advance") \
		.is_not_empty()


# === 2. The receiving peer =======================================================================

## …and the peer that RECEIVED the round advance over the network (which never runs
## _do_next_round — the RPC already advanced its state) ticks the SAME counter through
## _on_remote_round_advanced, so both sides land identical without any extra wire traffic.
func test_remote_round_advance_ticks_per_round_growth_in_plain_mp(timeout := 120000) -> void:
	var u := _reg(1, "Riflemen", [_at(6.0)], ["Piercing Growth"])
	assert_int(_growth_of(u)).is_equal(0)

	_main._on_remote_round_advanced()

	assert_int(_growth_of(u)) \
		.override_failure_message("the receiving peer's round advance did not tick per-round growth in MP") \
		.is_equal(1)
	assert_array(_fake.sent) \
		.override_failure_message("the tick must be pure bookkeeping — no growth traffic may leave this client") \
		.is_empty()
