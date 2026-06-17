class_name DiagnosticsReporter
extends RefCounted
## Builds an ANONYMISED diagnostics bundle players can send us to triage bugs. Gathers the
## version, platform, GPU/renderer and the recent log (Godot file logging writes it to
## user://logs/niemandsland.log), then scrubs anything identifying — the OS username baked
## into paths, player names, the room code — before writing a plain-text file the player can
## review and attach. NOT a crash reporter and NOT auto-sent: the user explicitly exports it.
## The scrub is the privacy boundary, so its pure core (scrub_text) is unit-tested.

const LOG_PATH := "user://logs/niemandsland.log"
const USER_PLACEHOLDER := "<user>"
const PLAYER_PLACEHOLDER := "<player>"
const ROOM_PLACEHOLDER := "<room>"
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
	lines.append("=== recent log ===")
	lines.append(_read_log())
	var raw := "\n".join(lines)
	return scrub_text(raw, gather_replacements(player_names, room_code))


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

static func _read_log() -> String:
	if not FileAccess.file_exists(LOG_PATH):
		return "(no log file yet at %s)" % LOG_PATH
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		return "(could not open log)"
	var text := f.get_as_text()
	f.close()
	return text
