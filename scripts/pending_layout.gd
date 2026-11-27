class_name PendingLayout
## The layout the table setup chose (step 04, "Lay out the table"), carried to the table beside
## `niemandsland/pending_table_setup`: {} for the empty table, {"theme": id} for a ready-made table, {"board": record,
## "path": file} for a generated board (`GeneratedBoard.resolve`) with the editor's file of its deployment, or
## {"path": file} - a file the setup wrote with the layout editor's own save. The reveal gate applies it on a new
## table; a load and a join never do.

const KEY := "niemandsland/pending_table_layout"


static func store(choice: Dictionary) -> void:
	ProjectSettings.set_setting(KEY, choice)


static func has_pending() -> bool:
	var choice: Variant = ProjectSettings.get_setting(KEY, null)
	return choice is Dictionary and not (choice as Dictionary).is_empty()


## Lays the pending choice on `main`'s table through the paths a player's own actions take (a theme through
## main.apply_table_theme; a file through the editor's load, then its close), then clears the setting and deletes
## the file. True when something was laid out.
static func apply(main: Node) -> bool:
	var choice: Variant = ProjectSettings.get_setting(KEY, null)
	ProjectSettings.set_setting(KEY, null)
	if not choice is Dictionary:
		return false
	var board_laid := false
	if choice.has("board") and main.has_method("apply_generated_board"):   # GEN-4: a generated board, through its door
		board_laid = main.apply_generated_board(choice.board)
		if not choice.has("path"):
			return board_laid
	if choice.has("theme") and main.has_method("apply_table_theme"):
		main.apply_table_theme(str(choice.theme))
		return true
	var path := str(choice.get("path", ""))
	if path.is_empty():
		return board_laid
	if not FileAccess.file_exists(path):
		print("[Setup] The chosen layout file is gone; the table opens empty: %s" % path)
		return false
	var editor: Node = main.get("map_layout_editor")
	var laid: bool = editor != null and editor.load_layout(path)
	if laid:
		editor._on_close_pressed()
	DirAccess.remove_absolute(path)
	return laid or board_laid
