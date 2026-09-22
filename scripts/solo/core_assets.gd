## The files the Rust core reads with std::fs from its repo root — rules, spells,
## the row vocab and the shipped brain — staged out of the PCK into a real
## directory. An EXPORTED build packs res:// into the PCK, so the core's
## `Registries::new(root)` found NO file there and answered with an EMPTY rules map
## (rules.rs rules_for: unreadable = empty, no error). In the editor res:// is a
## plain directory and nothing is copied.
class_name CoreAssets
extends RefCounted

## Every path the core opens relative to its root (rules.rs, rows.rs, the brain).
const FILES: Array[String] = [
	"assets/solo/rules_mechanics_aof.json", "assets/solo/rules_mechanics_aofr.json",
	"assets/solo/rules_mechanics_aofs.json", "assets/solo/rules_mechanics_gff.json",
	"assets/solo/rules_mechanics_gf.json",
	"assets/solo/spells_mechanics_aof.json", "assets/solo/spells_mechanics_aofr.json",
	"assets/solo/spells_mechanics_aofs.json", "assets/solo/spells_mechanics_gff.json",
	"assets/solo/spells_mechanics_gf.json",
	"data/encoder_rule_vocab_v1.json",
	"assets/solo/brains/erlkoenig.onnx", "assets/solo/brains/erlkoenig.json",
]

## The directory to hand `NmlCore.set_repo_root`: res:// itself in the editor,
## else the staged copy under user:// (globalized, trailing separator).
static func root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	var dir := stage_dir()
	stage(dir)
	return ProjectSettings.globalize_path(dir)


## One directory per game version, so an update never reads a stale copy.
static func stage_dir() -> String:
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	return "user://nml_core/%s/" % ver


## Copies every FILES entry from res:// into `dir` unless an identical-size copy is
## there. Returns the number of files written; a missing source is skipped with one
## warning (the core then declines that game loudly — never silently).
static func stage(dir: String) -> int:
	var written := 0
	for rel in FILES:
		var src := "res://" + rel
		if not FileAccess.file_exists(src):
			push_warning("[CORE] staged asset missing from the build: %s" % src)
			continue
		var dst := dir + rel
		var bytes := FileAccess.get_file_as_bytes(src)
		if FileAccess.file_exists(dst) and FileAccess.get_file_as_bytes(dst).size() == bytes.size():
			continue
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var f := FileAccess.open(dst, FileAccess.WRITE)
		if f == null:
			push_warning("[CORE] cannot stage %s: %s" % [dst, error_string(FileAccess.get_open_error())])
			continue
		f.store_buffer(bytes)
		f.close()
		written += 1
	return written
