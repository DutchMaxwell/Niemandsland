class_name RecentArmyLists
## The army lists this player imported last (sheet 04, "Recent lists"; D5): newest first, five at most, one entry per
## link - `{link, name, system, points}`. Kept in a local file only: never synced, never in a save, never sent.

const DEFAULT := "user://recent_lists.cfg"
const MAX := 5


## The stored lists, newest first; a missing or broken file reads as none.
static func load_all(path := DEFAULT) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return []
	var lists: Variant = cfg.get_value("recent", "lists", [])
	if not lists is Array:
		return []
	return (lists as Array).filter(func(e: Variant) -> bool: return e is Dictionary and str(e.get("link", "")) != "")


## Puts `entry` on top; the same link stored before goes, the sixth list falls off.
static func remember(entry: Dictionary, path := DEFAULT) -> void:
	var link := str(entry.get("link", "")).strip_edges()
	if link.is_empty():
		return
	var lists := load_all(path).filter(func(e: Dictionary) -> bool: return str(e.link) != link)
	lists.push_front({"link": link, "name": str(entry.get("name", "")), "system": str(entry.get("system", "")),
		"points": int(entry.get("points", 0))})
	var cfg := ConfigFile.new()
	cfg.set_value("recent", "lists", lists.slice(0, MAX))
	cfg.save(path)
