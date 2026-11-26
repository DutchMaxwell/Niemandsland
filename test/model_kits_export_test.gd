extends GdUnitTestSuite
## Tray-exact S3-1 — ModelKitsExport.kits_of_list runs the TABLE's own import and writes each
## model's kit in model order. The fixture's Custodian Brothers (3 models) carry Flame-Mount x3
## (universal: every model), Custodian Axe x2 and Custodian Spear x1 (limited: distributed by the
## melee slot's cursor) — so all three kits carry the Flame-Mount, two the Axe, one the Spear.

const FIXTURE := "res://test/fixtures/card_list_gf_custodian_brothers_1000.json"


func test_the_export_writes_the_tables_own_per_model_loadout() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var holder: Node = auto_free(Node.new())
	add_child(holder)
	var res := ModelKitsExport.kits_of_list(data, holder)
	assert_str(str(res.get("format", ""))).is_equal(ModelKitsExport.FORMAT)
	var key := ""
	for k in res.get("units", {}):
		if str(k).ends_with("_zHrtuAb"):
			key = k
	assert_str(key).override_failure_message("Custodian Brothers not exported").is_not_empty()
	if key.is_empty():
		return
	var kits: Array = res["units"][key]
	assert_int(kits.size()).is_equal(3)
	var count := func(w: String) -> int:
		return kits.filter(func(k: Dictionary) -> bool: return w in (k["weapons"] as Array)).size()
	assert_int(count.call("Flame-Mount")).is_equal(3)
	assert_int(count.call("Custodian Axe")).is_equal(2)
	assert_int(count.call("Custodian Spear")).is_equal(1)


## KIT-BEARER-NAME K3: an AoF: Skirmish command group names its bearers in the sidecar (the models the import gave the
## Banner and the Musician); a gf list names none, so its sidecar keeps its shape.
func test_the_export_names_the_command_group_bearers() -> void:
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/ratmen_warriors_export.json"))
	var holder: Node = auto_free(Node.new())
	add_child(holder)
	var res := ModelKitsExport.kits_of_list({"name": "t", "gameSystem": "aofs", "units": [fx["drill"]]}, holder)
	var key := "0_%s" % str(fx["drill"]["id"])
	var b: Dictionary = (res.get("bearers", {}) as Dictionary).get(key, {})
	assert_array(b.keys()).override_failure_message("both bearers named: %s" % [b]).contains_exactly_in_any_order(["cmd_bearer", "cmd_musician"])
	assert_int(int(b["cmd_bearer"])).override_failure_message("two models, two bearers").is_not_equal(int(b["cmd_musician"]))
	assert_int(int(b["cmd_bearer"])).is_between(0, (res["units"][key] as Array).size() - 1)
	assert_int(int(b["cmd_musician"])).is_between(0, (res["units"][key] as Array).size() - 1)
	var gf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_bool(ModelKitsExport.kits_of_list(gf, holder).has("bearers")).is_false()
