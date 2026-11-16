extends RefCounted
class_name CoreLoadNotice
## One-core phase 1: the pure part of the boot notice. An exported build whose Rust rules core
## (the NmlCore GDExtension) failed to load logs one boot line and shows one warning dialog. Since M-3
## (maintainer 16.11.) the core is mandatory for NACHTMAHR and Automatic play: without it the game
## offers Manual play only. The caller passes the two facts in, so this file touches neither ClassDB,
## OS nor the scene tree.

const TITLE := "Rules core missing"
const TEXT := "A part of the game did not load (the rules core library). Playing against NACHTMAHR and Automatic rules are switched off until you reinstall; Manual play still works. Download the full game again from the releases page."
## The one line a door shows (toast + battle log) when it refuses to seat NACHTMAHR or switch Automatic on.
const ENGINE_OFF_LINE := "The rules core did not load, so NACHTMAHR and Automatic rules are not available - Manual play only. Reinstall the game from the releases page."


## The one boot line, printed on every start so a support log shows whether the core loaded.
static func boot_line(core_loaded: bool) -> String:
	if core_loaded:
		return "core: NmlCore loaded"
	return "core: NmlCore NOT loaded - solo and Automatic play are off; reinstall the game"


## The dialog is for players: an exported build that lost its library. The editor and test runs
## (debug builds) have no installed core on purpose and stay silent.
static func should_show(exported: bool, core_loaded: bool) -> bool:
	return exported and not core_loaded
