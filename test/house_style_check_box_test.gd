extends GdUnitTestSuite
## Every house check box shows its empty square (maintainer 03.10.2026, decision B): Godot's own unchecked icon
## draws at ~1:1 on the house panels (measured 1.04:1), so an empty box read as no box at all. The bar is the
## WCAG 1.4.11 non-text contrast for a control's boundary, 3:1, against the card fill the boxes sit on.

const MIN_CONTRAST := 3.0
const GlassmorphismTheme = preload("res://scripts/glassmorphism_theme.gd")   # the ☰ menu's outer theme (ThemeManager)


## One frame later the theme cache holds what the screen draws (read in the same frame it still answered with
## the engine's icons: measured 03.10., a probe read 1.04:1 there and 17.77:1 one frame on).
func _house_check_box(parent: Node = self) -> CheckBox:
	var box: VBoxContainer = auto_free(VBoxContainer.new())
	box.theme = HouseStyle.theme()
	var cb := CheckBox.new()
	cb.text = "Plasma Rifle"
	box.add_child(cb)
	parent.add_child(box)
	GameMenu.section(box)   # dressed as a house line, as in the game menu and the split-fire card
	await get_tree().process_frame
	return cb


## The card fill the boxes sit on: the house panel over the dark table.
func _card() -> Color:
	var p := HouseStyle.PANEL
	return Color.BLACK.lerp(Color(p.r, p.g, p.b), p.a)


func _lum(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


## The strongest contrast any pixel of `icon` reaches against `ground` (WCAG ratio).
func _contrast(icon: Texture2D, ground: Color) -> float:
	var img := icon.get_image()
	if img.is_compressed():
		img.decompress()
	var best := 1.0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var a := _lum(ground.lerp(Color(p.r, p.g, p.b), p.a))
			var b := _lum(ground)
			best = maxf(best, (maxf(a, b) + 0.05) / (minf(a, b) + 0.05))
	return best


func test_an_empty_check_box_shows_its_square() -> void:
	var c := _contrast((await _house_check_box()).get_theme_icon(&"unchecked"), _card())
	assert_float(c).override_failure_message("the empty box reaches %.2f:1 on the card, below %.1f:1" % [c, MIN_CONTRAST]) \
		.is_greater_equal(MIN_CONTRAST)


func test_a_checked_box_stays_visible() -> void:
	var c := _contrast((await _house_check_box()).get_theme_icon(&"checked"), _card())
	assert_float(c).override_failure_message("the checked box reaches %.2f:1 on the card" % c) \
		.is_greater_equal(MIN_CONTRAST)


## Ticking a box never moves its label: both states draw at one size.
func test_empty_and_checked_share_one_size() -> void:
	var cb := await _house_check_box()
	assert_object(cb.get_theme_icon(&"unchecked").get_size()).is_equal(cb.get_theme_icon(&"checked").get_size())
	assert_object(cb.get_theme_icon(&"unchecked_disabled").get_size()) \
		.is_equal(cb.get_theme_icon(&"checked_disabled").get_size())


## The ☰ menu's sections sit under the glass theme (ThemeManager), a prompt card's do not: a house check box
## draws the same four icons in both, or a box in the menu ticks between two icon families of two sizes.
func test_the_same_boxes_with_or_without_the_glass_theme_above() -> void:
	var bare := await _house_check_box()
	var outer: Control = auto_free(Control.new())
	outer.theme = GlassmorphismTheme.get_theme()
	add_child(outer)
	var in_menu := await _house_check_box(outer)
	for icon_name: StringName in [&"unchecked", &"checked", &"unchecked_disabled", &"checked_disabled"]:
		assert_object(in_menu.get_theme_icon(icon_name)).override_failure_message("%s differs under the glass theme" % icon_name) \
			.is_same(bare.get_theme_icon(icon_name))


## A disabled box is the same pair, dimmer (and dimming it must leave the enabled icons as they were).
func test_a_disabled_box_is_dimmer_than_an_enabled_one() -> void:
	var cb := await _house_check_box()
	for state: String in ["unchecked", "checked"]:
		var on := _contrast(cb.get_theme_icon(StringName(state)), _card())
		var off := _contrast(cb.get_theme_icon(StringName(state + "_disabled")), _card())
		assert_float(off).override_failure_message("%s: disabled %.2f:1 is not dimmer than enabled %.2f:1" % [state, off, on]) \
			.is_less(on)
