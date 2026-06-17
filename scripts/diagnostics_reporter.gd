class_name DiagnosticsReporter
extends RefCounted
## Builds an ANONYMISED diagnostics bundle players can send us to triage bugs. Gathers the
## version, platform, GPU/renderer and the recent log (Godot file logging writes it to
## user://logs/niemandsland.log), then scrubs anything identifying — the OS username baked
## into paths, player names, the room code — before writing a plain-text file the player can
## review and attach. NOT a crash reporter and NOT auto-sent: the user explicitly exports it.
## The scrub is the privacy boundary, so its pure core (scrub_text) is unit-tested.

const LOG_PATH := "user://logs/niemandsland.log"
const LOG_DIR := "user://logs"
## The engine ROTATES niemandsland.log on every launch, so "the last game" is usually in a
## timestamped file from a prior run, not the current (often fresh) log. Include the most recent
## few log files so the report actually carries the session the player is reporting about.
const RECENT_LOG_FILES := 3        # current + the 2 prior sessions
const PER_LOG_TAIL_BYTES := 80000  # keep the END of each (where errors/crashes land)
const USER_PLACEHOLDER := "<user>"
const PLAYER_PLACEHOLDER := "<player>"
const ROOM_PLACEHOLDER := "<room>"
## Room-code alphabet (relay: no ambiguous 0/O/1/I/L). Used to discover codes mentioned in the log.
const ROOM_CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
## Don't scrub very short secrets (a 1-char name would blank half the text).
const MIN_SECRET_LEN := 2

# === Public: pure scrub (unit-tested) ===

## Replace each [secret, placeholder] pair in `text`. Longest secrets first, so a name that
## contains a shorter one isn't half-replaced; secrets shorter than MIN_SECRET_LEN are skipped.
static func scrub_text(text: String, replacements: Array) -> String:
	var sorted := replacements.duplicate()
	sorted.sort_custom(func(a, b): return str(a[0]).length() > str(b[0]).length())
	var out := text
	for pair in sorted:
		var secret := str(pair[0])
		if secret.length() >= MIN_SECRET_LEN:
			out = out.replace(secret, str(pair[1]))
	return out


## The [secret, placeholder] pairs to scrub: the OS username (baked into user:// paths and
## some absolute paths), every known player name, and the room code.
static func gather_replacements(player_names: Array, room_code: String) -> Array:
	var pairs: Array = []
	var user := OS.get_environment("USER")
	if user.is_empty():
		user = OS.get_environment("USERNAME")  # Windows
	if not user.is_empty():
		pairs.append([user, USER_PLACEHOLDER])
	for n in player_names:
		var s := str(n).strip_edges()
		if not s.is_empty():
			pairs.append([s, PLAYER_PLACEHOLDER])
	if not room_code.strip_edges().is_empty():
		pairs.append([room_code.strip_edges(), ROOM_PLACEHOLDER])
	return pairs


## Discover room codes mentioned in `text` so they can be scrubbed without a live session naming
## them. Matches the relay's log contexts — "room <CODE>", "room=<CODE>", "ROOM CREATED: <CODE>",
## "Room code <CODE>" — with an uppercase-only code class (lowercase words like "room not found"
## can't match). Returns both the dashed ("V2K-T9S") and undashed ("V2KT9S") forms.
static func _room_codes_in(text: String) -> Array:
	var found := {}
	var re := RegEx.new()
	if re.compile("(?i:room(?:\\s+(?:code|created))?[\\s:=]+)([%s][%s\\-]{4,6})" % [ROOM_CODE_CHARS, ROOM_CODE_CHARS]) != OK:
		return []
	for m in re.search_all(text):
		var code: String = m.get_string(1)
		found[code] = true
		found[code.replace("-", "")] = true
	return found.keys()

# === Public: report building / export ===

## The full anonymised report text: a system header + the scrubbed recent log. `extra` lets a
## caller add a couple of lines (e.g. MP error count). Never includes the identity token.
static func build_report(player_names: Array = [], room_code: String = "", extra: Dictionary = {}) -> String:
	var lines: Array[String] = []
	lines.append("Niemandsland diagnostics (anonymised)")
	lines.append("version: %s" % ProjectSettings.get_setting("application/config/version", "unknown"))
	lines.append("os: %s" % OS.get_name())
	lines.append("renderer: %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")))
	lines.append("gpu: %s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
	lines.append("cpu: %s x%d" % [OS.get_processor_name(), OS.get_processor_count()])
	for k in extra:
		lines.append("%s: %s" % [str(k), str(extra[k])])
	lines.append("")
	var log_text := _read_log()
	lines.append("=== recent log ===")
	lines.append(log_text)
	var raw := "\n".join(lines)
	# Player names never reach the log (it only ever prints "Player N" / peer ids), but ROOM CODES do
	# — and the exporter (the start menu) has no live session to name them. Discover them from the
	# log itself so they're scrubbed too, keeping the report's "anonymised" promise honest.
	var replacements := gather_replacements(player_names, room_code)
	for code in _room_codes_in(log_text):
		replacements.append([code, ROOM_PLACEHOLDER])
	return scrub_text(raw, replacements)


## Write the report to the user's Desktop and open the folder so it's trivial to attach.
## Returns the written file path (empty on failure). `stamp` makes the filename unique and
## must be passed in (Time.get_datetime_string is unavailable at class scope under resume).
static func export_report(stamp: String, player_names: Array = [], room_code: String = "", extra: Dictionary = {}) -> String:
	var report := build_report(player_names, room_code, extra)
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if dir.is_empty():
		dir = OS.get_user_data_dir()
	var path := dir.path_join("niemandsland-diagnostics-%s.txt" % stamp)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[Diagnostics] Could not write report to %s" % path)
		return ""
	f.store_string(report)
	f.close()
	OS.shell_open(dir)  # open the folder containing the report
	return path

# === Private ===

## Read the recent log: the newest RECENT_LOG_FILES `niemandsland*.log` files (the engine rotates
## per launch), each tailed to its last PER_LOG_TAIL_BYTES, in chronological order — so a report
## taken from the menu after restarting still carries the previous session's game.
static func _read_log() -> String:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return _read_one_tail(LOG_PATH)
	var files: Array = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("niemandsland") and name.ends_with(".log"):
			files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	if files.is_empty():
		return "(no log files in %s)" % LOG_DIR
	# Newest first by modification time, then keep the most recent few.
	files.sort_custom(func(a, b): return FileAccess.get_modified_time(LOG_DIR.path_join(a)) > FileAccess.get_modified_time(LOG_DIR.path_join(b)))
	var selected: Array = files.slice(0, RECENT_LOG_FILES)
	selected.reverse()  # present oldest -> newest so it reads chronologically
	var chunks: Array[String] = []
	for fname in selected:
		chunks.append("----- %s -----\n%s" % [fname, _read_one_tail(LOG_DIR.path_join(fname))])
	return "\n\n".join(chunks)


## Read one log file, keeping only its last PER_LOG_TAIL_BYTES (the tail, where the failure is).
static func _read_one_tail(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "(missing %s)" % path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "(could not open %s)" % path
	var text := f.get_as_text()
	f.close()
	if text.length() > PER_LOG_TAIL_BYTES:
		text = "…(earlier lines truncated)…\n" + text.substr(text.length() - PER_LOG_TAIL_BYTES)
	return text
