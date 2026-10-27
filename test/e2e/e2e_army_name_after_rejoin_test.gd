extends GdUnitTestSuite
## Step 25 (P0d) — a rejoined guest's own panel row keeps its army name.
##
## The host holds no army object for a REMOTE army (its armies[] slot is null), so the army names
## that ride the full-state push only covered the host's own army; the guest rebuilt its tray with
## the fallback "Army" and its "AI plays P2 — <army>" row degraded to "AI plays P2 — Army" after a
## rejoin (seen live in test 5 on the laptop after #1874).
##
## Pinned on the real main scene: the pushed state carries the name the host learned from the army
## header, and the guest's row shows it after adopting that state.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const GUEST_NAME := "Synthetic Guest 2"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_fake_net()


func after_test() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _fake_net() -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\n" \
		+ "var sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn 2\n" \
		+ "func get_my_peer_id() -> int:\n\treturn 0\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_main.network_manager = _net


func _pushed_state() -> Dictionary:
	for s in _net.sent:
		if str((s as Array)[0]) == "sync_game_state":
			return (s as Array)[1]["state"]
	return {}


func _row_texts() -> Array:
	var out: Array = []
	for c in _main.solo_panel_box.get_children():
		if c is CheckButton and (c as CheckButton).text.begins_with("AI plays "):
			out.append((c as CheckButton).text)
	return out


func test_the_pushed_state_carries_the_remote_army_name_and_the_row_keeps_it(timeout := 120000) -> void:
	# Host side: its own army object, plus the name it learned from the guest's army header.
	var host_army := OPRApiClient.OPRArmy.new()
	host_army.name = "Synthetic Host 1"
	_main.opr_army_manager.armies[1] = host_army
	_main._remote_army_names[2] = GUEST_NAME
	var guest_unit := E2EBoot.make_unit(_main, 2, "Guest Squad", [Vector3(0.3, 0, 0)])
	_main.opr_army_manager.game_units[guest_unit.unit_id] = guest_unit

	_main._sync_state_to_peer(2)
	var state := _pushed_state()
	assert_bool(state.has("army_names")).override_failure_message("no army_names in the pushed state").is_true()
	assert_str(str((state.get("army_names", {}) as Dictionary).get(2, ""))) \
		.override_failure_message("the pushed state lost the guest army's name: %s" % str(state.get("army_names"))) \
		.is_equal(GUEST_NAME)

	# Guest side: a fresh table that only knows what the push carried.
	_main.opr_army_manager.armies.clear()
	_main._remote_army_names.clear()
	_main.solo_ai_slots = {2: true}
	await _main._rpc_sync_game_state(state)
	_main._refresh_solo_panel()
	await _runner.simulate_frames(2)
	var rows := _row_texts()
	var row := ""
	for t in rows:
		if str(t).begins_with("AI plays P2"):
			row = str(t)
	assert_bool(row.contains(GUEST_NAME)) \
		.override_failure_message("the guest row lost the army name after the re-push (got %s)" % str(rows)) \
		.is_true()
	await E2EBoot.settle(get_tree())
