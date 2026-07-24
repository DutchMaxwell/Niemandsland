class_name AutosaveController
extends Node
## Autosave (ROADMAP "Now": the leading follow-up after 0.3.9.0) — periodic + round-start snapshots
## into the STANDARD save directory as a small rotating slot set, so the menu's CONTINUE entry and the
## load dialog pick them up with zero extra UI. Design rules:
##  - Saves rotate over `autosave_1.nml` … `autosave_<SLOTS>.nml`, always overwriting the OLDEST slot —
##    a corrupted latest autosave never costs the previous ones.
##  - In a multiplayer session only the HOST autosaves (host-authoritative state; a guest's view is a
##    replica). Offline / solo always autosaves.
##  - Never while a save/load restore is in flight (the restore lock), never on an empty table, and at
##    most once per MIN_GAP_SEC (a fast round-advance click run must not burst-write).
##  - Writes reuse SaveManager.save_game unchanged — the versioned-migration chain (#119) covers
##    autosaves exactly like manual saves.
## The timer tick and the round hook both funnel through ONE `_try_autosave` gate, so every rule above
## holds for both triggers. Pure decision/slot helpers are static for gdUnit tests.

signal autosaved(path: String)

const INTERVAL_SEC := 300.0        # periodic tick (5 min)
const MIN_GAP_SEC := 30.0          # debounce between ANY two autosaves
const SLOTS := 3
const SLOT_PREFIX := "autosave_"

var _save_manager: Node = null
var _army_manager: Node = null
var _object_manager: Node = null
var _network_manager: Node = null
var _last_autosave_msec: int = -1
var _timer: Timer = null


func setup(save_manager: Node, army_manager: Node, object_manager: Node, network_manager: Node) -> void:
	_save_manager = save_manager
	_army_manager = army_manager
	_object_manager = object_manager
	_network_manager = network_manager
	if army_manager != null and army_manager.has_signal("round_advanced"):
		army_manager.round_advanced.connect(_on_round_advanced)
	_timer = Timer.new()
	_timer.wait_time = INTERVAL_SEC
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_on_timer_tick)
	add_child(_timer)


## PURE: which slot index (1-based) to write next — the EMPTY slot first, else the OLDEST.
## `slot_times` = modified-unix per existing slot index (missing key = slot file absent).
static func pick_slot(slot_times: Dictionary, slots: int = SLOTS) -> int:
	var best_slot := 1
	var best_time := 9223372036854775807
	for i in range(1, slots + 1):
		if not slot_times.has(i):
			return i
		var t := int(slot_times[i])
		if t < best_time:
			best_time = t
			best_slot = i
	return best_slot


## PURE: the full gate — every reason NOT to autosave in one testable place.
## `in_mp_session` = a live multiplayer session exists; `is_host` only matters then.
static func should_autosave(in_mp_session: bool, is_host: bool, restore_in_flight: bool,
		has_content: bool, msec_since_last: int) -> bool:
	if restore_in_flight or not has_content:
		return false
	if in_mp_session and not is_host:
		return false
	if msec_since_last >= 0 and msec_since_last < int(MIN_GAP_SEC * 1000.0):
		return false
	return true


## The slot path the NEXT autosave writes (scans the real save dir for the slot files' ages).
static func next_slot_path(dir_path: String) -> String:
	var times: Dictionary = {}
	for i in range(1, SLOTS + 1):
		var p := dir_path.path_join("%s%d.nml" % [SLOT_PREFIX, i])
		if FileAccess.file_exists(p):
			times[i] = FileAccess.get_modified_time(p)
	return dir_path.path_join("%s%d.nml" % [SLOT_PREFIX, pick_slot(times)])


func _on_timer_tick() -> void:
	_try_autosave("periodic")


func _on_round_advanced(_round_number: int) -> void:
	_try_autosave("round")


func _try_autosave(reason: String) -> void:
	if _save_manager == null:
		return
	var since: int = -1 if _last_autosave_msec < 0 else (Time.get_ticks_msec() - _last_autosave_msec)
	if not should_autosave(_in_mp_session(), _is_host(), _restore_in_flight(), _has_content(), since):
		return
	var path := next_slot_path(SaveManager.get_default_save_dir())
	var err: Error = _save_manager.save_game(path)
	if err != OK:
		push_warning("[Autosave] save failed (%s): %s" % [reason, error_string(err)])
		return
	_last_autosave_msec = Time.get_ticks_msec()
	autosaved.emit(path)


func _in_mp_session() -> bool:
	var mp := get_tree().get_multiplayer()
	return mp != null and mp.has_multiplayer_peer() and mp.get_peers().size() > 0


func _is_host() -> bool:
	return _network_manager != null and bool(_network_manager.get("is_host"))


func _restore_in_flight() -> bool:
	return _save_manager != null and _save_manager.has_method("is_restore_in_flight") \
		and bool(_save_manager.is_restore_in_flight())


## Anything worth saving on the table: any placed selectable object (the same collection
## SaveManager._serialize_objects walks) or any imported army unit.
func _has_content() -> bool:
	if _object_manager != null:
		for child in _object_manager.get_children():
			if child is Node3D and (child as Node3D).is_in_group("selectable"):
				return true
	if _army_manager != null and _army_manager.has_method("get_all_game_units"):
		return not (_army_manager.get_all_game_units() as Array).is_empty()
	return false
