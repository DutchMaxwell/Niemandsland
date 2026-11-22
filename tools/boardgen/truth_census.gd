extends SceneTree
## Ruin-town TRUTH CENSUS (plan PLAN_RUINTOWN_DRESSING, step 1): the digests that pin "the dressing changes no gameplay".
##   godot --headless --path . -s res://tools/boardgen/truth_census.gd -- [seeds=41,25] [theme=ruintown]
## Prints per seed `TRUTH <seed> layout=<sha256> solids=<n> colliders=<sha256>` and ends with `TRUTH_DONE`.
## layout = the core's layout dictionary as JSON; colliders = the sorted solid boxes of BoardgenGreybox.plan (one per collider).
## The static helpers are what test/boardgen_truth_test.gd pins; a generator change re-pins them and states old -> new.

const THEME := "ruintown"


func _initialize() -> void:
	var seeds: Array = [41, 25]
	var theme := THEME
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds = Array(arg.substr(6).split(",", false)).map(func(s: String) -> int: return int(s))
		elif arg.begins_with("theme="):
			theme = arg.substr(6)
	for board_seed: int in seeds:
		var layout := layout_of(board_seed, theme)
		print("TRUTH %d layout=%s solids=%d colliders=%s" % [board_seed, layout_digest(layout), solid_boxes(layout).size(), collider_digest(layout)])
	print("TRUTH_DONE")
	quit()


## The core's layout of a seed (`{}` when this NmlCore has no themed boardgen binding).
static func layout_of(board_seed: int, theme := THEME) -> Dictionary:
	var core: Object = ClassDB.instantiate("NmlCore") if ClassDB.class_exists("NmlCore") else null
	return core.boardgen_layout_themed(board_seed, theme) if core != null and core.has_method("boardgen_layout_themed") else {}


static func layout_digest(layout: Dictionary) -> String:
	return JSON.stringify(layout).sha256_text()


## The boxes of the plan that carry a collider (`solid`), in plan order.
static func solid_boxes(layout: Dictionary) -> Array[Dictionary]:
	return BoardgenGreybox.plan(layout).filter(func(b: Dictionary) -> bool: return b["solid"])


static func collider_digest(layout: Dictionary) -> String:
	var rows: Array[String] = []
	for b: Dictionary in solid_boxes(layout):
		rows.append(var_to_str(b["lo"]) + "|" + var_to_str(b["hi"]))
	rows.sort()
	return "\n".join(rows).sha256_text()
