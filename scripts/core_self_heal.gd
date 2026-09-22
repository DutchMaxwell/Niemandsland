extends RefCounted
class_name CoreSelfHeal
## Option (b) for release 0925 — NOT merged before a real Windows test. RED skeleton: API only.

const DLL_NAME := "nml_core_godot.dll"
const EXTRACT_DIR := "user://_update/extracted"
const MARKER_PATH := "user://core_selfheal.txt"

enum Action { NONE, HEAL, HEALED, GIVE_UP, NO_SOURCE }


static func decide(_windows_export: bool, _core_loaded: bool, _tried: bool, _source_ok: bool) -> Action:
	return Action.NONE


static func run(_ops: Object, _windows_export: bool, _core_loaded: bool) -> Action:
	return Action.NONE
