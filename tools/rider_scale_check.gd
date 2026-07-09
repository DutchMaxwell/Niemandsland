extends SceneTree
## QA tool: rider-constant mount scale acceptance check (Mummified Undead go-live, QA round 3).
##
## Loads REAL pilot GLBs and runs the REAL spawn fit math (OPRArmyManager._get_model_aabb /
## _get_body_aabb / _compute_model_fit) with the exact parameters the spawn path uses for the QA
## list LlY4ue1_JOKN (Royal Champion: 25mm round base, Tough(3); mounts replace the base and fold
## their Tough into the unit rules). It then MEASURES the rider `body`-node world height of each
## mounted model against the foot model's world height and asserts equality within ±5%
## (the foot champion carries its own Tough(3) ⇒ a 1.05 height factor the rider does not get).
##
## Usage (headless, no renderer needed):
##   godot --path <project> --headless -s res://tools/rider_scale_check.gd -- \
##     <foot.glb> <steed.glb> <flyingbeast.glb>
## GLB order: foot = royal champion#greatweapon, steed = #greatweapon+steed,
## flyingbeast = #flyingbeast+greatweapon (pilot manifest sha blobs, downloaded beforehand).
## Exit code 0 = all mounted riders within tolerance; 1 = violation or load error.

## Acceptance tolerance: |rider/foot - 1| <= 5% (the foot hero's own Tough(3) ⇒ ±4.8% by design).
const TOLERANCE: float = 0.05

## Fit parameters per case — mirrors the QA list exactly (AF book t-sIke2snonFSL6Q v3.5.3):
## foot: 25mm round, Tough(3). Steed: 60x35 oval mount base, Tough(3) (steed grants none).
## Flying beast: 160x122 oval mount base, Tough(18) (folded from the mount's rules).
const CASES: Array = [
	{"name": "foot royal champion#greatweapon", "long_mm": 25, "short_mm": -1, "tough": 3, "is_mount": false},
	{"name": "mounted #greatweapon+steed", "long_mm": 60, "short_mm": 35, "tough": 3, "is_mount": true},
	{"name": "mounted #flyingbeast+greatweapon", "long_mm": 160, "short_mm": 122, "tough": 18, "is_mount": true},
]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < CASES.size():
		push_error("Usage: -s res://tools/rider_scale_check.gd -- <foot.glb> <steed.glb> <flyingbeast.glb>")
		quit(1)
		return

	var mgr: OPRArmyManager = OPRArmyManager.new()
	var results: Array = []
	for i in range(CASES.size()):
		var c: Dictionary = CASES[i]
		var glb: Node3D = mgr._instantiate_model(args[i])
		if glb == null:
			push_error("rider_scale_check: failed to load %s" % args[i])
			quit(1)
			return
		var aabb: AABB = mgr._get_model_aabb(glb)
		var body: AABB = mgr._get_body_aabb(glb)
		var fit: Dictionary = mgr._compute_model_fit(aabb, int(c["long_mm"]), int(c["tough"]), 0.0,
			int(c["short_mm"]), false, body, bool(c["is_mount"]))
		var scale: float = float(fit["scale"])
		var body_h_mm: float = (body.size.y if body.size.y > 0.0 else aabb.size.y) * scale * 1000.0
		results.append({
			"name": c["name"],
			"scale": scale,
			"raw_body_h": (body.size.y if body.size.y > 0.0 else aabb.size.y),
			"body_world_mm": body_h_mm,
			"combined_world_mm": aabb.size.y * scale * 1000.0,
			"footprint_world_mm": maxf(aabb.size.x, aabb.size.z) * scale * 1000.0,
			"is_mount": c["is_mount"],
		})
		glb.free()
	mgr.free()

	var foot_mm: float = float(results[0]["body_world_mm"])
	var ok: bool = true
	print("=== rider_scale_check (foot body height = %.2f mm) ===" % foot_mm)
	for r in results:
		var ratio: float = float(r["body_world_mm"]) / foot_mm
		var verdict: String = ""
		if bool(r["is_mount"]):
			var within: bool = absf(ratio - 1.0) <= TOLERANCE
			verdict = "PASS" if within else "FAIL (>±%.0f%%)" % (TOLERANCE * 100.0)
			ok = ok and within
		print("%-36s scale=%.5f raw_body=%.3fu body=%.2fmm (%.2fx foot) combined=%.1fmm footprint=%.1fmm %s"
			% [r["name"], r["scale"], r["raw_body_h"], r["body_world_mm"], ratio,
				r["combined_world_mm"], r["footprint_world_mm"], verdict])
	print("=== RESULT: %s ===" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
