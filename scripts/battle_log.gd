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


# === Export (shareable plain text — the maintainer's field-test artefact) ===

## Format the full log as shareable plain text: a header, then EVERY entry as its round-prefixed one-liner,
## and — when the dev "AI reasoning" toggle fed us records — an AI-decision-records section beneath (the
## diagnostic gold). Pure + dependency-free: the caller pre-renders the decision lines (via
## SoloController.render_decision) and passes them in, so BattleLog stays free of any Solo import.
## Directly unit-tested (records → text).
static func export_text(all_entries: Array, decision_lines: Array = [], title: String = "Niemandsland — Battle Log") -> String:
	var lines: PackedStringArray = [title, "=".repeat(title.length()), ""]
	for e in all_entries:
		lines.append(format_entry(e as Dictionary))
	if not decision_lines.is_empty():
		lines.append("")
		lines.append("--- AI decision records ---")
		for d in decision_lines:
			lines.append(str(d))
	lines.append("")
	return "\n".join(lines)


## Write the whole log (+ optional pre-rendered AI decision lines) to user://battle_log_<timestamp>.txt and
## return the ABSOLUTE filesystem path (also printed to the console so the maintainer can find + share it).
## No external deps; returns "" on a write failure.
## The full export text (maintainer request: clipboard hand-off for live-test triage) —
## the same rendering the file export writes, without touching disk.
func export_as_text(decision_lines: Array = []) -> String:
	return export_text(_entries, decision_lines)


func export_to_file(decision_lines: Array = []) -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var vpath := "user://battle_log_%s.txt" % stamp
	var f := FileAccess.open(vpath, FileAccess.WRITE)
	if f == null:
		push_error("BattleLog export failed (%s): %s" % [vpath, error_string(FileAccess.get_open_error())])
		return ""
	f.store_string(export_text(_entries, decision_lines))
	f.close()
	var abs_path := ProjectSettings.globalize_path(vpath)
	print("[BattleLog] exported %d entries → %s" % [_entries.size(), abs_path])
	return abs_path


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


func on_dice_rolled(count: int, hits: int, target: int, player: String = "", faces: Array = [],
		kind: String = "attack") -> void:
	# WHO rolled + the FACE RESULTS, not just a count (maintainer): "You: 6 4 2 1 → 2 hits (3+)" /
	# "Alice: 5 3 1". Faces sort high→low (same convention as the dice-log icon strip). Callers without
	# faces (e.g. Solo-AI summaries) fall back to the count-only lines; no-target rolls log too.
	# `kind` (live-test Bug 16): DEFENSE rolls read "… defends: … → N block(s)" so a save can never be
	# mistaken for an attack line ("0 hits (7+)" used to be a SAVE at 7+); attacks keep the hit wording.
	var defense := kind == "defense"
	var noun := "block" if defense else "hit"
	var prefix := (player + (" defends: " if defense else ": ")) if not player.is_empty() else ""
	if not faces.is_empty():
		var sorted_faces := faces.duplicate()
		sorted_faces.sort()
		sorted_faces.reverse()
		var parts: Array[String] = []
		for f in sorted_faces:
			parts.append(str(int(f)))
		var faces_str := " ".join(parts)
		if target > 0:
			var plural := "" if hits == 1 else "s"
			log_event(Category.COMBAT, "%s%s → %d %s%s (%d+)" % [prefix, faces_str, hits, noun, plural, target])
		elif prefix.is_empty():
			log_event(Category.COMBAT, "%d dice: %s" % [count, faces_str])
		else:
			log_event(Category.COMBAT, "%s%s" % [prefix, faces_str])
		return
	if target <= 0:
		log_event(Category.COMBAT, "%s%d dice rolled" % [prefix, count])
		return
	var plural2 := "" if hits == 1 else "s"
	log_event(Category.COMBAT, "%s%d dice → %d %s%s (%d+)" % [prefix, count, hits, noun, plural2, target])


func on_wounds(unit_name: String, lost: int, alive: int, total: int) -> void:
	log_event(Category.COMBAT, "%s takes %d wound%s (%d/%d)" % [unit_name, lost, ("" if lost == 1 else "s"), alive, total])


func on_unit_destroyed(unit_name: String) -> void:
	log_event(Category.COMBAT, "%s destroyed" % unit_name)


func on_unit_revived(unit_name: String) -> void:
	log_event(Category.GENERAL, "%s returns to the battle" % unit_name)


func on_unit_parked(unit_name: String) -> void:
	log_event(Category.GENERAL, "%s wiped out" % unit_name)
