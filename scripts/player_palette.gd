class_name PlayerPalette
extends RefCounted
## Single source of truth for per-player colours. Presence (avatars, cursors, chat) AND army bases share
## this, so a player's head/cursor always matches their army — including at slot >= 5, where the old army
## table fell back to grey while presence wrapped, and even at slots 1-4 where the three former literals
## disagreed on RGB (bus 036). Slots are 1-indexed; colours wrap past the palette length.

const PALETTE: Array[Color] = [
	Color(0.20, 0.40, 0.90),  # 1 Blue (host)
	Color(0.90, 0.20, 0.20),  # 2 Red
	Color(0.20, 0.80, 0.30),  # 3 Green
	Color(0.90, 0.70, 0.10),  # 4 Yellow
	Color(0.65, 0.35, 0.90),  # 5 Purple
	Color(0.20, 0.80, 0.85),  # 6 Cyan
]


## The colour for a 1-indexed player slot; wraps past the palette length so a 3+-player game never runs
## out. Slot <= 0 (unassigned/pending) resolves to slot 1 so nothing renders an undefined colour.
static func color_for_slot(slot: int) -> Color:
	var s: int = maxi(slot, 1)
	return PALETTE[(s - 1) % PALETTE.size()]
