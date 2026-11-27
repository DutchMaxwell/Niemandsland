extends GdUnitTestSuite
## E2E — what greets the player when the table is revealed (menu steps 49.4-49.7), on the real main.tscn in harness
## mode. The host of an online room gets the invite card once the relay has given the room its code.
## Red before 49.4: there is no res://scripts/hud/table_arrival.gd.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SCRIPT := "res://scripts/hud/table_arrival.gd"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _start(mode: String) -> bool:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no table arrival").is_true()
	if not ResourceLoader.exists(SCRIPT):
		return false
	(load(SCRIPT) as GDScript).call("start", _main, mode)
	return true


func _invite() -> Control:
	var cards := _main.find_children("*", "InviteCard", true, false)
	return null if cards.is_empty() else cards[0] as Control


func test_the_host_gets_the_invite_card_once_per_code_and_the_chip_reopens_it() -> void:
	_main.network_manager.is_host = true
	if not _start("new"):
		return
	_main.internet_lobby.room_code_ready.emit("ABC123")
	await _runner.simulate_frames(2)
	var card := _invite()
	assert_object(card).override_failure_message("no invite card on the code").is_not_null()
	if card == null:
		return
	assert_bool(card.visible).is_true()
	assert_bool(card.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "ABC-123")).is_true()
	(card.find_child("KeepSettingUp", true, false) as Button).pressed.emit()
	_main.internet_lobby.room_code_ready.emit("ABC123")   # a relay reconnect re-announces the same code
	await _runner.simulate_frames(2)
	assert_bool(card.visible).override_failure_message("the same code raised the card again").is_false()
	_main.find_child("TopBar", true, false).link_pressed.emit()
	await _runner.simulate_frames(2)
	assert_bool(card.visible).override_failure_message("the ONLINE chip did not reopen it").is_true()


## A guest knows the code it joined with: no card by itself, the ONLINE chip opens it.
func test_a_guest_gets_the_card_only_from_the_chip() -> void:
	_main.network_manager.is_host = false
	_main.internet_lobby.room_code = "ABC123"
	if not _start("join"):
		return
	await _runner.simulate_frames(2)
	var card := _invite()
	assert_bool(card != null and card.visible).override_failure_message("a guest got the card by itself").is_false()
	_main.find_child("TopBar", true, false).link_pressed.emit()
	await _runner.simulate_frames(2)
	card = _invite()
	assert_bool(card != null and card.visible).override_failure_message("the chip did not open it").is_true()


func _arrival() -> Control:
	var cards := _main.find_children("*", "ArrivalCard", true, false)
	return null if cards.is_empty() else cards[0] as Control


## Step 49.6: a new, empty table greets the player with the arrival card; a loaded game does not; an army moves it
## on; leaving deployment takes it away (red before: no card).
func test_a_new_empty_table_shows_the_arrival_card_and_follows_the_armies() -> void:
	if not _start("new"):
		return
	await _runner.simulate_frames(10, 100)   # it stands 400 ms after the HUD has arrived
	var card := _arrival()
	assert_object(card).override_failure_message("no arrival card on a new table").is_not_null()
	if card == null:
		return
	assert_bool(card.is_visible_in_tree()).is_true()
	assert_str(String(card.call("state", 0))).is_equal("now")
	_main.opr_army_manager.armies[1] = OPRApiClient.OPRArmy.new()
	_main.opr_army_manager.army_spawned.emit(_main.opr_army_manager.armies[1], [] as Array[Node3D])
	assert_str(String(card.call("state", 1))).is_equal("now")
	_main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.PLAYING)
	await _runner.simulate_frames(2)
	assert_bool(is_instance_valid(card) and card.is_inside_tree()).override_failure_message("the card outlived deployment").is_false()


func test_a_loaded_game_gets_no_arrival_card() -> void:
	if not _start("load"):
		return
	await _runner.simulate_frames(10, 100)
	assert_object(_arrival()).is_null()


func _pieces() -> Array:
	var hud := _main.get_node("UI/HUD") as Control
	return hud.get_children().filter(func(c: Node) -> bool: return c is CanvasItem and (c as CanvasItem).visible)


## Step 49.7: the HUD arrives piece by piece - 60 ms in, the first piece is ahead of the last; by 900 ms every
## piece stands; with Reduce Motion all stand after 120 ms (red before: one block, no play_hud).
func test_the_hud_arrives_piece_by_piece() -> void:
	var script: GDScript = load(SCRIPT) if ResourceLoader.exists(SCRIPT) else null
	assert_bool(script != null and script.has_method("play_hud")).override_failure_message("no play_hud").is_true()
	if script == null or not script.has_method("play_hud"):
		return
	await _runner.simulate_frames(10, 100)   # the boot's own arrival (harness starts reveal too) has settled
	var hud := _main.get_node("UI/HUD") as Control
	script.call("play_hud", hud)
	await _runner.simulate_frames(6, 10)
	var pieces := _pieces()
	assert_float((pieces[0] as CanvasItem).modulate.a).is_greater((pieces[-1] as CanvasItem).modulate.a)
	await _runner.simulate_frames(10, 100)
	for piece: CanvasItem in _pieces():
		assert_float(piece.modulate.a).override_failure_message(piece.name).is_equal_approx(1.0, 0.001)


func test_with_reduce_motion_the_hud_stands_after_120_ms() -> void:
	var settings: Node = get_tree().root.get_node_or_null("GraphicsSettings")
	var script: GDScript = load(SCRIPT) if ResourceLoader.exists(SCRIPT) else null
	if settings == null or script == null or not script.has_method("play_hud"):
		fail("no play_hud")
		return
	await _runner.simulate_frames(10, 100)   # the boot's own arrival has settled
	var before: bool = settings.reduce_motion
	settings.reduce_motion = true
	var hud := _main.get_node("UI/HUD") as Control
	script.call("play_hud", hud)
	await _runner.simulate_frames(4, 50)
	settings.reduce_motion = before
	assert_float(hud.modulate.a).is_equal_approx(1.0, 0.001)
	for piece: CanvasItem in _pieces():
		assert_float(piece.modulate.a).is_equal_approx(1.0, 0.001)
