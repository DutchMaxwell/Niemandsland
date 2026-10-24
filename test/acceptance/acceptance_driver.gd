extends Node
## Acceptance driver (tools/acceptance/run_acceptance.sh): plays ONE role of ONE scenario in a real windowed
## instance. It acts only where a player acts - buttons, fields, the radial menu, found by node name or by
## visible text - and judges only what a player sees: labels, toasts, cards, battle-log and game-log lines.
## Every checkpoint writes a markdown row plus a screenshot; frame gaps > 2 s are counted as stalls.

const LISTS := ["__FfT0jOYHtc", "gLi7he9YFjEt"]   # the public Army Forge lists of the tutorial board (P1, P2)
var o := {"role": "solo", "scenario": "1", "out": "user://", "relay": ""}
var step := "boot"
var _t := Time.get_ticks_msec()
var _gaps: PackedStringArray = []
var _slow := {}   # step -> ms spent in frames > 250 ms
var _rows := ""
var _seen: PackedStringArray = []   # battle-log lines and toasts as they appeared
var _log_hooked: Object = null

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size() - 1:
		if a[i].begins_with("--"):
			o[a[i].substr(2)] = a[i + 1]
	get_tree().current_scene = null   # this node stays under /root while the game changes scenes
	get_tree().change_scene_to_file("res://scenes/startup_menu.tscn")
	var close: bool = (await call("_scenario_" + o.scenario.left(1), o.scenario.ends_with("c"))) == true
	if _rows == "" and not close:   # an early exit is a failure too, never an empty (green) report
		await _check("end", false, "no checkpoint reached; stopped at '%s'" % step)
	FileAccess.open("%s/%s.md" % [o.out, o.role], FileAccess.WRITE).store_string(_rows)
	FileAccess.open("%s/%s.stalls" % [o.out, o.role], FileAccess.WRITE).store_string(
		"- s%s %s: %d gap(s) > 2 s %s (%d frames in %d s)\n" % [o.scenario, o.role, _gaps.size(), ", ".join(_gaps),
		Engine.get_process_frames(), Time.get_ticks_msec() / 1000] + "  slow frames (> 250 ms), ms per step: %s\n" % _slow)
	FileAccess.open("%s/%s.seen.txt" % [o.out, o.role], FileAccess.WRITE).store_string("\n".join(_seen))
	# The player's window close: the window manager's request (wmctrl), else the same request in-engine.
	if close and OS.execute("wmctrl", ["-i", "-c", "0x%x" % DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)]) != 0:
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	await get_tree().create_timer(5.0 if close else 0.1).timeout
	get_tree().quit()

func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _t > 2000:
		_gaps.append("%.1f s at '%s'" % [(now - _t) / 1000.0, step])
	if now - _t > 250:   # slow frames (< 4 fps) do not stall the loop, but starve everything polled per frame
		_slow[step] = _slow.get(step, 0) + now - _t
	_t = now
	var main := get_tree().root.get_node_or_null("Main")
	if main != null and main.get("battle_log") != null and _log_hooked != main.battle_log:
		_log_hooked = main.battle_log
		_log_hooked.entry_added.connect(func(e: Dictionary) -> void: _seen.append(str(e.get("text", ""))))
	var toast: Label = (main.get_node_or_null("UI/SoloActionToast") as Label) if main != null else null
	if toast != null and toast.visible and (_seen.is_empty() or _seen[-1] != "toast: " + toast.text):
		_seen.append("toast: " + toast.text)

func _shown(n: Node) -> bool:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return false
	var w := n.get_viewport() as Window
	while w != null and w != get_tree().root:
		if not w.visible:
			return false
		w = w.get_parent().get_viewport() as Window if w.get_parent() != null else null
	return true

func _first(cls: String, pred: Callable) -> Node:   # dialog buttons are internal children: walk those too
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls) and _shown(n) and pred.call(n):
			return n
		if not n is Node3D or n.get_parent() == get_tree().root:   # the table scene's root is 3D, its UI is not
			stack.append_array(n.get_children(true))
	return null

func _screen_text(sub: String) -> String:   # first visible text containing `sub`
	var n := _first("Control", func(c: Control) -> bool: return (c is Label or c is Button or c is RichTextLabel) and str(c.get("text")).findn(sub) >= 0)
	return str(n.text) if n != null else ""

func _game_log() -> String:   # this instance's own game log (user://, flushed per line in debug builds)
	return FileAccess.get_file_as_string("user://logs/niemandsland.log")

func _wait(what: String, pred: Callable, secs := 30.0) -> Variant:
	step = what
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		var v: Variant = pred.call()
		if v:
			return v
		await get_tree().create_timer(0.25).timeout
	return null

func _press(key: String, secs := 30.0, part := false, need := true) -> bool:   # visible, enabled: node name or text
	var b: BaseButton = await _wait("press " + key, func() -> Variant: return _first("BaseButton", func(x: BaseButton) -> bool:
		var t := str(x.get("text")).strip_edges()
		return not x.disabled and (x.name == key or t == key or (part and key in t))), secs)
	if b == null:
		if need:
			await _check("step", false, "'%s' never became pressable" % key)
		return false
	if b.toggle_mode:
		b.button_pressed = not b.button_pressed
	b.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	return true

func _type(placeholder: String, value: String) -> void:   # a visible field, by its placeholder text
	var e := _first("LineEdit", func(x: LineEdit) -> bool: return placeholder in x.placeholder_text) as LineEdit
	if e != null:
		e.text = value
		e.text_changed.emit(value)

func _put(flag: String, value := "") -> void:
	FileAccess.open("%s/%s" % [o.out, flag], FileAccess.WRITE).store_string(value)

func _peek(flag: String, secs := 120.0) -> String:   # waits for the other instance's flag file
	var p := "%s/%s" % [o.out, flag]
	return str(await _wait("wait for " + flag, func() -> Variant: return FileAccess.get_file_as_string(p) + " " if FileAccess.file_exists(p) else null, secs)).strip_edges()

func _check(id: String, ok: bool, evidence: String) -> void:
	await RenderingServer.frame_post_draw
	var png := "%s_%s.png" % [o.role, id.replace(".", "_")]
	get_viewport().get_texture().get_image().save_png("%s/%s" % [o.out, png])
	_rows += "| s%s %s %s | %s | %s (%s) |\n" % [o.scenario, o.role, id, "PASS" if ok else "FAIL",
		evidence.replace("|", "/").replace("\n", " ").left(300), png]

func _main() -> Node:
	return get_tree().root.get_node_or_null("Main")

func _at_table() -> bool:   # the table is up; the player opens the left menu (☰)
	if await _wait("table loads", func() -> Variant: return _main() != null and _main().is_node_ready(), 180.0) == null:
		return false
	await get_tree().create_timer(3.0).timeout
	return await _menu(true)

func _menu(open: bool) -> bool:   # the left menu (☰)
	return (_main().get_node("UI/HUD/LeftPanelScroll") as Control).visible == open or await _press("HamburgerButton")

func _new_table() -> bool:
	await _press("Close", 15.0, false, false)
	return await _press("StartBattleBtn", 60.0) and await _press("Create table", 30.0, true) and await _at_table()

func _online_table(host: bool) -> bool:   # Create a room / Join with a code, on the relay this run uses
	var code := "" if host else await _peek("code", 300.0)
	await _press("Close", 15.0, false, false)
	if not (await _press("OnlineBtn", 60.0) and await _press("HostOnlineBtn" if host else "JoinOnlineBtn")):
		return false
	_type("Player name", o.role.capitalize())
	_type("ABC-123", code)
	_type("wss://", o.relay)
	if not await _press("Prepare table" if host else "Join"):
		return false
	return (not host or await _press("Create table", 30.0, true)) and await _at_table()

func _import(p: int, ai := false) -> bool:   # Import OPR Army... -> share link -> LOAD ARMY -> player -> IMPORT ARMY
	var tray := "on Player %d's tray" % (p + 1)
	var before := _game_log().count(tray)
	if not await _press("ImportOPRArmy"):
		return false
	_type("Paste a share link", LISTS[p])
	await _press("LOAD ARMY")
	var opt := _first("OptionButton", func(x: OptionButton) -> bool: return x.get_item_text(0).begins_with("Player 1")) as OptionButton
	if opt != null:
		opt.select(opt.get_item_index(p + 1))
		opt.item_selected.emit(opt.selected)
	var tick := _first("CheckBox", func(x: CheckBox) -> bool: return x.text.begins_with("AI-controlled")) as CheckBox
	if tick != null:
		tick.button_pressed = ai
	return await _press("IMPORT ARMY", 90.0) and await _wait("army %d spawns" % (p + 1),
		func() -> Variant: return _game_log().count(tray) > before, 300.0) != null

func _units(pid: int) -> Array:   # where the player's units stand (to right-click them)
	return _main().opr_army_manager.game_units.values().filter(func(u: GameUnit) -> bool: return int(u.unit_properties.get("player_id", 0)) == pid)

func _radial(u: GameUnit) -> Array:   # right-click on the whole unit = the ObjectManager's context-menu request
	_main().get_node("ObjectManager").context_menu_requested.emit(Vector2(900, 500), u.models.map(func(m: ModelInstance) -> Node: return m.node))
	await get_tree().create_timer(0.4).timeout
	var r: Node = _main().get_node("UI/RadialMenu")
	return r._items + r._tier

## The player keeps the smallest unit of `pid` he can grab, takes `others` and the rest off, drags it onto the table.
func _deploy_one(pid: int, to: Vector3, others: Array = []) -> GameUnit:
	var keep: GameUnit = _units(pid).filter(func(u: GameUnit) -> bool: return not u.is_attached() and _grab(u) != null).reduce(
		func(x: GameUnit, y: GameUnit) -> GameUnit: return y if y.models.size() < x.models.size() else x)
	for u in others + _units(pid):
		if u != keep:   # a one-model unit gets the model menu
			_pick("delete_unit" if (await _radial(u)).any(func(it: Object) -> bool: return it.id == "delete_unit") else "delete_model")
	await _drag(keep, to)
	return keep

func _grab(u: GameUnit) -> Variant:   # window pixel where the cursor really hits one of the unit's models, else null
	var cam := get_viewport().get_camera_3d()   # (a tray rim or table wall can hide a model's foot)
	for m: ModelInstance in u.models:
		for h: float in [0.01, 0.03, 0.05]:
			var c := cam.unproject_position(m.node.global_position + Vector3(0.0, h, 0.0))
			var hit := cam.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
				cam.project_ray_origin(c), cam.project_ray_origin(c) + cam.project_ray_normal(c) * 100.0))
			if hit.get("collider") == m.node:
				return get_viewport().get_final_transform() * c   # camera: canvas coordinates; events: window pixels
	return null

func _drag(u: GameUnit, to: Vector3) -> void:   # the player's mouse: double-click the unit, then drag it to `to`
	await _menu(false)   # the open menu and the dice roller cover the trays
	var dice := _first("Button", func(b: Button) -> bool: return b.name == "CloseButton" and str(b.get_parent().get_child(0).get("text")).containsn("dice"))
	if dice != null:
		dice.pressed.emit()
	var cam := get_viewport().get_camera_3d()
	var a: Vector2 = _grab(u) if _grab(u) != null else Vector2.ZERO
	var path: Array = [[a, true, true], [a, false, false], [a, true, false]]
	for k in 8:
		path.append([a.lerp(get_viewport().get_final_transform() * cam.unproject_position(to), (k + 1) / 8.0), true, false])
	path.append([path[-1][0], false, false])
	for i in path.size():
		var p: Array = path[i]
		var e: InputEventMouse = InputEventMouseButton.new() if i < 3 or i == path.size() - 1 else InputEventMouseMotion.new()
		e.position = p[0]
		e.global_position = p[0]
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if p[1] else 0
		if e is InputEventMouseButton:
			e.set("button_index", MOUSE_BUTTON_LEFT); e.set("pressed", p[1]); e.set("double_click", p[2])
		Input.parse_input_event(e)
		await get_tree().create_timer(0.1).timeout

func _pick(id: String) -> void:   # a ring wedge, else a pill of the "More" tier, else close the menu
	var r: Node = _main().get_node("UI/RadialMenu")
	for i in r._items.size():
		if r._items[i].id == id:
			r._select_index(i)
			return
	if r._tier.any(func(it: Object) -> bool: return it.id == id):
		r.action_selected.emit(id, r._context)
	r.close()

## 1. Hotseat, two armies, no tick: deployment refuses, no AI in the radial, the game end names P1/P2.
func _scenario_1(_c: bool):
	if not (await _new_table() and await _import(0) and await _import(1)):
		return false
	var n0 := _seen.size()
	await _press("Start Deployment")
	await _wait("a wrong roll-off would run now", func() -> Variant: return null, 6.0)
	var said := " / ".join(_seen.slice(n0))
	await _check("1.1", "tick an army as AI" in said and not "roll-off" in said, "after Start Deployment: " + said)
	var bad: Array = []
	for pid in [1, 2]:
		for it in await _radial(_units(pid)[0]):
			var line := "P%d %s: %s / %s" % [pid, it.id, it.label, it.tooltip]
			if it.id.begins_with("solo_auto_") or RegEx.create_from_string("\\bAI\\b|NACHTMAHR").search(line) != null:
				bad.append(line)
		if pid == 2:
			await _check("1.2", bad.is_empty(), "radial entries naming the AI: %s" % [bad if not bad.is_empty() else "none"])
		_pick("")
	var keep := await _deploy_one(1, Vector3(-0.3, 0.0, 0.0), _units(2))   # a short game: P2 takes its units off
	for _i in 40:
		if _screen_text("rounds played") != "":
			break
		if not keep.is_activated:
			await _radial(keep)
			_pick("toggle_activate")
		await _wait("round ends", func() -> Variant: return null, 1.0)
	var end := _screen_text("rounds played")
	await _check("1.3", end.contains("P1") and end.contains("wins") and not end.contains("NACHTMAHR"), "game end: %s" % [
		end if end != "" else "no summary; last lines: " + " / ".join(_seen.slice(-4))])

## 2. Online: room, join by code, both import, both Ready -> play starts; one handshake; the rules switch shows.
func _scenario_2(_c: bool):
	var host: bool = o.role == "host"
	if not await _online_table(host):
		return false
	if host:   # the player shares the code, waits for the guest, then both import
		_put("code", (await _wait("room code", func() -> Variant: return _screen_text("Room: "), 90.0)).trim_prefix("Room: ").replace("-", ""))
		await _wait("guest joins", func() -> Variant: return _screen_text("joined)"), 300.0)
		await _press("Not now", 10.0, false, false)   # the one-time "Play with rules automation?" question
	if not await _import(0 if host else 1):
		return false
	# The table is frozen while either side still builds the other's army: deploy once both are built.
	await _wait("the other army is built", func() -> Variant: return _game_log().contains("Army built for player_id=%d" % (2 if host else 1)), 600.0)
	_put(o.role + "_synced")
	await _peek("guest_synced" if host else "host_synced", 600.0)
	await _wait("other side loads", func() -> Variant: return _screen_text("to finish loading") == "", 120.0)
	await _deploy_one(1 if host else 2, Vector3(-0.3 if host else 0.3, 0.0, 0.0))
	_put(o.role + "_deployed")
	await _peek("guest_deployed" if host else "host_deployed", 300.0)
	await _menu(true)
	await _press("StartGameButton")
	var start = await _wait("play starts", func() -> Variant: return _first("Label", func(l: Label) -> bool: return l.text == "PLAYING"), 60.0)
	await _check("2.1", start != null, "after both pressed Ready: %s" % ("play started" if start else
		"still '%s'" % _main().find_child("GamePhaseStatus", true, false).get("text")))
	var sw := _first("CheckButton", func(x: CheckButton) -> bool: return x.text == "Rules automation")
	await _check("2.2", sw != null, "the 'Rules automation' switch is %s" % ("on screen" if sw else "nowhere on screen"))
	if host:
		var n := _game_log().count("passed handshake")
		await _check("2.3", n == 1, "host log: %d 'passed handshake' line(s) for one join" % n)
	_put(o.role + "_done")
	await _peek("guest_done" if host else "host_done", 60.0)

## 3. Online leave: the host goes back to the menu (3c: closes its window); the guest is told within 2 s;
## the host then opens Trial by Fire "First Steps" and the lesson table is not empty.
func _scenario_3(window_close: bool) -> bool:
	var host: bool = o.role == "host"
	if not await _online_table(host):
		return false
	if not host:   # watch from the moment the table is up; the host leaves only after this flag
		_put("guest_watching")
		var seen = await _wait("told that the host left", func() -> Variant: return _screen_text("host left"), 60.0)
		var dt := Time.get_unix_time_from_system() - float(FileAccess.get_file_as_string(o.out + "/host_left"))
		await _check("3.1", seen != null and dt <= 2.0, "%s after %.1f s" % [("guest sees '%s'" % seen) if seen else
			"no notice; status '%s'" % _main().find_child("StatusLabel", true, false).get("text"), dt])
		return false
	_put("code", (await _wait("room code", func() -> Variant: return _screen_text("Room: "), 90.0)).trim_prefix("Room: ").replace("-", ""))
	await _peek("guest_watching", 300.0)
	await _press("Not now", 10.0, false, false)   # the one-time "Play with rules automation?" question
	if window_close:
		_put("host_left", str(Time.get_unix_time_from_system()))
		return true
	await _press("EndBattleBtn")
	_put("host_left", str(Time.get_unix_time_from_system()))
	await _press("Yes, Exit")
	if await _press("LearnBtn", 60.0) and await _press("SpielschuleBtn") and await _press("S-01 · FIRST STEPS", 30.0, true):
		var card = await _wait("lesson card", func() -> Variant: return _screen_text("Step 1 of"), 90.0)
		var why := _game_log().get_slice("Only the host", 1).get_slice("\n", 0)
		await _check("3.2", card != null, "First Steps: %s" % ("'%s' on screen" % card if card else "no lesson card; log: Only the host" + why))
	return false

## 4. Solo (P2 ticked as AI): the radial of an eligible P1 unit offers no Charge / Advance & Shoot / Rush.
func _scenario_4(_c: bool):
	if not (await _new_table() and await _import(0) and await _import(1, true)):
		return false
	var u: GameUnit = _units(1)[0]
	var labels := (await _radial(u)).map(func(it: Object) -> String: return it.label)
	await _check("4.1", not labels.any(func(l: String) -> bool: return l in ["Charge", "Advance (& Shoot)", "Rush"]),
		"radial of P1 %s: %s" % [u.get_name(), ", ".join(labels)])
	_pick("")
