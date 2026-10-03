extends SceneTree
## Tray-exact S3-1: write the table's per-model kits for Army-Forge lists as sidecars the trainer
## reads (selfplay.kits_sidecar). The AI-list dirs are read-only reference corpora, so the
## sidecars go to --out (then NML_KITS_DIR=<out> for the trainer).
##
##   godot --headless --path . -s res://tools/export_model_kits.gd -- --out DIR LIST_OR_DIR...
##
## One line per list: "kits: <list> units=<n> models=<m> -> <sidecar>"; a list that does not
## import is reported and skipped, and the exit code says how many were skipped.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ""
	var lists: Array = []
	var i := 0
	while i < args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
			i += 2
			continue
		var p: String = args[i]
		if DirAccess.dir_exists_absolute(p):
			for f in DirAccess.get_files_at(p):
				if f.ends_with(".json") and not f.ends_with(".kits.json"):
					lists.append(p.path_join(f))
		else:
			lists.append(p)
		i += 1
	if out.is_empty() or lists.is_empty():
		push_error("usage: -- --out DIR LIST_OR_DIR...")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var skipped := 0
	for path in lists:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var holder := Node.new()
		root.add_child(holder)
		var res: Dictionary = ModelKitsExport.kits_of_list(data, holder) if data is Dictionary else {}
		holder.free()
		if res.is_empty():
			print("kits: %s did not import - skipped" % path)
			skipped += 1
			continue
		res["list"] = path.get_file()
		var side := out.path_join(path.get_file().get_basename() + ".kits.json")
		var f := FileAccess.open(side, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, "", true))
		f.close()
		var models := 0
		for k in res["units"]:
			models += (res["units"][k] as Array).size()
		print("kits: %s units=%d models=%d -> %s" % [path.get_file(), res["units"].size(), models, side])
	quit(skipped)
