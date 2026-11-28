class_name SkirmishTable
extends RefCounted
## Feature-test facade for the skirmish systems (gff / aofs) on the real table: one booted main.tscn in a seat, units
## built over ParityTable, the battle log tapped, the card's doors pressed, a pending rules epoch pinned on record.
## No rule logic lives here: a feature test asserts what a player sees, this file only sets the table up.
##
## Seats: "H" hot-seat (two humans, no AI seat), "S" human (slot 1) vs AI (slot 2), "A" both slots AI,
## "O" an agreed Automatic online room with the transport swapped for `WireNet` (frames land in `net.wire`).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254

## The receive doors main connects in _ready ([signal of the manager, main's handler]) that the O seat rewires.
const RECEIVE_DOORS := [["remote_activation_updated", "_on_remote_activation_updated"],
	["turn_state_received", "_on_turn_state_received"], ["command_received", "_on_network_command"],
	["remote_wounds_updated", "_on_remote_wounds_updated"], ["remote_round_advanced", "_on_remote_round_advanced"]]

## Every epoch a feature test pinned through `need_epoch` (the shipped-epoch gate reads it).
static var pins: Array[int] = []


## The REAL NetworkManager with its transport swapped out (as core_activation_mp_test.gd): every frame lands in `wire`.
class WireNet extends "res://scripts/network_manager.gd":
	var active := true
	var wire: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func _validate_rpc_ready(_context: String = "") -> bool:
		return active
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		wire.append({"t": type, "p": payload, "to": target_peer})
		return true
	var human_slots: Array = []   # the slots a human peer plays (their units are asked through the wire)
	func slot_has_human_peer(slot: int) -> bool:
		return human_slots.has(slot)
	func get_my_peer_id() -> int:
		return 1
	func get_my_player_slot() -> int:
		return 1


var main: Node
var runner: Object
var lines: Array = []
var net: WireNet
var _root_before: Array
var _epoch_before: int
var _real_net: Node
var _tree: SceneTree


## Boot main.tscn for `suite` in `seat`: PLAYING, round 1, instant dice, fast pacing, auto saves, the lesson paused, the log tapped.
static func boot(suite: Node, seat: String) -> SkirmishTable:
	var t := SkirmishTable.new()
	t._tree = suite.get_tree()
	t._epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	t._root_before = E2EBoot.root_children(t._tree)
	t.runner = suite.scene_runner(E2EBoot.MAIN_SCENE)
	t.main = t.runner.scene()
	await t.runner.simulate_frames(4)
	t._real_net = t.main.network_manager
	t.main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	t.main.opr_army_manager.current_round = 1
	CoreActivation._env = 1
	match seat:
		"H":
			CoreActivation._hotseat_env = 1
			t.main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
			t.main.solo_ai_slots = {}
			SoloHarness.controller(t.main)
		"S":
			SoloHarness.start(t.main, [2], 1)
		"A":
			SoloHarness.start(t.main, [1, 2], 1)
		"O":
			t.main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
			t.main.solo_ai_slots = {}
			t.net = WireNet.new()
			t.net.is_host = true   # this table is the host, slot 1: it owns the turn token
			t.net.army_manager = t.main.opr_army_manager
			t.main.network_manager = t.net
			t.main.radial_menu_controller.network_manager = t.net
			for pair in RECEIVE_DOORS:   # main wired its receive doors to the real manager in _ready: wire the swapped one
				if t.net.has_signal(pair[0]) and t.main.has_method(pair[1]):
					t.net.connect(pair[0], Callable(t.main, pair[1]))
			SoloHarness.controller(t.main)
			t.main._apply_turn_token(1)
	SoloHarness.instant(t.main)
	SoloHarness.fast(t.main)
	SoloHarness.auto_saves(t.main)
	SoloHarness.lesson_paused(t.main)
	t.main.battle_log.entry_added.connect(t._tap)
	return t


## A clean table in the same seat for the next case (a seed scan, a twin): no units, no turn state, round 1, no lines.
func reset() -> void:
	CoreActivation.reset_all(main)
	main.object_manager._deselect_all()   # no selection may outlive the models freed below
	for u in main.opr_army_manager.game_units.values():
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.queue_free()
	main.opr_army_manager.game_units.clear()
	main._hotseat_turn = null
	main._solo_game_finished = false
	main.opr_army_manager.current_round = 1
	main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	lines.clear()


## A unit of `sys` ("gff" | "aofs") for `player`: `models` in a row 1.2 in apart along z from (x_in, z_in), Quality 4,
## Defense 4, `tough` per model, `weapon` (ParityTable shape; {} = a 24 in rifle, one attack per model), `rules`.
func unit(sys: String, player: int, name: String, models: int, tough: int, x_in: float, z_in: float,
		weapon: Dictionary = {}, rules: Array = []) -> GameUnit:
	var w := weapon if not weapon.is_empty() else {"name": "Rifle", "range_in": 24, "attacks": 1, "count": models, "rules": []}
	var u := ParityTable._make_unit(main, {"player": player, "name": name, "models": models, "x_in": x_in,
		"z_step_in": 1.2, "quality": 4, "defense": 4, "tough": tough, "game_system": sys,
		"faction_folder": "robot_legions", "rules": rules}, w)
	for i in u.models.size():
		var mi := u.models[i] as ModelInstance
		mi.model_index = i
		mi.node.global_position += Vector3(0, 0, z_in * INCH)
		mi.node.set_meta("network_id", 900 + 10 * player + main.opr_army_manager.game_units.size() * 4 + i)
		mi.node.set_meta("model_instance", mi)
	return u


func _tap(e: Dictionary) -> void:
	lines.append(str(e["text"]))


## How many logged lines begin with `prefix`.
func count(prefix: String) -> int:
	return lines.filter(func(l: String) -> bool: return l.begins_with(prefix)).size()


## The card of `gu` shows the button `text` and its controller door runs (the button's own path: card_face ->
## unit_dock._card_action -> radial_menu_controller). False when the card does not show it (nothing runs then).
func press(gu: GameUnit, text: String) -> bool:
	main.unit_dock.present_unit(gu)
	var shown := false
	for b in main.unit_dock.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree() and not b.is_queued_for_deletion():
			shown = true
	if not shown:
		return false
	var radial: Node = main.radial_menu_controller
	match text:
		"End activation":
			await radial.card_end_activation(gu)
		"Place for me":
			radial.card_place_for_me(gu)
		"Cancel":
			radial.card_cancel_activation(gu)
		_:
			return false
	return true


## True when `gu`'s presented card shows a visible Label or Button whose text holds `needle`.
func card_shows(gu: GameUnit, needle: String) -> bool:
	main.unit_dock.present_unit(gu)
	for c in main.unit_dock.find_children("*", "Control", true, false):
		if (c is Label or c is Button) and str(c.text).find(needle) != -1 and (c as Control).is_visible_in_tree() \
				and not c.is_queued_for_deletion():
			return true
	return false


## Import the card-list JSON at `path` for `player` through the table's real import door (system check included).
func import_list(path: String, player: int) -> OPRApiClient.OPRArmy:
	var client := OPRApiClient.new()   # a Node: freed here, or the suite reports it as an orphan (CI exit 101)
	var army := client.build_army_offline(JSON.parse_string(FileAccess.get_file_as_string(path)))
	client.free()
	await main._on_opr_army_imported(army, player, false)
	await E2EBoot.settle(_tree)
	return army


## A whole AI-vs-AI game on this table through the table's own both-AI loop, `opener` taking round 1's first turn.
func run_ai_game(opener := 1) -> void:
	await main._solo_run_both_ai_game(opener)
	await E2EBoot.settle(_tree)


## The game-over summary's text as the player reads it, or "" while none stands.
func summary_text() -> String:
	for c in main.get_children():
		if c is CanvasLayer and c.name == "GameOverLayer" and not c.is_queued_for_deletion():
			var label := c.find_child("Summary", true, false) as Label
			return label.text if label != null else ""
	return ""


## Press the visible button whose text is `text` anywhere in the main scene (a board prompt's answer); false if none.
func press_button(text: String) -> bool:
	for b in main.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree() and not b.is_queued_for_deletion():
			(b as Button).pressed.emit()
			return true
	return false


## A table of `feet` (the size the setup screen hands the table: 4 x 4 ft for the skirmish systems).
func table_feet(feet: Vector2) -> void:
	main._set_table_size(feet)
	await runner.simulate_frames(2)


## The table's Start Game / Ready button (its deployment gate included).
func press_start() -> void:
	main._on_start_game_pressed()
	await E2EBoot.settle(_tree)


## A ladder-free x-ledge of the generated board `seed_value` that drops `drop_in` inches: [high, low] cell centres in


## world metres (y = the cell's height), or [] when the board has none.
static func ledge(seed_value: int, drop_in: float) -> Array:
	var layout: Dictionary = (ClassDB.instantiate("NmlCore") as Object).call("boardgen_layout_themed", seed_value, "")
	var nx := int(layout["nx"])
	var cell := float(layout["cell_in"])
	var cells: Array = layout["cells"]
	var lv: Array = layout["level_in"]
	var ladders := {}
	for c in layout["connectors"]:
		ladders[[int(c["low"]), int(c["high"])]] = true
	for i in cells.size():
		if i % nx + 1 >= nx:
			continue
		var a := int(cells[i]["level"])
		var b := int(cells[i + 1]["level"])
		if a <= b or ladders.has([i + 1, i]) or not is_equal_approx(float(lv[a]) - float(lv[b]), drop_in):
			continue
		var centre := func(k: int, lvl: int) -> Vector3:
			return Vector3(((k % nx) + 0.5 - nx / 2.0) * cell * INCH, float(lv[lvl]) * INCH,
				((k / nx) + 0.5 - int(layout["nz"]) / 2.0) * cell * INCH)
		return [centre.call(i, a), centre.call(i + 1, b)]
	return []


## The card's Activate (the committed start). True when the activation is open afterwards.
func start(gu: GameUnit) -> bool:
	return await E2EBoot.start_activation(main, gu)


## The card's End activation.
func end(gu: GameUnit) -> void:
	await main.radial_menu_controller.card_end_activation(gu)


## A player's drag of `model` to `to` (world metres) over `inches`, released as the drag's release runs it: the table's
## drop check first (the core's move check, a jump included; a refusal puts the model back), then the drop door.
## False when the drop was refused.
func drop(model: ModelInstance, to: Vector3, inches: float) -> bool:
	var from: Vector3 = model.node.global_position
	model.node.global_position = to
	if main.attacked_unit_drag_refused(model.unit, inches):
		model.node.global_position = from
		return false
	await SoloHarness.drop(main, [{"node": model.node, "inches": inches, "from_raw": from,
		"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])}])
	return true


## A player's real drag of every live model of `gu` (or only the models `only`) by (dx_in, dz_in) inches under the
## movement selector `cap` (CoreActivation.CAP_ADVANCE / CAP_RUSH / CAP_CHARGE): grab, move, release, the drop door and
## its tween landed.
func walk(gu: GameUnit, dx_in: float, dz_in: float, cap: int, only: Array = []) -> void:
	var om: Node3D = main.object_manager
	om.set_movement_cap(cap)
	om._deselect_all()
	var picked: Array = only if not only.is_empty() else gu.get_alive_models()
	for m in picked:
		om._add_to_selection((m as ModelInstance).node)
	var a: Vector3 = (picked[0] as ModelInstance).node.global_position
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	om._start_dragging(cam.unproject_position(Vector3(a.x, 0.0, a.z)))
	om._update_drag(cam.unproject_position(Vector3(a.x + dx_in * INCH, 0.0, a.z + dz_in * INCH)))
	await runner.simulate_frames(1)
	om._stop_dragging()
	await runner.simulate_frames(3)
	await _tree.create_timer(0.3).timeout   # a new drop id (a millisecond stamp) for the next drag


## A player's shot of `att` at `target` through the table's human attack door.
func shoot(att: GameUnit, target: GameUnit) -> void:
	await main._run_human_attack(att, target, false)
	await E2EBoot.settle(_tree)


## A player's Shoot (`melee` false) or Fight through the radial's targeting door and a left click on `target`'s first live
## model: the click handler picks it with a ray (each target model gets a pick body, as spawned models carry), validates
## it and logs the refusal or resolves the attack.
func aim(att: GameUnit, target: GameUnit, melee := false) -> void:
	await main.solo_begin_targeting(att, melee)
	for m in target.get_alive_models():
		var n: Node3D = (m as ModelInstance).node
		if n.get_node_or_null("FtPick") == null:
			var body := StaticBody3D.new()
			body.name = "FtPick"
			body.set_meta("game_unit", target)
			var shape := CollisionShape3D.new()
			var ball := SphereShape3D.new()
			ball.radius = 0.016
			shape.shape = ball
			body.add_child(shape)
			n.add_child(body)
			body.position = Vector3(0, 0.03, 0)
	await runner.simulate_frames(3)
	var at: Vector3 = (target.get_alive_models()[0] as ModelInstance).node.global_position + Vector3(0, 0.03, 0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = main.get_viewport().get_camera_3d().unproject_position(at)
	await main._solo_targeting_input(click)
	await E2EBoot.settle(_tree)


## The guided solo deployment (vs the AI) standing in its SCOUT phase with the human on turn and `placed` (units already
## down) recorded - the state the deploy flow reaches after the main phase (as e2e_deploy_phases_test arms it).
func scout_phase(placed: Array) -> void:
	var seen := {}
	for u in placed:
		seen[(u as GameUnit).unit_id] = true
	main._solo_deploy_fsm = {"phase": "scout", "winner_is_ai": false, "human_turn": true, "human_out": false,
		"human_placed": seen, "objectives": [], "seed": 5}


## The human's "✓ Unit placed" in the guided deployment; true when the placement was taken (the unit is on record).
func deploy_done(gu: GameUnit) -> bool:
	main._solo_deploy_human_done_one()
	await runner.simulate_frames(2)
	return (main._solo_deploy_fsm.get("human_placed", {}) as Dictionary).has(gu.unit_id)


## The solo action toast's text (the deployment refusals speak there).
func toast_text() -> String:
	var t := main.get_node_or_null("UI/SoloActionToast") as Label
	return "" if t == null else t.text


## O seat: a human guest (peer 2) holds slot 2 - its units' owner choices go over the wire; `timeout_s` bounds the wait.
func seat_guest(timeout_s: float) -> void:
	net.human_slots = [2]
	net.peer_to_slot = {1: 1, 2: 2}
	net.connected_peers.assign([2])
	main._owner_requests_instance().timeout_s = timeout_s


## The guest's answer frame to the owner request `req`, through the host's command receive door.
func answer_owner(req: int, faces: Array) -> void:
	main._on_network_command("roll_result", {"req": req, "faces": faces}, 2)


## Pin the table to the pending rules epoch `n` and record the pin (R-FT1); teardown restores the shipped epoch.
func need_epoch(n: int) -> void:
	AiActRecorder.rules_epoch = n
	if not pins.has(n):
		pins.append(n)


## Undo everything boot did: the tap, the core sessions, the env switches, the epoch, the transport, stray nodes.
func teardown() -> void:
	if main == null:
		return
	if main.battle_log.entry_added.is_connected(_tap):
		main.battle_log.entry_added.disconnect(_tap)
	CoreActivation.reset_all(main)
	CoreActivation._env = -1
	CoreActivation._hotseat_env = -1
	AiActRecorder.rules_epoch = _epoch_before
	SoloController.mission_scoring = "end"
	SoloController.mission_markers = []
	SoloController.mission_vp = [0, 0]
	SoloController.mission_vp_memo = {}
	SoloController.mission_vp_flavour = {}
	if net != null:
		main.network_manager = _real_net
		main.radial_menu_controller.network_manager = _real_net
		net.free()
		net = null
	E2EBoot.free_stray_root_nodes(_tree, _root_before)
	main = null
	runner = null
