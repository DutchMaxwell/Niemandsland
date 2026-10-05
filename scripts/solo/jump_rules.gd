class_name JumpRules
extends RefCounted
## Downward jumps only: GFF p.14 / AoFS p.15; Flying: GFF p.13.
enum DropKind { FREE, JUMP, IMPASSABLE }

## Sample the recorded path against the shared surface truth; foot is just past the edge.
static func drops(points: PackedVector2Array, surface: Callable, start_y: float) -> Array:
	var out: Array = []
	if points.is_empty():
		return out
	var samples := MoveLedger._sample_polyline(points, MoveLedger.CLIMB_SAMPLE_M)
	for p in samples:
		var y: float = surface.call(p)
		var dy_in := roundf((start_y - y) / MoveLedger.INCHES_TO_METERS * 100000.0) / 100000.0
		if dy_in > 3.0:
			out.append({"dy_in": dy_in, "foot": Vector3(p.x, y, p.y)})
		start_y = y
	return out

static func drop_kind(dy_in: float) -> DropKind:
	return DropKind.FREE if dy_in <= 3.0 else (DropKind.JUMP if dy_in <= 6.0 else DropKind.IMPASSABLE)

static func jump_dice(dy_in: float) -> int:
	return floori(dy_in / 3.0) + 1

## A zero target means Flying automatically passes without rolling.
static func jump_target(strider: bool = false, flying: bool = false) -> int:
	return 0 if flying else (2 if strider else 3)

## -1 means no hit (below 2 inches); AP(0) is still one hit.
static func fall_hit_ap(dy_in: float) -> int:
	return floori(dy_in / 3.0) if dy_in >= 2.0 else -1
