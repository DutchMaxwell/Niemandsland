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
