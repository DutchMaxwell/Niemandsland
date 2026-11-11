extends GdUnitTestSuite
## W1.1b (0.3.15, rules 3.6): the UI names the rules the build plays. The footer of the start menu and
## the first line of the HUD info label both carry "· rules 3.6" next to the game version. The rules
## number is not a second constant: it comes from the rule maps' own `_meta.core_version` through
## `OPRApiClient.rules_core_version`, shown as major.minor. The GF map is the source of the display;
## a test pins that GF and AoF agree, because both systems in scope play 3.6. If the map cannot be
## read the old text stays unchanged, so an early boot never shows a half sentence.

const StartupScript := preload("res://scripts/startup_menu.gd")
const MainScript := preload("res://scripts/main.gd")


func before_test() -> void:
	# The reader caches per system; every case starts from the maps on disk.
	OPRApiClient._core_versions.clear()


func after_test() -> void:
	OPRApiClient._core_versions.clear()


func _rules_mm() -> String:
	return OPRApiClient._major_minor(OPRApiClient.rules_core_version("gf"))


func _game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


## A bare main with just the node path the function under test reads.
func _main_with_info_label(text: String) -> Node3D:
	var main: Node3D = auto_free(MainScript.new())
	var ui := Node.new()
	ui.name = "UI"
	var hud := Node.new()
	hud.name = "HUD"
	var label := Label.new()
	label.name = "InfoLabel"
	label.text = text
	main.add_child(ui)
	ui.add_child(hud)
	hud.add_child(label)
	return main


func test_the_start_menu_footer_names_the_rules_version() -> void:
	var rules := _rules_mm()
	assert_str(rules).override_failure_message(
		"the GF rule map names no major.minor rules version").is_not_empty()
	var footer := StartupScript.version_string()
	assert_str(footer).override_failure_message(
		"the start menu footer does not name the rules: '%s'" % footer).ends_with(" · rules " + rules)


func test_the_rules_label_matches_both_systems_in_scope() -> void:
	var gf := _rules_mm()
	var aof := OPRApiClient._major_minor(OPRApiClient.rules_core_version("aof"))
	assert_str(gf).override_failure_message("GF and AoF disagree on the rules version").is_equal(aof)
	var footer := StartupScript.version_string()
	assert_str(footer).override_failure_message(
		"the start menu footer does not name the AoF rules: '%s'" % footer).ends_with(" · rules " + aof)


func test_the_hud_first_line_names_the_rules_version() -> void:
	var rules := _rules_mm()
	var main := _main_with_info_label("Niemandsland v0.0.0\n- WASD: move")
	main.call("_apply_version_to_info_label")
	var label := main.get_node("UI/HUD/InfoLabel") as Label
	var first := label.text.split("\n")[0]
	assert_str(first).override_failure_message(
		"the HUD first line does not name the rules: '%s'" % first).ends_with(" · rules " + rules)
	assert_str(label.text).override_failure_message(
		"the HUD function lost the lines below the version").contains("\n- WASD: move")


## CONTROL: an unreadable map keeps the footer exactly as it is today.
func test_control_start_menu_footer_is_unchanged_without_a_map() -> void:
	OPRApiClient._core_versions["gf"] = ""
	assert_str(StartupScript.version_string()).is_equal("v%s" % _game_version())


## CONTROL: an unreadable map keeps the HUD first line exactly as it is today.
func test_control_hud_first_line_is_unchanged_without_a_map() -> void:
	OPRApiClient._core_versions["gf"] = ""
	var main := _main_with_info_label("old first line\n- WASD: move")
	main.call("_apply_version_to_info_label")
	var label := main.get_node("UI/HUD/InfoLabel") as Label
	assert_str(label.text.split("\n")[0]).is_equal("Niemandsland v%s" % _game_version())
