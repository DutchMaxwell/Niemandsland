extends GdUnitTestSuite
## No religious symbols in the spell runes (maintainer, 05.10.): the orbiting glyphs are DATA made only of arcs around
## the glyph's own centre, so a straight stroke (crosses, stars, pentagrams, ankh), an off-centre arc (crescent,
## yin-yang, om) or a spoke (wheel) cannot be expressed at all. A lone arc could still read as a crescent, so every
## glyph has two or three arcs that open different ways. The rune shaders keep no axis-aligned bar either: a vertical
## stroke crossed by a horizontal bar is exactly the cross the maintainer saw.

const GlyphsScript = preload("res://scripts/vfx/spell_glyphs.gd")
const FORBIDDEN := ["bar", "line", "segment", "spoke", "cross", "star", "polygram", "triangle", "crescent", "ankh", "om",
	"wheel", "dot"]
const BARS := ["abs(p.x", "abs(p.y", "abs(c.x", "abs(c.y"]


func test_the_glyphs_hold_no_religious_shape() -> void:
	var glyphs: Array = (load("res://scripts/vfx/spell_glyphs.gd") as Script).get_script_constant_map().get("GLYPH_STROKES", [])
	assert_int(glyphs.size()).is_greater_equal(4)
	for glyph: Array in glyphs:
		assert_int(glyph.size()).is_between(2, 3)
		var mids: Array = []
		for stroke: Array in glyph:
			assert_bool(FORBIDDEN.has(str(stroke[0]))).is_false()
			assert_str(str(stroke[0])).is_equal("arc")   # the only stroke the glyph shader can draw
			assert_float(float(stroke[1])).is_between(0.25, 0.85)   # radius, in half the glyph's size
			assert_float(float(stroke[3])).is_between(0.15, 0.7)    # span in turns: never a closed ring
			mids.append(fmod(float(stroke[2]) + float(stroke[3]) * 0.5, 1.0))
		var spread := 0.0   # arcs that all open the same way read as a crescent
		for a: float in mids:
			for b: float in mids:
				spread = maxf(spread, minf(absf(a - b), 1.0 - absf(a - b)))
		assert_float(spread).is_greater_equal(0.25)


func test_the_rune_shaders_draw_no_straight_bar() -> void:
	for code: String in [GlyphsScript.GLYPH, GlyphsScript.COLUMN]:
		for bar: String in BARS:
			assert_bool(code.contains(bar)).override_failure_message("a straight bar in a rune shader: " + bar).is_false()
