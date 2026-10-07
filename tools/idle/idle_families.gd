extends RefCounted
## Explicit list of model families the real-idle exporter may convert, with the tail-bone count each one's
## proven rig carries. Extending the rollout to a new body means adding a line here, with a test.

const TAIL_BONES := {
	"ratmen/warriors": 5,
	"ratmen/storm veterans": 0,
	"ratmen/monks": 0,
	"ratmen/militia": 5,
	"ratmen/grenadiers": 5,
	"ratmen/snipers": 5,
	"ratmen/champion": 0,
	"saurians/saurian warriors": 0,
	"saurians/geckos": 0,
	"saurians/chameleons": 0,
	"saurians/saurian guardians": 0,
	"saurians/gators": 0,
	"saurians/gator veteran": 0,
	"saurians/gecko champion": 0,
	"saurians/kikatle": 0,
	"vampiric_undead/skeleton guard": 0,
	"vampiric_undead/skeleton watch": 0,
	"vampiric_undead/drained soldiers": 0,
	"vampiric_undead/drained archers": 0,
	"vampiric_undead/ghouls": 0,
	"vampiric_undead/skeleton champion": 0,
	"vampiric_undead/vampire master": 0,
	"vampiric_undead/stitched zombies": 0,
	"vampiric_undead/werewolves": 0,
	"vampiric_undead/stitched butchers": 0,
}

static func allows(key: String, tail_bones: int) -> bool:
	for family: String in TAIL_BONES:
		if key == family or key.begins_with(family + "#"):
			return TAIL_BONES[family] == tail_bones
	return false
