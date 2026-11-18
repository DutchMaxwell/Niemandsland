class_name CoreResolve
## One shared helper for the resolve tests that stop calling the GDScript search: one planner action through
## NmlCore. The game header goes in FIRST — without it the core runs at rules_epoch 0 and silently pins the
## legacy epoch — then the seams, the capture, the resolve, and the answer back as a live state. Same order as
## CoreActivation.capture and SoloController._core_plan; precedent test/one_core/round_binding_test.gd.
## `seams` = {"spacing": bool, "cast": bool}; an absent key reads the table's own switch.
## A core WITH a header takes its seams from the header's own knobs (resolve asks for the
## header epoch's seams), so the dict is stamped there; set_seams alone only reaches a
## headerless core.

static func resolve(state: Dictionary, action: Dictionary, seams := {}) -> Dictionary:
	var core: Object = ClassDB.instantiate("NmlCore")
	if core == null:
		return {}
	var head := AiActRecorder._header_line(state, state.get("terrain_at", Callable()))
	if seams.has("spacing"):
		head["knobs"]["seam_spacing"] = bool(seams["spacing"])
	if seams.has("cast"):
		head["knobs"]["seam_cast"] = bool(seams["cast"])
	if not bool(core.set_game_header(head)):
		return {}
	core.set_seams(bool(seams.get("spacing", BattleSim.spacing_enabled())),
		bool(seams.get("cast", BattleSim.cast_phase_enabled())))
	var h := int(core.capture_plain(BattleSim.state_to_plain(state)))
	var out := int(core.resolve(h, action))
	var plain: Dictionary = core.plain_of(out)
	core.release(h)
	core.release(out)
	var army: OPRArmyManager = OPRArmyManager.new()
	for key in state["units"]:
		var gu: Variant = (state["units"][key] as Dictionary).get("unit")
		if gu is GameUnit:
			army.game_units[str(key)] = gu
	var next := BattleSim.state_from_plain(plain, army)
	army.free()
	return next
