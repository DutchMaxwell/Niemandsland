class_name TableArrival
extends Node
## What greets the player when the table is revealed after a hand-over from the menu. The one place that decides
## which card shows and when, and owns the cards' lifetimes. Started by TableRevealGate, so the tutorial, lessons
## and the test harness never see it.
##
## The invite card: the host of an online room, once the relay has given the room its code, during deployment;
## once per code (a relay reconnect re-announcing the same code does not raise it again). The top bar's ONLINE chip
## opens it again for host and guest alike; the game leaving deployment closes it.
##
## The arrival card: a new or joined table with no army on it, during deployment (never a loaded game). Its three
## lines open the army import, the second army or NACHTMAHR's list (online: the invite card) and Start / Ready; it
## follows the armies and the players, hides under the game menu, and goes with deployment or its close box.

const AUTOMATIC := "Rules automation is on — deploy, ready up, then the game applies the rules it models"
const AFTER_HUD_S := 0.4
const HUD_STAGGER_S := 0.06
const HUD_WITHIN_S := 0.9
const HUD_REDUCED_S := 0.12

static var _hud_last_piece_ms := 0   # when play_hud starts its last piece (the arrival card follows it)
const MANUAL := "Multiplayer is manual play — deploy, ready up, then take turns like at a real table (no automation)."

var _main: Node
var _invite: InviteCard
var _code_shown := ""
var _arrival: ArrivalCard


## The HUD arrives piece by piece: each visible direct child fades in over DUR_PANEL_IN, 60 ms apart, all inside
## 900 ms (closer together when there are many). A piece whose alpha is not 1 is driven by its own code and left
## alone. Reduce Motion: the whole HUD fades once over 120 ms.
static func play_hud(hud: Control) -> void:
	if hud == null:
		return
	if UiMotion.reduced():
		hud.modulate.a = 0.0
		hud.create_tween().tween_property(hud, "modulate:a", 1.0, HUD_REDUCED_S)
		return
	hud.modulate.a = 1.0
	var pieces := hud.get_children().filter(func(c: Node) -> bool:
		return c is CanvasItem and (c as CanvasItem).visible and is_equal_approx((c as CanvasItem).modulate.a, 1.0))
	var gap := minf(HUD_STAGGER_S, (HUD_WITHIN_S - HudTokens.DUR_PANEL_IN) / maxf(1.0, pieces.size() - 1))
	var tween := hud.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in pieces.size():
		(pieces[i] as CanvasItem).modulate.a = 0.0
		tween.tween_property(pieces[i], "modulate:a", 1.0, HudTokens.DUR_PANEL_IN).set_delay(i * gap)
	_hud_last_piece_ms = Time.get_ticks_msec() + int(gap * maxf(0.0, pieces.size() - 1) * 1000.0)


static func start(main: Node, mode: String) -> TableArrival:
	var arrival := TableArrival.new()
	arrival.name = "TableArrival"
	main.add_child(arrival)
	arrival._watch(main, mode)
	return arrival


func _watch(main: Node, mode: String) -> void:
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
			if not _deploying():
				if is_instance_valid(_invite):
					_invite.close()
				if is_instance_valid(_arrival):
					_arrival.queue_free())
	if mode != "load" and _deploying() and (armies.get("armies") as Dictionary).keys().all(_is_ai):
		if UiMotion.reduced():
			_show_arrival()
		else:
			var wait := AFTER_HUD_S + maxf(0.0, (_hud_last_piece_ms - Time.get_ticks_msec()) / 1000.0)
			get_tree().create_timer(wait).timeout.connect(_show_arrival)


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


func _show_arrival() -> void:
	if not _deploying():
		return
	_arrival = ArrivalCard.new()
	_arrival.position = Vector2(40, 150)
	_arrival.set_lines(["Bring your army", "Invite your group" if _online() else _second_line(), "Deploy and start"])
	_arrival.line_pressed.connect(_on_line)
	_arrival.dismissed.connect(_arrival.queue_free)
	_main.get_node("UI/HUD").add_child(_arrival)   # hidden with the HUD (the layout editor hides it)
	var menu: Control = _main.get("left_panel_scroll")
	if menu != null:   # the game menu stands in the same place
		menu.visibility_changed.connect(func() -> void:
			if is_instance_valid(_arrival):
				_arrival.visible = not menu.visible)
		_arrival.visible = not menu.visible
	_main.opr_army_manager.army_spawned.connect(func(_army: Variant, _models: Variant) -> void: _progress())
	_main.network_manager.player_connected.connect(func(_peer: int) -> void: _progress())
	_progress()


## Offline, line 2 names who the setup put at the table: NACHTMAHR's faction, or the second player's army.
func _second_line() -> String:
	if PendingOpponent.who == "solo":
		return "NACHTMAHR brings %s" % PendingOpponent.label.get_slice(" · ", 1)
	return "Bring the second army"


func _is_ai(seat: Variant) -> bool:
	return _main.solo_ai_slots.has(seat)


## Line 1 is done with an army in a seat that is not NACHTMAHR's; line 2 with NACHTMAHR's army (Solo), two armies
## (two players) or, online, a second player at the table.
func _progress() -> void:
	if not is_instance_valid(_arrival):
		return
	var seats: Array = _main.opr_army_manager.armies.keys()
	var second: bool = seats.size() >= 2
	if _online():
		second = not _main.network_manager.connected_peers.is_empty()
	elif PendingOpponent.who == "solo":
		second = seats.any(_is_ai)
	_arrival.set_flags([not seats.all(_is_ai), second])


func _on_line(index: int) -> void:
	match index:
		0:
			_main._on_import_opr_army()
			if not _online() and PendingOpponent.who == "solo":   # the seat NACHTMAHR does not hold
				_main.opr_import_dialog.set_player(1 if PendingOpponent.slot == 2 else 2)
		1:
			if _online():
				_reopen()
			elif PendingOpponent.who == "solo":
				if not _main.opr_army_manager.armies.keys().any(_is_ai):   # the list failed: load it again
					_main._load_ai_opponent_list(PendingOpponent.file, PendingOpponent.slot)
			else:
				_main.opr_import_dialog.set_player(2)
				_main.opr_import_dialog.show()
		2:
			_main._on_start_game_pressed()


func _online() -> bool:
	return _main.network_manager.is_multiplayer_active()


func _deploying() -> bool:
	var armies: Object = _main.get("opr_army_manager")
	return armies != null and armies.has_method(&"is_deployment_phase") and armies.is_deployment_phase()
