extends GdUnitTestSuite
## Step 04 of the setup, "Who is at the table?" (sheet 03b): the folded rows 01-03, the heading and the three cards
## with the sheet's texts; the chosen card carries the gold rim, a press chooses, Solo is off without lists.

const MANIFEST := {
	"alien_hives": {"name": "Alien Hives", "lists": [
		{"points": 3000, "file": "alien_hives_3000.json"}, {"points": 750, "file": "alien_hives_750.json"}]},
	"orc_tribes": {"name": "Orc Tribes", "lists": [{"points": 1000, "file": "orc_tribes_1000.json"}]},
}
const TEXTS := ["Solo against NACHTMAHR", "The computer opponent builds its own list and plays by the rules.",
	"Two players, one screen", "Share this computer and take turns like at a real table.",
	"Online room", "Create a room for your group and share the invitation code."]


func _step(manifest: Dictionary = MANIFEST, page := Vector2(1920, 1080)) -> Control:
	var opponent := SetupOpponent.new()
	opponent.set_system("gf")
	opponent.set_manifest(manifest)
	var step: Control = auto_free(SetupOpponentStep.new())
	step.size = page
	add_child(step)
	step.setup(opponent, ["Grimdark Future", "Urban ruins", "72 × 48 in"])
	return step


func _texts(step: Control) -> Array:
	return step.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func _card(step: Control, id: String) -> Button:
	return step.find_child("Who_" + id, true, false) as Button


func test_the_folded_rows_the_heading_and_the_three_cards() -> void:
	var step := _step()
	assert_array(_texts(step)).contains(["01", "Game system", "Grimdark Future", "72 × 48 in", "04",
		"Who is at the table?"])
	assert_array(_texts(step)).contains(TEXTS)
	for id: String in ["solo", "local", "online"]:
		assert_object(_card(step, id)).is_not_null()


func test_the_chosen_card_carries_the_rim_and_a_press_chooses() -> void:
	var step := _step()
	assert_bool(_card(step, "solo").get_meta("chosen")).is_true()
	assert_bool(_card(step, "solo").has_theme_stylebox_override(&"normal")).is_true()
	_card(step, "online").pressed.emit()
	assert_str(step.get("_opponent").who).is_equal("online")
	assert_bool(_card(step, "online").get_meta("chosen")).is_true()
	assert_bool(_card(step, "solo").has_theme_stylebox_override(&"normal")).is_false()


func test_solo_is_off_without_lists() -> void:
	var step := _step({})
	assert_bool(_card(step, "solo").disabled).is_true()
	assert_bool(_card(step, "local").get_meta("chosen")).is_true()


func test_a_change_asks_for_that_step() -> void:
	var step := _step()
	var asked: Array = []
	step.connect("change_requested", func(i: int) -> void: asked.append(i))
	(step.find_child("Change3", true, false) as Button).pressed.emit()
	assert_array(asked).is_equal([3])


func test_the_solo_card_has_the_three_dropdowns_with_the_manifests_values() -> void:
	var step := _step()
	var faction := step.find_child("Faction", true, false) as OptionButton
	var points := step.find_child("Points", true, false) as OptionButton
	var seat := step.find_child("Seat", true, false) as OptionButton
	assert_array(range(faction.item_count).map(func(i: int) -> String: return faction.get_item_text(i))).is_equal(
		["Alien Hives", "Orc Tribes"])
	assert_str(points.get_item_text(points.selected)).is_equal("3000 points")
	assert_str(seat.get_item_text(seat.selected)).is_equal("Player 2 (Red)")
	assert_array(_texts(step)).contains(["FACTION", "POINTS", "AI PLAYS AS"])


func test_a_faction_change_refills_the_points_and_picks_the_largest() -> void:
	var step := _step()
	var faction := step.find_child("Faction", true, false) as OptionButton
	faction.select(1)
	faction.item_selected.emit(1)
	var points := step.find_child("Points", true, false) as OptionButton
	assert_int(points.item_count).is_equal(1)
	assert_str(points.get_item_text(points.selected)).is_equal("1000 points")
	assert_str(step.get("_opponent").faction).is_equal("orc_tribes")


func test_the_solo_card_hides_for_the_other_cards_and_says_why_it_is_off() -> void:
	var step := _step()
	var card := (step.find_child("Faction", true, false) as Control).get_parent().get_parent().get_parent() as Control
	_card(step, "local").pressed.emit()
	assert_bool(card.visible).is_false()
	var off := _step({})
	assert_array(_texts(off)).contains(["NACHTMAHR's lists need a connection the first time."])
