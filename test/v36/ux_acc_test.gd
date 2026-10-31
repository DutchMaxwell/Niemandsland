extends GdUnitTestSuite
## UX-ACC: P1 is imported through its LIVE Army Forge share link, so the upstream list can change
## under the acceptance run. The driver guards the MINIMAL composition its own scenario steps need
## (one P1 unit carrying models) and must name the change instead of dying on a null unit.

const DRIVER := "res://test/acceptance/acceptance_driver.gd"


## Loaded by path + call() so this file PARSES pre-fix (a direct reference to the guard would be a
## parse-time error). has_method() records a clean assertion failure for the pre-fix RED.
func _driver() -> Object:
	var script: Object = load(DRIVER)
	assert_bool(script.has_method("p1_composition_problem")).override_failure_message(
		"acceptance driver has no P1 composition guard (pre-fix RED)").is_true()
	return script


func test_a_composition_missing_the_needed_unit_is_named() -> void:
	var script := _driver()
	if not script.has_method("p1_composition_problem"):
		return
	var problem: String = script.call("p1_composition_problem", [])
	assert_str(problem).override_failure_message("an empty P1 list must be named").starts_with(
		"Army Forge list changed: no unit")


func test_one_unit_with_models_passes_the_guard() -> void:
	var script := _driver()
	if not script.has_method("p1_composition_problem"):
		return
	var problem: String = script.call("p1_composition_problem", [{"name": "Battle Brothers", "models": 5}])
	assert_str(problem).override_failure_message("one unit with models is the minimum").is_equal("")
