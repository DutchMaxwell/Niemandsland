extends RefCounted
class_name CoreLoadNotice
## One-core phase 1: the pure part of the boot notice. An exported build whose Rust rules core
## (the NmlCore GDExtension) failed to load logs one boot line and shows one warning dialog; the game
## stays playable on the GDScript decision tree. The caller passes the two facts in, so this file
## touches neither ClassDB, OS nor the scene tree.

const TITLE := "Rules core missing"
const TEXT := "A part of the game did not load (the rules core library). NACHTMAHR can only play its simple decision tree until you reinstall. Download the full game again from the releases page."


## The one boot line, printed on every start so a support log shows whether the core loaded.
static func boot_line(core_loaded: bool) -> String:
	if core_loaded:
		return "core: NmlCore loaded"
	return "core: NmlCore NOT loaded - the decision tree plays; reinstall the game"


## The dialog is for players: an exported build that lost its library. The editor and test runs
## (debug builds) have no installed core on purpose and stay silent.
static func should_show(exported: bool, core_loaded: bool) -> bool:
	return exported and not core_loaded
