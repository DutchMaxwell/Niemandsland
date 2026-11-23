extends GdUnitTestSuite
## PLAN H, DEADLY LANDING INLINE (`EPOCH_94_PARITY_BATCH` = 94, lead decision 20.11.). The table lands a Deadly weapon's unsaved wounds right
## after that weapon's saves, so a later weapon of the same volley reads the target as it stands then: a lone Hero the Deadly wounds killed no
## longer lends its Stealth / Changebound / Stealth Aura / Evasive to the weapons still to fire ("dead models lend nothing"). The core landed Deadly
## after all the dice and kept the captured target: 11 of 16 seeds of this fixture rolled a different to-hit number on the later weapon (H-10,
## ds/h_probe_stealth_family.md). From 94 the core's volley fold lands each Deadly weapon's groups on a scratch copy of the state and reads
## `Ctx::wiped` for the weapons still to fire; below 94 it is byte-identical.
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://deadly_inline_dice"
const SEEDS := 16
const PENDING_EPOCH := 94

## The door's lines and target survivors per seed, read on main (where the table still shoots and equals the door).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_INLINE_TWO_DEADLY := [
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher B)","COMBAT|Ranks loses a model (4/6)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 4 wounds (2/6)","COMBAT|Ranks loses 2 models (2/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses a model (4/6)"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 4 wounds (2/6)","COMBAT|Ranks loses 3 models (2/6)","COMBAT|Ranks fails morale — Shaken"],
	["COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses 2 models (4/6)"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher B)","COMBAT|Ranks loses a model (4/6)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 4 wounds (2/6)","COMBAT|Ranks loses 2 models (2/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses a model (4/6)"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses a model (4/6)"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher B)","COMBAT|Ranks loses a model (4/6)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 4 wounds (2/6)","COMBAT|Ranks loses 2 models (2/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher B)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses a model (4/6)"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher B)","COMBAT|Ranks loses a model (4/6)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 4 wounds (2/6)","COMBAT|Ranks loses 2 models (2/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher B)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses a model (4/6)"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher B)","COMBAT|Ranks loses a model (4/6)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 3 wounds (3/6)","COMBAT|Ranks loses a model (3/6)","COMBAT|Ranks fails morale — Shaken"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses a model (4/6)"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Deadly Launcher B as declared (10 models in range and sight before the first roll)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 5 wounds (1/6)","COMBAT|Ranks loses 4 models (1/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Ranks saves on 6+ (Def 4+, AP 2)","COMBAT|Deadly(3): 1 unsaved ×3, no carry-over → 1 wound dealt (Deadly Launcher B)","COMBAT|Ranks loses a model (5/6)","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 4 wounds (2/6)","COMBAT|Ranks loses 3 models (2/6)","COMBAT|Ranks fails morale — Shaken"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_INLINE_TAKEDOWN := [
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks saves on 4+"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks loses a model (5/6)","COMBAT|Takedown (Takedown Rifle): the trooper of Ranks is killed","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses 2 models (4/6)"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 3 wounds (3/6)","COMBAT|Ranks loses 3 models (3/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 1 wound (5/6)","COMBAT|Ranks loses a model (5/6)"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks loses a model (5/6)","COMBAT|Takedown (Takedown Rifle): the trooper of Ranks is killed","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses a model (4/6)"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks loses a model (5/6)","COMBAT|Takedown (Takedown Rifle): the trooper of Ranks is killed","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 3 wounds (3/6)","COMBAT|Ranks loses 2 models (3/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks loses a model (5/6)","COMBAT|Takedown (Takedown Rifle): the trooper of Ranks is killed","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses a model (4/6)"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks loses a model (5/6)","COMBAT|Takedown (Takedown Rifle): the trooper of Ranks is killed","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 3 wounds (3/6)","COMBAT|Ranks loses 2 models (3/6)","COMBAT|Ranks fails morale — Shaken"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 1 wound (5/6)","COMBAT|Ranks loses a model (5/6)"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 3 wounds (3/6)","COMBAT|Ranks loses 3 models (3/6)","COMBAT|Ranks fails morale — Shaken"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 3 wounds (3/6)","COMBAT|Ranks loses 3 models (3/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks loses a model (5/6)","COMBAT|Takedown (Takedown Rifle): the trooper of Ranks is killed","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 4 wounds (2/6)","COMBAT|Ranks loses 3 models (2/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks loses a model (5/6)","COMBAT|Takedown (Takedown Rifle): the trooper of Ranks is killed","COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 4 wounds (2/6)","COMBAT|Ranks loses 3 models (2/6)","COMBAT|Ranks passes morale"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Takedown (Takedown Rifle) vs the trooper of Ranks — unit of [1]: hits on 3+, no cover of its own, saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 2 wounds (4/6)","COMBAT|Ranks loses 2 models (4/6)"],
	["COMBAT|Takedown (Takedown Rifle): targets the trooper in Ranks — resolved as a unit of [1]","COMBAT|Ranks saves on 4+","COMBAT|Ranks takes 3 wounds (3/6)","COMBAT|Ranks loses 3 models (3/6)","COMBAT|Ranks passes morale"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_HERO_STEALTH := [
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_HERO_CHANGEBOUND := [
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_HERO_STEALTH_AURA := [
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_HERO_EVASIVE := [
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	["COMBAT|Simultaneous fire: Multi fires Plain Rifle as declared (10 models in range and sight before the first roll)"],
	[]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_BLAST := [
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 3 hits ×3 → 9 hits (cap read when the volley started)"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 3 hits ×3 → 9 hits (cap read when the volley started)"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 3 hits ×3 → 9 hits (cap read when the volley started)"],
	["COMBAT|Blast(3): 4 hits ×3 → 12 hits"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 2 hits ×3 → 6 hits (cap read when the volley started)"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 4 hits ×3 → 12 hits (cap read when the volley started)"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 5 hits ×3 → 15 hits (cap read when the volley started)"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 4 hits ×3 → 12 hits (cap read when the volley started)"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 5 hits ×3 → 15 hits (cap read when the volley started)"],
	["COMBAT|Blast(3): 3 hits ×3 → 9 hits"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 4 hits ×3 → 12 hits (cap read when the volley started)"],
	["COMBAT|Blast(3): 4 hits ×3 → 12 hits"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 5 hits ×3 → 15 hits (cap read when the volley started)"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 4 hits ×3 → 12 hits (cap read when the volley started)"],
	["COMBAT|Simultaneous fire: Blasters fires Blast Rifle as declared (10 models in range and sight before the first roll)","COMBAT|Blast(3): 4 hits ×3 → 12 hits (cap read when the volley started)"],
	["COMBAT|Blast(3): 4 hits ×3 → 12 hits"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_GUARDED_SURVIVORS := [
	[0,[]],
	[0,[]],
	[0,[]],
	[1,[1]],
	[0,[]],
	[0,[]],
	[0,[]],
	[0,[]],
	[0,[]],
	[1,[2]],
	[1,[1]],
	[1,[1]],
	[0,[]],
	[0,[]],
	[1,[1]],
	[1,[1]]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SHIELDED_SURVIVORS := [
	[0,[]],
	[0,[]],
	[0,[]],
	[1,[1]],
	[0,[]],
	[0,[]],
	[0,[]],
	[0,[]],
	[0,[]],
	[1,[2]],
	[1,[1]],
	[1,[1]],
	[0,[]],
	[0,[]],
	[1,[1]],
	[1,[1]]]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(wname: String, count: int, rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = 24
	w.attacks = 1
	w.count = count
	w.special_rules.assign(rules)
	return w


## A 10-model shooter with a Deadly(3) AP(2) launcher (one copy) beside a plain rifle (five copies): the Deadly weapon resolves first.
func _shooter() -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Multi"
	ou.size = 10
	ou.quality = 3
	ou.defense = 4
	ou.game_system = "gf"
	ou.weapons.append(_weapon("Deadly Launcher", 1, ["Deadly(3)", "AP(2)"]))
	ou.weapons.append(_weapon("Plain Rifle", 5, []))
	return {"unit": ou, "faction": "battle_brothers", "system": "gf"}


## A lone Hero, Tough(3), with `rules` (the Deadly launcher kills it on a hit that stays unsaved).
func _hero(rules: Array, faction: String) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Lone Hero"
	ou.size = 1
	ou.quality = 4
	ou.defense = 4
	ou.game_system = "gf"
	ou.special_rules.assign(["Hero", "Tough(3)"] + rules)
	return {"unit": ou, "faction": faction, "system": "gf"}


func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


func _named(lines: Array, prefixes: Array) -> Array:
	return lines.filter(func(l: String) -> bool: return prefixes.any(func(p: String) -> bool: return l.begins_with("COMBAT|" + p)))


## The door's `prefixes` lines at `epoch`, per seed, in order, against the pinned values.
func _door_lines(target: Dictionary, epoch: int, shooter: Dictionary, prefixes: Array, want: Array) -> void:
	AiActRecorder.rules_epoch = epoch
	var dice := ProjectSettings.globalize_path(DICE)
	var got: Array = []
	var fired := 0
	for s in SEEDS:
		var sh := shooter if not shooter.is_empty() else _shooter()
		var door := await RosterSweep.volley(_main, sh, target, s, true, dice)
		var lines := _named(door["lines"], prefixes)
		got.append(lines)
		fired += 1 if not lines.is_empty() else 0
	assert_int(fired).override_failure_message("the door never said the lines, nothing is pinned").is_greater(0)
	assert_array(got).override_failure_message("the door's lines moved from the pinned values").is_equal(want)


## A shooter of ten with `weapons` ([name, copies, rules]) and a plain unit of six: the inline-landing lines fixtures.
func _armed(weapons: Array) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Multi"
	ou.size = 10
	ou.quality = 3
	ou.defense = 4
	ou.game_system = "gf"
	for w in weapons:
		ou.weapons.append(_weapon(w[0], w[1], w[2]))
	return {"unit": ou, "faction": "battle_brothers", "system": "gf"}


## H-17 lines: beside another weapon the table lands a Deadly or Takedown weapon inline and says its lines right there (the weapon's line,
## the casualties, `Simultaneous fire` for the next weapon), then "takes N wounds" counting them too; the door says the same, in that order.
func test_inline_landings_say_their_lines_where_the_table_does() -> void:
	var ranks := _hero([], "battle_brothers")
	ranks["unit"].name = "Ranks"
	ranks["unit"].size = 6
	ranks["unit"].special_rules.assign([])
	var cases := [["two Deadly", _armed([["Deadly Launcher", 1, ["Deadly(3)", "AP(2)"]], ["Deadly Launcher B", 1, ["Deadly(3)", "AP(2)"]],
		["Plain Rifle", 5, []]])], ["Takedown", _armed([["Takedown Rifle", 1, ["Takedown"]], ["Plain Rifle", 5, []]])]]
	var want := [WANT_INLINE_TWO_DEADLY, WANT_INLINE_TAKEDOWN]
	for i in cases.size():
		await _door_lines(ranks, PENDING_EPOCH, cases[i][1], ["Simultaneous fire", "Deadly(", "Takedown (", "Ranks "], want[i])



func test_a_hero_the_deadly_weapon_killed_lends_no_rule_to_the_later_weapon_from_94() -> void:
	var cases := [["Stealth", _hero(["Stealth"], "alien_hives")], ["Changebound", _hero(["Changebound"], "change_disciples")],
		["Stealth Aura", _hero(["Stealth Aura"], "robot_legions")], ["Evasive", _hero(["Evasive"], "battle_brothers")]]
	var want := [WANT_HERO_STEALTH, WANT_HERO_CHANGEBOUND, WANT_HERO_STEALTH_AURA, WANT_HERO_EVASIVE]
	for i in cases.size():
		await _door_lines(cases[i][1], PENDING_EPOCH, {}, ["Simultaneous fire"], want[i])


## A Blast weapon fired after the Deadly one at a unit of four Tough(1) models: the Deadly launcher kills one, the cap of the Blast line was read when the
## volley started (4), the table writes the note, the core now writes it too; the casualty also makes `Simultaneous fire` due.
func test_a_blast_line_after_a_deadly_kill_carries_the_cap_note() -> void:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Blasters"
	ou.size = 10
	ou.quality = 3
	ou.defense = 4
	ou.game_system = "gf"
	ou.weapons.append(_weapon("Deadly Launcher", 1, ["Deadly(3)", "AP(2)"]))
	ou.weapons.append(_weapon("Blast Rifle", 5, ["Blast(3)"]))
	var shooter := {"unit": ou, "faction": "battle_brothers", "system": "gf"}
	var tgt_unit := OPRApiClient.OPRUnit.new()
	tgt_unit.name = "Squad"
	tgt_unit.size = 4
	tgt_unit.quality = 4
	tgt_unit.defense = 4
	tgt_unit.game_system = "gf"
	var target := {"unit": tgt_unit, "faction": "battle_brothers", "system": "gf"}
	await _door_lines(target, PENDING_EPOCH, shooter, ["Simultaneous fire", "Blast("], WANT_BLAST)



## Seeds (of 16) whose save targets (every roll's kind, faces AND target) or end state differ between the table and the core at `epoch`.
## The door's target survivors ([alive, wounds]) at `epoch`, per seed, against the pinned values.
func _door_survivors(target: Dictionary, epoch: int, want: Array) -> void:
	AiActRecorder.rules_epoch = epoch
	var dice := ProjectSettings.globalize_path(DICE)
	var got: Array = []
	for s in SEEDS:
		var door := await RosterSweep.volley(_main, _shooter(), target, s, true, dice)
		got.append([int(door["state"]["tgt"]["alive"]), door["state"]["tgt"]["wounds"]])
	assert_array(got).override_failure_message("the door's survivors moved from the pinned values").is_equal(want)


## H-17 (`EPOCH_95_PARITY_BATCH` = 95, lead call 21.11.): the volley is fired simultaneously, so a Guarded / Shielded Hero the
## Deadly weapon killed keeps its declared Defense for the later weapon's saves, as the table does; at 94 the core drops it (save one worse).
func test_a_killed_hero_keeps_its_declared_defense_from_95() -> void:
	var rules := ["Guarded", "Shielded"]
	var want := [WANT_GUARDED_SURVIVORS, WANT_SHIELDED_SURVIVORS]
	for i in rules.size():
		await _door_survivors(_hero([rules[i]], "battle_brothers"), PENDING_EPOCH + 1, want[i])
