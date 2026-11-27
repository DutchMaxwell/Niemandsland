class_name TableOpponentLayer
extends CanvasLayer
## The table's "Opponent…" (game menu): the setup's step-04 page in table mode over the table - the same page, the
## same model. Its button (or Enter) does what the chosen card says: NACHTMAHR's list into its seat (the table's own
## loader), the army import on Player 2, or the Host dialog. Esc or Back closes it and changes nothing. Bringing
## NACHTMAHR into a seat that already holds an army replaces it, as any import into that seat does.

## Tests hand in their own list source here (no CDN); null = the table's.
static var lists_override: AiLists = null

var page: SetupOpponentStep
var opponent := SetupOpponent.new()
var _main: Node


static func open(main: Node) -> TableOpponentLayer:
	var layer := TableOpponentLayer.new()
	layer.name = "TableOpponentLayer"
	layer.layer = 90
	layer._main = main
	main.add_child(layer)
	layer._build()
	return layer


func _build() -> void:
	var fill := ColorRect.new()
	fill.color = HouseStyle.SHEET_FILL
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.theme = HouseStyle.menu_theme()
	add_child(fill)
	var system: String = _main._table_system()
	var feet: Vector2 = _main.map_layout_editor.table_size_feet
	var biome := str(_main.table.biome)
	opponent.set_system(system)
	page = SetupOpponentStep.new()
	page.table_mode = true
	for seat: int in [1, 2]:
		if _main.network_manager != null and _main.network_manager.slot_has_human_peer(seat):
			page.human_seats.append(seat)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.add_child(page)
	page.setup(opponent, [GameSystem.label(system), TableSizeDialog.BIOMES.get(biome, [biome])[0],
		"%d × %d in" % [roundi(feet.x * 12), roundi(feet.y * 12)]])
	page.create_requested.connect(_act)
	var back := HouseStyle.button("Back to the table", HouseStyle.BUTTON, 36)
	back.name = "BackToTable"
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.position += Vector2(-220, 36)
	back.pressed.connect(queue_free)
	fill.add_child(back)
	opponent.loading = true
	var lists: AiLists = lists_override if lists_override != null else _main._ai_lists
	opponent.set_manifest(await lists.manifest())


func _act() -> void:
	match opponent.who:
		"solo":
			var choice := opponent.choice()
			if not _main._engine_refused_without_core():   # no NACHTMAHR without the rules core (its own line)
				_main._load_ai_opponent_list(str(choice.file), int(choice.slot))
		"local":
			_main.opr_import_dialog.set_player(2)
			_main.opr_import_dialog.show()
		"online":
			_main._on_host_pressed()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:   # as the setup: Enter is the gold button
		get_viewport().set_input_as_handled()
		_act()
