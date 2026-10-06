extends RefCounted
## Explicit list of model families the real-idle exporter may convert, with the tail-bone count each one's
## proven rig carries. Extending the rollout to a new body means adding a line here, with a test.

const TAIL_BONES := {
	"ratmen/warriors": 5,
	"ratmen/storm veterans": 0,
	"ratmen/monks": 0,
}

static func allows(key: String, tail_bones: int) -> bool:
	for family: String in TAIL_BONES:
		if key == family or key.begins_with(family + "#"):
			return TAIL_BONES[family] == tail_bones
	return false
