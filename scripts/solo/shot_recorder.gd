class_name AiShotRecorder
extends RefCounted
## NML-1073 M5 D6a-B6: env NML_SHOT_DUMP=<dir> appends every SHOT the table resolves in an
## AI volley to <dir>/shots.jsonl — the per-shot counterpart to AiDiceRecorder's per-roll
## dump (scripts/solo/dice_recorder.gd): a sharded gate for per-model sighting (D6a) and
## per-copy bearer scaling needs the table's own sighted/bearers/reach facts, not an inferred
## residue (PLAN_fast_rules_core.md "D6a DESIGN DRAFT" §3/§5 B6). Same shape as AiDiceRecorder:
## a static FileAccess stream opened once and kept open, one JSON line per call via
## JSON.stringify, an env line cap (NML_SHOT_DUMP_MAX), flush per line, close() at game end.
## Unset (default) never touches disk: main.gd's tap calls record() unconditionally, but
## record() returns immediately on the very first (cheap, cached) env check — byte-identical
## game either way.


static var _stream: FileAccess = null
static var _checked := false
static var _max := 200000
static var _count := 0


static func _dump_stream() -> FileAccess:
	if not _checked:
		_checked = true
		var dir := OS.get_environment("NML_SHOT_DUMP")
		if dir != "" and DirAccess.dir_exists_absolute(dir):
			_stream = FileAccess.open(dir.path_join("shots.jsonl"), FileAccess.WRITE)
			var cap := OS.get_environment("NML_SHOT_DUMP_MAX")
			if cap != "":
				_max = maxi(int(cap), 0)
	return _stream


## One line per shot: `rec` already carries act/round/player/shooter/member/weapon/target/
## alive/sighted/bearers/max_models/attacks/reach_in/indirect (main.gd's `_solo_resolve_ai_volley`
## tap builds it, right after the shot's scaled attack count is final and before the hit roll).
## No-op when the env seam is off or the line cap is hit.
static func record(rec: Dictionary) -> void:
	var f := _dump_stream()
	if f == null or _count >= _max:
		return
	f.store_line(JSON.stringify(rec, "", true, true))
	f.flush()   # a same-process reader must see the line without a close()
	_count += 1


## NML-1073 M5 D6a-B6: closes the stream at a GAME's end (tools/arena_match.gd, beside
## AiDiceRecorder.close()) — flushed and closed where the writer stands. Resets every cached
## static so a later record() reopens a fresh file cleanly.
static func close() -> void:
	if _stream != null:
		_stream.flush()
		_stream.close()
	_stream = null
	_checked = false
	_count = 0
