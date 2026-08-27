class_name AiDiceRecorder
extends RefCounted
## NML-1073 M5 D1-B1: env NML_DICE_DUMP=<dir> appends every TRAY ROLL to
## <dir>/dice.jsonl — the table-side half of the D1 (real dice) gate the fast
## trainer will later replay against. Same shape as AiActRecorder
## (scripts/solo/act_recorder.gd): a static FileAccess stream opened once and
## kept open, one JSON line per call via JSON.stringify, an env line cap
## (NML_DICE_DUMP_MAX), flush per line, close() at game end. Unset (default)
## never touches disk: main.gd's tap calls record() unconditionally, but
## record() returns immediately on the very first (cheap, cached) env check —
## byte-identical game either way.


static var _stream: FileAccess = null
static var _checked := false
static var _max := 200000
static var _count := 0


static func _dump_stream() -> FileAccess:
	if not _checked:
		_checked = true
		var dir := OS.get_environment("NML_DICE_DUMP")
		if dir != "" and DirAccess.dir_exists_absolute(dir):
			_stream = FileAccess.open(dir.path_join("dice.jsonl"), FileAccess.WRITE)
			var cap := OS.get_environment("NML_DICE_DUMP_MAX")
			if cap != "":
				_max = maxi(int(cap), 0)
	return _stream


## One line per tray roll: `rec` already carries act/seq/round/player/roll_kind/owner/target/
## count/faces (main.gd's `_solo_tray_roll` tap builds it, right next to the "dice" record_decision
## call). No-op when the env seam is off or the line cap is hit.
static func record(rec: Dictionary) -> void:
	var f := _dump_stream()
	if f == null or _count >= _max:
		return
	f.store_line(JSON.stringify(rec, "", true, true))
	f.flush()   # a same-process reader must see the line without a close()
	_count += 1


## NML-1073 M5 D1-B1: closes the stream at a GAME's end (tools/arena_match.gd, beside
## AiActRecorder.close()) — flushed and closed where the writer stands. Resets every cached
## static so a later record() reopens a fresh file cleanly.
static func close() -> void:
	if _stream != null:
		_stream.flush()
		_stream.close()
	_stream = null
	_checked = false
	_count = 0
