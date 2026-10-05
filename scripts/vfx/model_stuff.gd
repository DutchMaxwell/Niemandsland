class_name ModelStuff
extends RefCounted
## What a unit is made of, by keywords in its name and rules (the army data has no model kind): machine words make a
## machine, undead words the undead; a Tough(6+) unit with no creature hint stays a machine (the old vehicle rule),
## everything else is flesh. Decides blood vs oil vs bone dust for stains and the combat effects.

enum Stuff { FLESH, MACHINE, UNDEAD }
const MACHINE_WORDS := ["self repair", "robot", "machine", "drone", "vehicle", "tank", "walker", "mech", "construct",
	"golem", "transport", "aircraft", "automaton", "servitor"]
const UNDEAD_WORDS := ["undead", "skeleton", "zombie", "wraith", "ghoul", "spectral", "lich", "mummy", "revenant"]
## Hints that a big (Tough 6+) unit is a creature, not a machine — the old rule called every Tough(6+) a vehicle.
const FLESH_WORDS := ["monster", "beast", "dragon", "rex", "wyrm", "giant", "troll", "hydra", "behemoth",
	"spider", "worm", "brood", "ogre", "mammoth", "wyvern", "regeneration", "fear", "rampage"]


static func stuff_of(unit: GameUnit) -> Stuff:
	return Stuff.FLESH if unit == null else stuff_of_props(unit.unit_properties)


static func stuff_of_props(props: Dictionary) -> Stuff:
	var rules: Array = props.get("special_rules", [])
	var text := (str(props.get("name", "")) + " " + " ".join(PackedStringArray(rules.map(func(r):
		return str(r.get("name", "")) if r is Dictionary else str(r))))).to_lower().replace("-", " ")
	var has := func(words: Array) -> bool: return words.any(func(w: String) -> bool: return text.contains(w))
	if has.call(MACHINE_WORDS):
		return Stuff.MACHINE
	if has.call(UNDEAD_WORDS):
		return Stuff.UNDEAD
	var tough := 0
	var m := RegEx.create_from_string("tough\\s*\\((\\d+)\\)").search(text)
	if m != null:
		tough = int(m.get_string(1))
	return Stuff.MACHINE if tough >= 6 and not has.call(FLESH_WORDS) else Stuff.FLESH
