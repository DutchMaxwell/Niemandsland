class_name CoreExchange
extends RefCounted
## One-core Phase 0 spike (default OFF): ONE exchange through the core's step API.
## The table rolls every die on its own tray (`_solo_tray_roll`: physical or seeded);
## the core rules on exactly the faces it is handed (core/nml-core/src/step.rs) and
## answers the next roll it needs, until it is done.

static var _env := -1


## NML_ONE_CORE_VOLLEY=1 arms the spike; anything else leaves the table resolver alone.
static func enabled() -> bool:
	if _env < 0:
		_env = 1 if OS.get_environment("NML_ONE_CORE_VOLLEY") == "1" else 0
	return _env == 1


## step_exchange -> need_roll -> the table's tray -> faces, until "done" or "error".
## Returns the core's last answer plus "faces" (one array per roll), "steps" and
## "core_us" (time spent inside the core, marshalling included).
static func drive(table: Node, core: Object, h: int, action: Dictionary) -> Dictionary:
	var faces: Array = []
	var core_us := 0
	for i in range(64):
		var t0 := Time.get_ticks_usec()
		var s: Dictionary = core.step_exchange(h, action, faces)
		core_us += Time.get_ticks_usec() - t0
		if str(s.get("step", "")) != "need_roll":
			s["faces"] = faces
			s["steps"] = i + 1
			s["core_us"] = core_us
			return s
		var rolled: Array = await table._solo_tray_roll(int(s["count"]), int(s["target"]),
			"AI (%s)" % str(s["owner"]), str(s["kind"]))
		faces.append(rolled)
	return {"step": "error", "error": "more than 64 rolls", "faces": faces}
