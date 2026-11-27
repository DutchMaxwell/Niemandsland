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
