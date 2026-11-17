class_name CoreShadow
extends RefCounted
## C-3 (shadow run): env NML_CORE_SHADOW=1 (test soaks only, default OFF). The core keeps a board for EVERY OPR AI
## activation, not only for a plain one, and an in-memory tap holds the table's tray rolls of that activation, so the
## same volley can be replayed through the core and compared (C-4). Counting only: the table resolves as always, the
## capture draws no die and writes no line. Flag off: no capture, no tap entry - byte-identical play.

static var _env := -1
## The table's tray rolls since this activation's shadow capture, in order: {kind, count, target, faces, owner, leg}.
static var tap: Array = []
## True while a shadow board is open (the tray's tap appends only then).
static var tapping := false


## The flag, read once: ON only for "1" / "on".
static func enabled() -> bool:
	if _env < 0:
		var raw := OS.get_environment("NML_CORE_SHADOW").to_lower()
		_env = 1 if (raw == "1" or raw == "on") else 0
	return _env == 1


## The shadow board of the AI activation about to start (`peek`, before its move): a core handle, 0 with the flag off,
## no core at this table or a non-OPR unit. Opens the tap on a handle, empties it either way.
static func capture(main, peek: GameUnit) -> int:
	tap.clear()
	tapping = false
	if not enabled() or peek == null or not CoreActivation.applies(main) or not peek.source_data is OPRApiClient.OPRUnit:
		return 0
	var h := CoreActivation.capture(main)
	tapping = h != 0
	return h


## One table tray roll, kept while a shadow board is open (main.gd's `_solo_tray_roll` calls it with `faces` known).
static func note_roll(kind: String, count: int, target: int, faces: Array, owner: String, leg: String) -> void:
	if tapping:
		tap.append({"kind": kind, "count": count, "target": target, "faces": faces.duplicate(), "owner": owner, "leg": leg})


## Closes the activation's shadow board (every exit of the AI body, and a game reset): the handle is released, the tap
## emptied.
static func release(main) -> void:
	if int(main._solo_core_shadow_h) != 0 and is_instance_valid(main.solo_controller):
		var core: Object = main.solo_controller._core_node_ready()
		if core != null:
			core.release(int(main._solo_core_shadow_h))
	main._solo_core_shadow_h = 0
	tap.clear()
	tapping = false
