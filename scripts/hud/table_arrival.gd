class_name TableArrival
extends Node
## What greets the player when the table is revealed after a hand-over from the menu. The one place that decides
## which card shows and when, and owns the cards' lifetimes. Started by TableRevealGate, so the tutorial, lessons
## and the test harness never see it.
##
## The invite card: the host of an online room, once the relay has given the room its code, during deployment;
## once per code (a relay reconnect re-announcing the same code does not raise it again). The top bar's ONLINE chip
## opens it again for host and guest alike; the game leaving deployment closes it.

const AUTOMATIC := "Rules automation is on — deploy, ready up, then the game applies the rules it models"
const MANUAL := "Multiplayer is manual play — deploy, ready up, then take turns like at a real table (no automation)."

var _main: Node
var _invite: InviteCard
var _code_shown := ""


static func start(main: Node, mode: String) -> TableArrival:
	var arrival := TableArrival.new()
	arrival.name = "TableArrival"
	main.add_child(arrival)
	arrival._watch(main, mode)
	return arrival


func _watch(main: Node, _mode: String) -> void:
	_main = main
	var lobby: InternetLobby = main.get("internet_lobby")
	if lobby != null:
		lobby.room_code_ready.connect(_on_code)
		if not lobby.room_code.is_empty():
			_on_code(lobby.room_code)
	var bar: Node = main.get("_top_bar")
	if bar != null and bar.has_signal(&"link_pressed"):
		bar.link_pressed.connect(_reopen)
	var armies: Object = main.get("opr_army_manager")
	if armies != null and armies.has_signal(&"game_phase_changed"):
		armies.game_phase_changed.connect(func(_phase: int) -> void:
			if is_instance_valid(_invite) and not _deploying():
				_invite.close())


func _on_code(code: String) -> void:
	var net: Object = _main.get("network_manager")
	if code.is_empty() or code == _code_shown or net == null or not net.is_host or not _deploying():
		return
	_code_shown = code
	_open(code)


func _reopen() -> void:
	var lobby: InternetLobby = _main.get("internet_lobby")
	var code := lobby.room_code if lobby != null and not lobby.room_code.is_empty() else _code_shown
	if not code.is_empty() and _deploying():
		_open(code)


func _open(code: String) -> void:
	if not is_instance_valid(_invite):
		_invite = InviteCard.new()
		_main.get_node("UI").add_child(_invite)
		_invite.setup(_main)
	var automatic: bool = _main.has_method("_solo_engine_automatic") and _main._solo_engine_automatic()
	_invite.open(code, AUTOMATIC if automatic else MANUAL)


func _deploying() -> bool:
	var armies: Object = _main.get("opr_army_manager")
	return armies != null and armies.has_method(&"is_deployment_phase") and armies.is_deployment_phase()
