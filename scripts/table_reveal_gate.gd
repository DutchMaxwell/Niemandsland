class_name TableRevealGate
extends Node
## The hand-over from the menu to the table without the intro: watches the table's own signals until the table
## can be shown - Table, Battlemap, Terrain, Miniatures - and names the stage on the menu's loading picture.
## `revealed` fires once: when every stage is done, or after CAP_S (by_cap). A fresh table has no pieces and
## no models, so its Terrain and Miniatures are done at once; a join first waits for the host's state.

signal stage_changed(stage: String, ratio: float)
signal revealed(by_cap: bool)

const STAGES: Array[String] = ["Table", "Battlemap", "Terrain", "Miniatures"]
## Upper bound from the cold-cache capture series (the battlemap arrived ~18-20 s into Main); after it the table
## shows with its bundled surface and the battlemap swaps in when it arrives.
const CAP_S := 20.0
const WAITING_FOR_HOST := "Waiting for the host"
## A join whose host has not answered by the cap: the table opens anyway, with this one line.
const HOST_LATE := "The host has not sent the table yet. It arrives as soon as the host answers."

var done: Array[String] = []
var _table: Node = null
var _caching := false
var _revealed := false
var _main: Node = null
var _mode := ""


## Starts the gate under `main` for `mode`: "new" (a table from the setup), "load" or "join".
static func start(main: Node, mode: String) -> TableRevealGate:
	var gate := TableRevealGate.new()
	gate.name = "TableRevealGate"
	main.add_child(gate)
	gate._watch(main, mode)
	return gate


func _watch(main: Node, mode: String) -> void:
	_main = main
	_mode = mode
	for overlay: Node in get_tree().get_nodes_in_group("transition_overlay"):
		if overlay.has_method("set_stages"):
			overlay.set_stages(PackedStringArray(STAGES))
	_table = main.get("table")
	if mode != "new":  # a new table counts from its size (the direct chooser may stand open for long)
		_start_cap()
	_table.battlemap_settled.connect(
		func(biome: String, _applied: bool) -> void:
			if biome == _table.biome:
				tick("Battlemap")
	)
	var models: Object = (
		main.opr_army_manager.model_library if main.get("opr_army_manager") != null else null
	)
	if models != null:
		models.caching_started.connect(func(_total: int) -> void: _caching = true)
		models.caching_finished.connect(
			func() -> void:
				_caching = false
				if done.has("Table"):
					tick("Miniatures")
		)
	var save_manager: Node = main.get("save_manager")
	match mode:
		"load":
			PendingOpponent.store({})
			save_manager.load_completed.connect(
				func(_count: int) -> void: _arrived(), CONNECT_ONE_SHOT
			)
			save_manager.load_failed.connect(
				func(_error: String) -> void: _arrived(), CONNECT_ONE_SHOT
			)
		"join":  # the host's state is applied inside a restore; its unlock is the first moment it stands
			PendingOpponent.store({})
			save_manager.connect("_restore_unlocked", _arrived, CONNECT_ONE_SHOT)
			_show(WAITING_FOR_HOST)
		_:  # a new table: it stands once the setup's size is applied (deferred from main's _ready)
			_table.table_resized.connect(
				func(_feet: Vector2) -> void:
					_start_cap()
					if PendingLayout.has_pending():
						_lay_out()
					else:
						PendingOpponent.apply(_main)
						_arrived(),
				CONNECT_ONE_SHOT
			)


## The setup's layout (step 04), one frame after the resize has cleared the editor; then the table stands.
func _lay_out() -> void:
	await get_tree().process_frame
	PendingLayout.apply(_main)
	PendingOpponent.apply(_main)
	_arrived()


func _start_cap() -> void:
	get_tree().create_timer(CAP_S).timeout.connect(_reveal.bind(true))


## The table stands (built, loaded or synced): its pieces came with it; models are done unless they still cache.
func _arrived() -> void:
	tick("Table")
	tick("Terrain")
	if not _caching:
		tick("Miniatures")


## Marks `stage` done; the overlay names the next one. Every stage done reveals the table.
func tick(stage: String) -> void:
	if _revealed or done.has(stage):
		return
	done.append(stage)
	var next := STAGES.filter(func(s: String) -> bool: return not done.has(s))
	_show(str(next[0]) if not next.is_empty() else "")
	if next.is_empty():
		_reveal(false)


func _show(stage: String) -> void:
	var ratio := float(done.size()) / float(STAGES.size())
	stage_changed.emit(stage, ratio)
	for overlay: Node in get_tree().get_nodes_in_group("transition_overlay"):
		if overlay.has_method("set_stage"):
			overlay.set_stage(stage)
			overlay.set_progress(ratio)


func _reveal(by_cap: bool) -> void:
	if _revealed:
		return
	_revealed = true
	if by_cap and _mode == "join" and not done.has("Table") and _main.has_method("_show_toast"):
		_main._show_toast(HOST_LATE)
	revealed.emit(by_cap)
	TableArrival.start(_main, _mode)
	queue_free.call_deferred()
