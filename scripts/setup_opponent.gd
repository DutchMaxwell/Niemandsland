class_name SetupOpponent
extends RefCounted
## The model behind step 04 of the table setup, "Who is at the table?": the card (solo, local, online) and, for
## Solo, NACHTMAHR's faction, points bracket and seat, read from the AI-list manifest of the game system picked
## in step 01 (exactly that system). On Create table the choice travels to the table (PendingOpponent).

signal changed

const LOCAL_LABEL := "Two players, one screen"
const ONLINE_LABEL := "Online room"
const LOADING_LINE := "Loading NACHTMAHR's lists ..."
const NO_MANIFEST_LINE := "NACHTMAHR's lists need a connection the first time."
const NO_LISTS_LINE := "No NACHTMAHR lists for %s yet."
const MENU_CFG := "user://menu.cfg"
const WHO_IDS := ["solo", "local", "online"]

var who := "solo"           # "solo" | "local" | "online"
var manifest: Dictionary = {}
var loading := false
var faction := ""           # a manifest key
var bracket := 0            # an index into the faction's lists
var seat := 2               # the player NACHTMAHR plays: 2 (Red) or 1 (Blue)
var _preferred := "solo"    # the card asked for; Solo falls to "local" while it is off
var _system := GameSystem.DEFAULT_ID
var _wanted := {}           # a remembered faction / points pick, applied when the manifest offers it


## The pick a fresh setup starts on: the remembered one (the menu config), else Solo, NACHTMAHR as player 2. Same
## file and pattern as GameSystem.default_pick; a value that is no card or seat reads as the default.
static func default_pick(cfg_path: String = MENU_CFG) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)   # a missing file reads as the defaults
	var who := str(cfg.get_value("menu", "opponent_who", "solo"))
	return {"who": who if WHO_IDS.has(who) else "solo", "faction": str(cfg.get_value("menu", "opponent_faction", "")),
		"points": int(str(cfg.get_value("menu", "opponent_points", 0))),
		"seat": 1 if str(cfg.get_value("menu", "opponent_seat", 2)) == "1" else 2}


## Remembers the card, faction, points and seat for the next table (keeps the other menu keys).
static func remember_pick(pick: Dictionary, cfg_path: String = MENU_CFG) -> void:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	for key: String in ["who", "faction", "points", "seat"]:
		cfg.set_value("menu", "opponent_" + key, pick.get(key, ""))
	cfg.save(cfg_path)


## The pick to remember: {who, faction, points, seat}.
func pick() -> Dictionary:
	var points: Array = brackets()
	return {"who": who, "faction": faction, "points": int(points[bracket]) if bracket < points.size() else 0,
		"seat": seat}


## Starts on a remembered pick; a faction or bracket the manifest does not offer falls back silently.
func apply_pick(remembered: Dictionary) -> void:
	_wanted = remembered
	seat = int(remembered.get("seat", 2))
	faction = ""
	choose_who(str(remembered.get("who", "solo")))


func set_manifest(m: Dictionary) -> void:
	manifest = m
	loading = false
	_settle()


func set_system(id: String) -> void:
	_system = id
	_settle()


## [key, name] of the factions the system offers, sorted by key.
func factions() -> Array:
	var keys: Array = GameSystem.manifest_keys(manifest, _system)
	keys.sort()
	return keys.map(func(k: String) -> Array: return [k, str((manifest[k] as Dictionary).get("name", k))])


## The points of the chosen faction's lists, in manifest order.
func brackets() -> Array:
	return _lists().map(func(l: Dictionary) -> int: return int(l.get("points", 0)))


func choose_who(id: String) -> void:
	_preferred = id
	_settle()


func choose_faction(key: String) -> void:
	faction = key
	bracket = _largest()
	changed.emit()


func choose_bracket(index: int) -> void:
	bracket = clampi(index, 0, maxi(0, _lists().size() - 1))
	changed.emit()


func choose_seat(player: int) -> void:
	seat = 1 if player == 1 else 2
	changed.emit()


func solo_available() -> bool:
	return not loading and not factions().is_empty()


## The muted line shown in the Solo card's place while Solo is off; "" when it is on.
func off_line() -> String:
	if loading:
		return LOADING_LINE
	if manifest.is_empty():
		return NO_MANIFEST_LINE
	if factions().is_empty():
		return NO_LISTS_LINE % GameSystem.label(_system)
	return ""


func label() -> String:
	match who:
		"solo":
			var points: Array = brackets()
			return "NACHTMAHR · %s · %d" % [_faction_name(), int(points[bracket]) if bracket < points.size() else 0]
		"online":
			return ONLINE_LABEL
	return LOCAL_LABEL


## {who, file, slot, label}: what the table needs (file and slot only for Solo).
func choice() -> Dictionary:
	var out := {"who": who, "label": label()}
	if who == "solo":
		out["file"] = str((_lists()[bracket] as Dictionary).get("file", ""))
		out["slot"] = seat
	return out


func commit() -> void:
	PendingOpponent.store(choice())


## Keeps the faction while the system still offers it (else the first), and falls from Solo to two players
## while Solo is off; back to Solo once its lists are there, unless the player picked another card.
func _settle() -> void:
	var keys: Array = factions().map(func(f: Array) -> String: return f[0])
	if not keys.has(faction):
		var wanted := str(_wanted.get("faction", ""))
		faction = wanted if keys.has(wanted) else str(keys[0]) if not keys.is_empty() else ""
		bracket = _largest()
		if faction == wanted and brackets().has(int(_wanted.get("points", 0))):
			bracket = brackets().find(int(_wanted.get("points", 0)))
	who = "local" if _preferred == "solo" and not solo_available() else _preferred
	changed.emit()


func _lists() -> Array:
	return (manifest.get(faction, {}) as Dictionary).get("lists", [])


func _largest() -> int:
	var points := brackets()
	var best := 0
	for i in points.size():
		if int(points[i]) > int(points[best]):
			best = i
	return best


func _faction_name() -> String:
	return str((manifest.get(faction, {}) as Dictionary).get("name", faction))
