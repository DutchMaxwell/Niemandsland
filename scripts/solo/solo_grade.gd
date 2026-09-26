class_name SoloGrade
extends RefCounted
## The NACHTMAHR difficulty ladder (grill 25.09.2026, NML-1018), five grades bottom-up: three tree
## presets that never reach the planner (the only road to the net), Albtraum = Erlkönig 10/3 where core
## and brain are up (else the tree ceiling), NACHTMAHR reserved. The player's choice is `solo_grade`.

const GRADES := ["daemmerung", "zwielicht", "finsternis", "albtraum", "nachtmahr"]
const DEFAULT := "albtraum"   # maintainer 25.09.: always start against the strongest shipped grade
const NAMES := {"daemmerung": "Dämmerung", "zwielicht": "Zwielicht", "finsternis": "Finsternis",
	"albtraum": "Albtraum", "nachtmahr": "NACHTMAHR"}
const CONFIG_PATH := "user://solo.cfg"
const CONFIG_SECTION := "solo"
const CONFIG_KEY := "solo_grade"
const CFG_OVERRIDE_SETTING := "niemandsland/solo_cfg_override"   # tests: their own file
const DESCRIPTIONS := {"daemmerung": "still learning; makes visible mistakes",
	"zwielicht": "plays solidly, misses some chances", "finsternis": "plays the rules hard and punishes mistakes",
	"albtraum": "Erlkönig: thinks several moves ahead", "nachtmahr": "coming"}


static func selectable(grade: String) -> bool:
	return GRADES.has(grade) and grade != "nachtmahr"


## A saved or passed grade, or the default when it is unknown or not selectable.
static func sanitize(grade: String) -> String:
	var g := grade.strip_edges().to_lower()
	return g if selectable(g) else DEFAULT


static func display_name(grade: String) -> String:
	return str(NAMES.get(grade, grade))


## The picker's one line per grade; on macOS Albtraum says honestly that Erlkönig is missing (Q6).
static func description(grade: String, macos: bool) -> String:
	return "on macOS still without Erlkönig" if macos and grade == "albtraum" else str(DESCRIPTIONS.get(grade, ""))


## Solo, or the host of a co-op room: the AI runs there, so only there is the grade picked.
static func picker_visible(multiplayer_active: bool, is_host: bool) -> bool:
	return not multiplayer_active or is_host


## Albtraum starts from "nachtmahr", the pre-ladder pin main resolves to Erlkönig or the tree ceiling.
static func base_preset(grade: String) -> String:
	var g := sanitize(grade)
	return "nachtmahr" if g == "albtraum" else g


## The preset a grade really plays, pure so "only Albtraum reaches the planner" is testable.
static func preset_for(grade: String, core_up: bool, brain_up: bool) -> String:
	var p := base_preset(grade)
	return SoloDifficulty.preset_for_nachtmahr(core_up, brain_up) if p == "nachtmahr" else p


## The start line for a resolved opponent (GameRecordCollector.opponent_brain shape); "" = no graded seat.
static func start_line(brain: Dictionary, macos: bool) -> String:
	var id := str(brain.get("id", ""))
	if str(brain.get("engine", "")) == "erlkoenig":
		return "NACHTMAHR — Albtraum (Erlkönig)"
	if id == "nachtmahr":
		return "NACHTMAHR — Albtraum (decision tree%s)" % (" — on macOS still without Erlkönig" if macos else "")
	return "NACHTMAHR — %s (decision tree)" % display_name(id) if selectable(id) else ""


## The override first; under harness mode without one, "" — a test never touches the player's file.
static func _path() -> String:
	var o := str(ProjectSettings.get_setting(CFG_OVERRIDE_SETTING, ""))
	if not o.is_empty():
		return o
	return "" if bool(ProjectSettings.get_setting("niemandsland/harness_mode", false)) else CONFIG_PATH


static func load_saved() -> String:
	var config := ConfigFile.new()
	if _path().is_empty() or config.load(_path()) != OK:
		return DEFAULT
	return sanitize(str(config.get_value(CONFIG_SECTION, CONFIG_KEY, DEFAULT)))


## Persists a selectable grade (remembered after a downshift); anything else is refused.
static func save(grade: String) -> void:
	if not selectable(grade) or _path().is_empty():
		return
	var config := ConfigFile.new()
	config.load(_path())   # keep any other keys; ignore "not found"
	config.set_value(CONFIG_SECTION, CONFIG_KEY, grade)
	config.save(_path())
