extends SceneTree
## HARD REQUIREMENT (coreship brief 11.09.2026): shipping the optional Rust NmlCore
## extension must not move ONE game byte. This prints ONE canonical JSON — class
## presence, the core seam switch, and an ObjectiveLayout stamp for every Solo
## difficulty preset x 5 fixed seeds — so CI can run it twice (extension installed /
## manifest moved away) and diff the "stamps" section. Env NML_DORMANT_STAMPS names a
## file to also write just that section to. A red demo arms a doctrine rung
## (NML_OBJECTIVE_DOCTRINE), which stamps "doctrine" and breaks the diff.
const SEEDS := [1, 2, 3, 4, 5]


func _init() -> void:
	var stamps := {}
	var names: Array = SoloDifficulty.PRESETS.keys()
	names.sort()
	for preset in names:
		var per_seed := {}
		for s in SEEDS:
			# objectives_mode pinned to "rulebook": only the preset/env rung matters here.
			var mode: String = SoloDifficulty.resolve_placement(str(preset), str(preset), "rulebook")
			per_seed[str(s)] = ObjectiveLayout.generate(int(s), {}, {}, {}, 0, 72.0, 48.0, mode)
		stamps[str(preset)] = per_seed
	print("NML_DORMANT_CHECK " + JSON.stringify({
		"class_present": ClassDB.class_exists("NmlCore"),
		"core_enabled": BattleSim.core_enabled(),
		"stamps": stamps}))
	var stamp_path := OS.get_environment("NML_DORMANT_STAMPS")
	if stamp_path != "":
		var f := FileAccess.open(stamp_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(stamps))
			f.close()
	quit(0)
