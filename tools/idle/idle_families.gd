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
	"ratmen/champion": 5,
	"ratmen/battle master": 5,
	"ratmen/night scouts": 0,
	"ratmen/brother hepalit": 0,
	"ratmen/captain kedseit": 0,
	"ratmen/getrie veikasip": 0,
	"mummified_undead/skeleton warriors": 0,
	"mummified_undead/skeleton archers": 0,
	"mummified_undead/skeleton leader": 0,
	"mummified_undead/royal guard": 0,
	"mummified_undead/royal champion": 0,
	"mummified_undead/rammit den geddul": 0,
	"mummified_undead/guardian statues": 0,
	"mummified_undead/skeleton giant": 0,
	"mummified_undead/mummies": 0,
	"saurians/saurian warriors": 5,
	"saurians/geckos": 5,
	"saurians/chameleons": 5,
	"saurians/saurian guardians": 5,
	"saurians/gators": 5,
	"saurians/gator veteran": 5,
	"saurians/gecko champion": 5,
	"saurians/kikatle": 5,
	"saurians/teqi": 5,
	"saurians/hakatlo": 5,
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
