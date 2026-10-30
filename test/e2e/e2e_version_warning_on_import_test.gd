extends GdUnitTestSuite
## D5 (b), step 7 of the v3.6 plan: the game IMPORTS a book on other rules than the ones it plays,
## but says so visibly — driven through the REAL import handler and read off the REAL toast.
##
## The old suite called the gate's own helpers directly, so its RED was a "symbol not found" parse
## error instead of a behaviour. This suite never names the new symbols: it boots main.tscn, builds a
## real army from the per-instance caches (exactly as the deleted suite did) and lets
## _on_opr_army_imported run, then reads the SoloActionToast label. On the base it fails on an
## assertion, not on a parse error.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ApiScript := preload("res://scripts/opr_api_client.gd")

const LIST_FIXTURE := "res://test/fixtures/wolf_brothers_3000.json"
## The book id the wolf fixture's units carry (and the offline index resolves).
const WOLF_BOOK_ID := "yxjboa8oma9bbdck"
## Marks a rules-version warning; every case looks for THIS phrase, never for the gate symbols.
const WARNING_MARKER := "Army Forge serves rules"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _import(book_version: String) -> OPRApiClient.OPRArmy:
	var client: OPRApiClient = ApiScript.new()
	client._army_books[WOLF_BOOK_ID] = {
		"name": "Wolf Brothers", "versionString": book_version, "units": [],
	}
	client._common_rules_cache[2] = {"rules": [], "traits": []}  # 2 = _game_system_id("gf")
	var army: OPRApiClient.OPRArmy = await client.import_from_tts_json(
		FileAccess.get_file_as_string(LIST_FIXTURE))
	client.free()
	# No models: the warning is the handler's first step, and the 43 Wolf Brothers models pulled
	# ~300 MB from the CDN on a fresh CI runner (5 min timeout; a warm laptop cache hid it).
	if army != null:
		army.units.clear()
	return army


## Import one book through the real handler; a stale toast (and its text) is cleared first, so a
## silent import can never inherit the warning of the previous one.
func _import_and_hide_old_toast(book_version: String) -> OPRApiClient.OPRArmy:
	_main._solo_hide_toast(true)
	var army := await _import(book_version)
	await _main._on_opr_army_imported(army, 1, false)
	await E2EBoot.settle(get_tree())
	return army


func _visible_warning() -> String:
	var t: Label = _main._solo_toast
	if t == null or not is_instance_valid(t) or not t.visible:
		return ""
	return t.text if t.text.contains(WARNING_MARKER) else ""


## W1.1a (rules 3.6): a book on the pinned major.minor (gf = 3.6.0) is the same rules and imports
## silently; a bare "3" says nothing about the rules and stays silent too.
func test_a_36_book_imports_silently() -> void:
	for book_version: String in ["3.6.0", "3.6", "3"]:
		var army := await _import_and_hide_old_toast(book_version)
		assert_object(army).override_failure_message("a '%s' book did not import" % book_version).is_not_null()
		var warning := _visible_warning()
		assert_str(warning).override_failure_message(
			"a '%s' book must import silently, toast says '%s'" % [book_version, warning]).is_empty()


## CONTROL: a book without a version string must never invent a warning.
func test_control_a_book_without_a_version_imports_silently() -> void:
	var army := await _import_and_hide_old_toast("")
	assert_object(army).override_failure_message("a book without a version did not import").is_not_null()
	assert_str(_visible_warning()).override_failure_message(
		"a book without a version must import silently").is_empty()


## The pinned rules version is the maps' own _meta.core_version (single source of truth): GF and AoF
## play 3.6.0, the spin-off maps stay on 3.5.1 in this release.
func test_gf_and_aof_maps_pin_360_the_spin_offs_keep_351() -> void:
	var pins := {"gf": "3.6.0", "gff": "3.5.1", "aof": "3.6.0", "aofs": "3.5.1", "aofr": "3.5.1"}
	for system: String in pins:
		var path := "res://assets/solo/rules_mechanics_%s.json" % system
		var text := FileAccess.get_file_as_string(path)
		assert_str(text).override_failure_message("cannot read %s" % path).is_not_empty()
		var parsed = JSON.parse_string(text) if not text.is_empty() else null
		assert_bool(parsed is Dictionary).override_failure_message("%s is not a JSON object" % path).is_true()
		if not (parsed is Dictionary):
			continue
		var meta = parsed.get("_meta")
		assert_bool(meta is Dictionary).override_failure_message("%s has no _meta" % path).is_true()
		if not (meta is Dictionary):
			continue
		assert_str(str(meta.get("core_version", ""))).override_failure_message(
			"%s does not pin %s" % [path, pins[system]]).is_equal(pins[system])


## THE PROVING CASE: an OLD (3.5.x) book on gf imports, says so visibly, names the book as the older
## side (never "the game runs on the old rules") and does NOT promise something unbuilt.
func test_an_old_35_book_imports_with_a_visible_warning() -> void:
	for book_version: String in ["3.5.3", "3.5"]:
		var army := await _import_and_hide_old_toast(book_version)
		assert_object(army).override_failure_message("a %s book did not import" % book_version).is_not_null()
		var toast: Label = _main._solo_toast
		assert_object(toast).override_failure_message(
			"no toast after importing a %s book" % book_version).is_not_null()
		if not is_instance_valid(toast):
			return
		assert_bool(toast.visible).override_failure_message(
			"the %s version warning toast is hidden" % book_version).is_true()
		assert_str(toast.text).contains(book_version)
		assert_str(toast.text).contains("3.6.0")
		assert_str(toast.text).override_failure_message(
			"an older book is told the game runs on old rules: %s" % toast.text).not_contains("runs on the old rules")
		assert_str(toast.text).override_failure_message(
			"the toast promises a refusal that is not built: %s" % toast.text).not_contains("refuse")
