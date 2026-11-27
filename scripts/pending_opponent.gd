class_name PendingOpponent
## Who the table setup put at the table (step 04, "Who is at the table?"), carried to the table beside
## `niemandsland/pending_table_setup`: {who, file, slot, label}, who = "solo" | "local" | "online". The reveal gate
## applies it on a new table (NACHTMAHR's list is loaded into its seat); a load and a join clear it.

const KEY := "niemandsland/pending_table_opponent"

## The last applied choice, for the arrival card: "local" when nothing was chosen.
static var who := "local"
static var label := ""


static func store(choice: Dictionary) -> void:
	ProjectSettings.set_setting(KEY, choice)


## Clears the setting and remembers who / label. For "solo" with a named list it starts `main`'s list loader
## without waiting for it (the table shows first, the list arrives with its toast). True when the load started;
## without the core nothing is loaded and the core's own line is logged.
static func apply(main: Node) -> bool:
	var choice: Variant = ProjectSettings.get_setting(KEY, null)
	ProjectSettings.set_setting(KEY, null)
	var c: Dictionary = choice if choice is Dictionary else {}
	who = str(c.get("who", "local"))
	label = str(c.get("label", ""))
	var file := str(c.get("file", ""))
	if who != "solo" or file.is_empty() or main._engine_refused_without_core():
		return false
	main._load_ai_opponent_list(file, int(c.get("slot", 2)))
	return true
