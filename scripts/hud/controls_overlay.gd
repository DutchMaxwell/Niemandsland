class_name ControlsOverlay
extends RefCounted
## "? Controls" (house style, maintainer 23.09.): the key list that used to sit on the table as an
## always-on wall, now a sheet you open when you need it. It READS the list from UI/HUD/InfoLabel —
## the one source; its first line carries the version — so nothing of the list can get lost or drift.
## Every "- KEYS: WHAT" line becomes a row of key caps and its text, sorted into the mockup's groups;
## a line no group claims still shows, under "More". Esc, the × or a click beside the sheet closes it.

## Group -> the KEYS parts it claims, in the order the rows appear.
const GROUPS := [
	["Camera", ["WASD", "Q/E", "Scroll"]],
	["Selection", ["Left Click", "Alt + Click", "Double Click", "Right Click"]],
	["Unit", ["R (hold)", "Shift+R", "1-9", "B", "Shift+A", "Ctrl+C/V/D", "L", "Del", "Ctrl+Z / Ctrl+Y"]],
	["Measure & view", ["Shift + Click", "P", "K / Shift+K", "G / Shift+G", "F / Shift+F", "M / Shift+M", "T / Shift+T"]],
	["Game", ["F7", "F8"]],
]
const LEFT_COLUMN := ["Camera", "Selection", "Game", "More"]
const SHEET_W := 820
const KEYS_W := 170
const TEXT_W := 190   # the text beside the caps: half the sheet minus the caps column

var root: Control = null
var _body: VBoxContainer = null
var _source: Label = null


## Builds the (hidden) overlay under `parent`; `source` is the key-list label it reads on every open.
func build(parent: Node, source: Label) -> void:
	_source = source
	var parts := HouseStyle.overlay_sheet("Controls", SHEET_W)
	root = parts["root"]
	root.name = "ControlsOverlay"
	root.visible = false
	_body = parts["body"]
	(parts["close"] as Button).pressed.connect(close)
	(root.get_node("Scrim") as ColorRect).gui_input.connect(_on_scrim_input)
	parent.add_child(root)


func is_open() -> bool:
	return root != null and root.visible


func open() -> void:
	_rebuild()
	root.visible = true


func close() -> void:
	root.visible = false


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()


## Esc closes the sheet (the rail forwards unhandled keys while it is open).
func handle_key(event: InputEventKey) -> bool:
	if is_open() and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		return true
	return false


## The list's rows as [{"keys": "G / Shift+G", "text": "Range Ring / clear"}], in source order —
## everything after the version line and the "Controls:" caption.
static func parse(text: String) -> Array:
	var rows: Array = []
	for line: String in text.split("\n"):
		var s := line.strip_edges()
		if not s.begins_with("- "):
			continue
		var cut := s.find(": ")
		if cut < 0:
			continue
		rows.append({"keys": s.substr(2, cut - 2).strip_edges(), "text": s.substr(cut + 2).strip_edges()})
	return rows


## Which group shows a row ("More" if none claims its keys).
static func group_of(keys: String) -> String:
	for g: Array in GROUPS:
		if keys in (g[1] as Array):
			return g[0]
	return "More"


func _rebuild() -> void:
	for c: Node in _body.get_children():
		if c.name != "Header":
			_body.remove_child(c)
			c.queue_free()
	var first := _source.text.split("\n")[0].strip_edges()
	var version := HouseStyle.label(first, HouseStyle.CAPTION)
	version.name = "Version"
	_body.add_child(version)
	var by_group := {}
	for row: Dictionary in parse(_source.text):
		var g := group_of(row["keys"])
		if not by_group.has(g):
			by_group[g] = []
		by_group[g].append(row)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", HouseStyle.PAD_SHEET + HouseStyle.GAP_SECTION)
	var left := _column()
	var right := _column()
	cols.add_child(left)
	cols.add_child(right)
	for g: String in ["Camera", "Selection", "Unit", "Measure & view", "Game", "More"]:
		if by_group.has(g):
			_add_group(left if g in LEFT_COLUMN else right, g, by_group[g])
	_body.add_child(cols)


func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override(&"separation", HouseStyle.GAP_CONTROL + 2)
	return v


func _add_group(col: VBoxContainer, title: String, rows: Array) -> void:
	var head := HouseStyle.label(title.to_upper(), HouseStyle.EYEBROW)
	if col.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, HouseStyle.GAP_ROW)
		col.add_child(gap)
	col.add_child(head)
	for row: Dictionary in rows:
		col.add_child(_row(row["keys"], row["text"]))


## One binding: its keys as caps ("G / Shift+G" -> [G] / [Shift][G]), then what it does.
func _row(keys: String, text: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.set_meta(&"keys", keys)
	r.add_theme_constant_override(&"separation", HouseStyle.GAP_ROW)
	var caps := HBoxContainer.new()
	caps.custom_minimum_size = Vector2(KEYS_W, 0)
	caps.add_theme_constant_override(&"separation", 3)
	var alternatives := keys.split(" / ")
	for i: int in alternatives.size():
		if i > 0:
			caps.add_child(HouseStyle.label("/", HouseStyle.CAPTION))
		for k: String in alternatives[i].split("+"):
			if k.strip_edges() != "":
				caps.add_child(HouseStyle.key_cap(k.strip_edges()))
	r.add_child(caps)
	var what := HouseStyle.label(text, HouseStyle.BODY)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label is first measured at width 0 (one word per line): without a floor the sheet
	# came out ~4,800 px tall and its × sat far below the screen.
	what.custom_minimum_size = Vector2(TEXT_W, 0)
	r.add_child(what)
	return r
