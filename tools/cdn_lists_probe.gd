extends SceneTree
## Headless probe for the S6 AI-list CDN delivery: performs the EXACT fetch the game's
## _fetch_cdn_text does (same host, same browser UA) against a known-existing object and —
## once the lists are staged — against ai_lists/_manifest.json. Run:
##   godot --headless -s res://tools/cdn_lists_probe.gd [-- path=ai_lists/_manifest.json]
## Prints PROBE_OK <bytes> or PROBE_FAIL <result> <code>.

func _init() -> void:
	_run()


func _run() -> void:
	await process_frame   # _init runs before the loop — the node tree is only usable after a frame
	var rel := "model_manifest.json"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("path="):
			rel = str(a).trim_prefix("path=")
	var http := HTTPRequest.new()
	http.timeout = 15.0
	root.add_child(http)
	var err := http.request("%s/%s" % [AssetCDN.HOST, rel],
		["User-Agent: Mozilla/5.0 (X11; Linux x86_64) Niemandsland"])
	if err != OK:
		print("PROBE_FAIL request_err %d" % err)
		quit(1)
		return
	var res: Array = await http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		print("PROBE_FAIL %d %d" % [int(res[0]), int(res[1])])
		quit(1)
		return
	print("PROBE_OK %d" % (res[3] as PackedByteArray).size())
	quit(0)
