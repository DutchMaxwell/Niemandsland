class_name LessonChecks
extends RefCounted
## Pure, stateless completion checks a Game School lesson step can name. Every check compares the
## CURRENT game-state snapshot (`now`) against the snapshot taken when the step began (`base`) —
## a state check, never a gesture. See scripts/spielschule_lessons.gd for the step data that uses
## these, and scripts/lesson_facts.gd for how `now`/`base` snapshots are built.

## Names of every check this file implements. `passes()` fails (and warns) on anything else so an
## unrecognised check can never silently mark a lesson complete.
const KNOWN := [
	"camera_turned",
	"camera_zoomed",
	"camera_panned",
	"counter_grew",
	"counter_at_least",
	"flag",
	"at_least",
	"value_changed",
	"value_is",
	"unit_selected_whole",
	"unit_moved",
	"tag_flag",
	"gap_at_most",
]


## True when every entry of `step["all"]` (Array of `{check: String, args: Dictionary}`) passes.
static func passes(step: Dictionary, now: Dictionary, base: Dictionary) -> bool:
	var entries: Array = step.get("all", [])
	if entries.is_empty():
		return false
	for entry in entries:
		var check_name := String(entry.get("check", ""))
		var args: Dictionary = entry.get("args", {})
		if not KNOWN.has(check_name):
			push_warning("LessonChecks: unknown check '%s'" % check_name)
			return false
		if not _passes_one(check_name, args, now, base):
			return false
	return true


static func _passes_one(check_name: String, args: Dictionary, now: Dictionary, base: Dictionary) -> bool:
	match check_name:
		"camera_turned":
			var base_yaw := float(base.get("yaw", 0.0))
			var now_yaw := float(now.get("yaw", 0.0))
			return absf(angle_difference(base_yaw, now_yaw)) >= deg_to_rad(float(args.get("deg", 0.0)))
		"camera_zoomed":
			var base_dist := float(base.get("cam_dist", 0.0))
			var now_dist := float(now.get("cam_dist", 0.0))
			return absf(now_dist - base_dist) / maxf(base_dist, 0.001) >= float(args.get("ratio", 0.0))
		"camera_panned":
			var now_pivot: Vector3 = now.get("pivot", Vector3.ZERO)
			var base_pivot: Vector3 = base.get("pivot", Vector3.ZERO)
			return now_pivot.distance_to(base_pivot) >= float(args.get("m", 0.0))
		"counter_grew":
			var key := String(args.get("key", ""))
			var now_counters: Dictionary = now.get("counters", {})
			var base_counters: Dictionary = base.get("counters", {})
			return int(now_counters.get(key, 0)) > int(base_counters.get(key, 0))
		"counter_at_least":
			var key_abs := String(args.get("key", ""))
			var now_abs: Dictionary = now.get("counters", {})
			return int(now_abs.get(key_abs, 0)) >= int(args.get("n", 1))
		"flag":
			return bool(now.get(String(args.get("key", "")), false))
		"at_least":
			return int(now.get(String(args.get("key", "")), 0)) >= int(args.get("n", 0))
		"value_changed":
			var key2 := String(args.get("key", ""))
			return now.get(key2) != base.get(key2)
		"value_is":
			return now.get(String(args.get("key", ""))) == args.get("value")
		"unit_selected_whole":
			var tag := String(args.get("tag", ""))
			var now_tags: Dictionary = now.get("tags", {})
			if not now_tags.has(tag):
				return false
			return bool(now_tags[tag].get("selected_whole", false))
		"unit_moved":
			var tag2 := String(args.get("tag", ""))
			var now_tags2: Dictionary = now.get("tags", {})
			var base_tags2: Dictionary = base.get("tags", {})
			if not now_tags2.has(tag2) or not base_tags2.has(tag2):
				return false
			var now_centroid: Vector2 = now_tags2[tag2].get("centroid_in", Vector2.ZERO)
			var base_centroid: Vector2 = base_tags2[tag2].get("centroid_in", Vector2.ZERO)
			return now_centroid.distance_to(base_centroid) >= float(args.get("inches", 0.0))
		"tag_flag":
			var tag3 := String(args.get("tag", ""))
			var now_tags3: Dictionary = now.get("tags", {})
			if not now_tags3.has(tag3):
				return false
			return now_tags3[tag3].get(String(args.get("key", "")), null) == args.get("value")
		"gap_at_most":
			var tag4 := String(args.get("tag", ""))
			var now_tags4: Dictionary = now.get("tags", {})
			if not now_tags4.has(tag4):
				return false
			return float(now_tags4[tag4].get("enemy_gap_in", INF)) <= float(args.get("inches", 0.0))
	return false
