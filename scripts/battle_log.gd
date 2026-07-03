class_name BattleLog
extends Node
## The game's narrative memory: ONE collector that turns central game events into compact, filterable
## one-line entries for the in-game Battle Log panel. It is fed by CENTRAL seams (the same events the MP
## command protocol flows through — unit activation, move batches, wounds, dice, round changes) via the
## on_* entry points below, NOT by call-site sprinkling. In MP both peers derive their log locally from
## the same applied commands, so no wire traffic is added.
##
## Pure core: a capped ring buffer + formatting + category filter. No allocations in _process (it has
## none). Save/load persistence, export, timestamps, per-player colour, objective events and
## click-to-select are deferred (M2).

# === Constants / enums ===
const CAP := 200                       # ring-buffer cap (oldest entries drop off)

enum Category { GENERAL, COMBAT, MOVEMENT }
enum Filter { ALL, COMBAT, MOVEMENT, AI }

# === Signals ===
signal entry_added(entry: Dictionary)  # {round:int, category:int, ai:bool, text:String, seq:int}
signal cleared()

# === State ===
var current_round: int = 1
var _entries: Array = []
var _seq: int = 0


# === Core ===

## Record one event. `ai` tags Solo-AI-originated events (so the AI filter can surface them regardless of
## their combat/movement category). Emits entry_added for the panel; drops the oldest past CAP.
func log_event(category: int, text: String, ai: bool = false) -> Dictionary:
	var entry := {"round": current_round, "category": category, "ai": ai, "text": text, "seq": _seq}
	_seq += 1
	_entries.append(entry)
	if _entries.size() > CAP:
		_entries.pop_front()
	entry_added.emit(entry)
	return entry


func entries(filter: int = Filter.ALL) -> Array:
	match filter:
		Filter.COMBAT:
			return _where(func(e: Dictionary) -> bool: return int(e["category"]) == Category.COMBAT)
		Filter.MOVEMENT:
			return _where(func(e: Dictionary) -> bool: return int(e["category"]) == Category.MOVEMENT)
		Filter.AI:
			return _where(func(e: Dictionary) -> bool: return bool(e["ai"]))
		_:
			return _entries.duplicate()


func size() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()
	cleared.emit()


## Compact one-liner with a round prefix, e.g. "R2  Skeletons advance 6\"".
static func format_entry(entry: Dictionary) -> String:
	return "R%d  %s" % [int(entry["round"]), str(entry["text"])]


func _where(pred: Callable) -> Array:
	var out: Array = []
	for e in _entries:
		if pred.call(e):
			out.append(e)
	return out


# === Event seams (wired by main.gd to the central signals; solo-ai emits the AI ones) ===

func on_game_started(text: String = "Battle started") -> void:
	log_event(Category.GENERAL, text)


func on_round_advanced(round_number: int) -> void:
	current_round = round_number
	log_event(Category.GENERAL, "— Round %d —" % round_number)


func on_unit_activated(unit_name: String, owner: String, ai: bool = false) -> void:
	log_event(Category.GENERAL, "%s activated (%s)" % [unit_name, owner], ai)


func on_unit_moved(unit_name: String, distance_inches: float, ai: bool = false) -> void:
	var verb := "advances" if ai else "moves"
	log_event(Category.MOVEMENT, "%s %s %.0f\"" % [unit_name, verb, distance_inches], ai)


func on_dice_rolled(count: int, hits: int, target: int) -> void:
	var plural := "" if hits == 1 else "s"
	log_event(Category.COMBAT, "%d dice → %d hit%s (%d+)" % [count, hits, plural, target])


func on_wounds(unit_name: String, lost: int, alive: int, total: int) -> void:
	log_event(Category.COMBAT, "%s takes %d wound%s (%d/%d)" % [unit_name, lost, ("" if lost == 1 else "s"), alive, total])


func on_unit_destroyed(unit_name: String) -> void:
	log_event(Category.COMBAT, "%s destroyed" % unit_name)


func on_unit_revived(unit_name: String) -> void:
	log_event(Category.GENERAL, "%s returns to the battle" % unit_name)


func on_unit_parked(unit_name: String) -> void:
	log_event(Category.GENERAL, "%s wiped out" % unit_name)
