class_name SpellLook
extends RefCounted
## The spells' elements, read from the spell's NAME (fire, lightning, frost, shadow; anything else is arcane), with
## each element's tint and particle look. Data only: the spell show, its impacts and its hero effects all read it, so
## an element looks the same everywhere and a new keyword is one line here.

enum Element { ARCANE, FIRE, LIGHTNING, FROST, SHADOW }
const WORDS := [[Element.FIRE, ["fire", "flame", "burn", "blaze", "inferno", "ember", "scorch", "pyre", "sun"]],
	[Element.LIGHTNING, ["lightning", "thunder", "storm", "shock", "spark", "volt", "electric", "static"]],
	[Element.FROST, ["frost", "ice", "cold", "freez", "frozen", "winter", "chill", "snow", "blizzard", "hail"]],
	[Element.SHADOW, ["shadow", "dark", "death", "doom", "curse", "hex", "plague", "rot", "decay", "necro", "soul",
		"void", "night", "fear", "terror"]]]
## element -> HDR tint of its ribbons, glyphs and light
const TINTS := [Color(1.35, 0.62, 1.9), Color(2.0, 0.65, 0.12), Color(0.45, 1.3, 2.0), Color(0.6, 1.2, 1.65),
	Color(0.75, 0.24, 1.3)]
## element -> [particle look, particle tint]
const PARTICLES := {Element.ARCANE: [FxBurst.Look.MOTE, Color(1, 1, 1)], Element.FIRE: [FxBurst.Look.EMBER, Color(1, 1, 1)],
	Element.LIGHTNING: [FxBurst.Look.SPARK, Color(0.45, 0.9, 1.6)], Element.FROST: [FxBurst.Look.FROST, Color(1, 1, 1)],
	Element.SHADOW: [FxBurst.Look.WISP, Color(1, 1, 1)]}


## The element a spell's name names; arcane when none of the words is in it.
static func element_of(spell_name: String) -> Element:
	var n := spell_name.to_lower()
	for entry in WORDS:
		if (entry[1] as Array).any(func(w: String) -> bool: return n.contains(w)):
			return entry[0]
	return Element.ARCANE
