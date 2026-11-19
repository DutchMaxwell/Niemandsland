extends RefCounted
## C-19: the AI door's default slice is the measured deny-list. A case that is about a unit the NARROW (allow) slice refuses
## (a unit with a rule is "not plain", the census labels of such a unit) pins that slice through the real way back,
## `NML_CORE_SLICE=allow`, and releases it in after_test. The human door reads the allow file by default and needs no pin.


static func narrow() -> void:
	OS.set_environment("NML_CORE_SLICE", "allow")
	CoreSlice.reset_cache()


static func release() -> void:
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## DLINES2 (19.11.): the deny list also refuses the rules whose battle-log line the door omits (`kind` "rule_line" groups and the
## deny_names that cite `dlines_gap`): their DICE are equal, only a line is missing. A case that is about the dice of such a family
## (a parity or contact test) reads the list WITHOUT those entries - the production file minus its line refusals - through the test
## seam, so it keeps proving the dice while production refuses the volley; `release_dice_only()` puts the seam back.
const DICE_ONLY_TMP := "user://slice_pin_dice_only.json"


static func dice_only() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	assert(data is Dictionary, "the production deny list parses")
	var groups: Dictionary = (data as Dictionary).get("groups", {})
	for g in groups.keys():
		if str((groups[g] as Dictionary).get("kind", "")) == "rule_line":
			groups.erase(g)
	var names: Dictionary = (data as Dictionary).get("deny_names", {})
	for n in names.keys():
		if str(names[n]).contains("dlines_gap"):
			names.erase(n)
	var f := FileAccess.open(DICE_ONLY_TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	CoreSlice.path_override = DICE_ONLY_TMP
	CoreSlice.reset_cache()


static func release_dice_only() -> void:
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
