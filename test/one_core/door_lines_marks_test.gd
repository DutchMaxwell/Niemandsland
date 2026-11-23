extends GdUnitTestSuite
## PLAN H, the shooter-side Mark beats (`vs_target` Utility Buffs: "once per activation, before attacking, pick one enemy unit ... which friendly
## units get <Rule> against once"). The table says three lines (`_solo_apply_vs_marks`: the pick; `_solo_record_spell_mod`: `... is ACTIVE`;
## `_solo_spend_records`: `... is consumed`); the core placed and spent the Mark without saying them. Per Mark name: 16 seeds of a unit carrying
## it at a plain unit: the door's lines that name the Mark, per seed, pinned as literals.
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://door_lines_marks_dice"
const SEEDS := 16
## [Mark name, game system, faction folder]; every one carries `vs_target` in the registry map of its system. Only the Marks whose probe read EQUAL
## on the dice, both end states and every Mark line over 16 seeds belong here (Plan H probe, 20.11.). Not here, with the reason: Relentless Mark and
## Surge Mark (the table's per-effect line names the Mark, the core's does not), Rapid Charge Mark and Piercing Fighting Mark (a melee-scoped record:
## the core spends it in a volley, the table does not), Shred Mark (dice differ), Slayer / Indirect / Quick Shot / Increased Shooting Range Mark
## (the table never placed the Mark in this fixture, so nothing was compared).
const MARKS := [["Furious Mark", "gf", "rebel_guerrillas"], ["Rending Mark", "gf", "orc_marauders"], ["Unstoppable Mark", "gf", "battle_brothers"],
	["Piercing Shooting Mark", "gf", "dao_union"], ["Unpredictable Shooter Mark", "gf", "goblin_reclaimers"], ["Unpredictable Fighter Mark", "gf", "alien_hives"]]

## The door's Mark lines per seed, read on main (where the table still shoots and equals the door).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_FURIOUS_MARK := [
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"],
	["COMBAT|Furious Mark: Att marks Def — friendly units attacking it gain Furious (once)","COMBAT|Furious Mark on Def is ACTIVE: grants Furious — applies ONCE","COMBAT|\"Furious Mark\" on Def is consumed (applies once)"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_RENDING_MARK := [
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"],
	["COMBAT|Rending Mark: Att marks Def — friendly units attacking it gain Rending (once)","COMBAT|Rending Mark on Def is ACTIVE: grants Rending — applies ONCE","COMBAT|\"Rending Mark\" on Def is consumed (applies once)"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_UNSTOPPABLE_MARK := [
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unstoppable Mark: Att marks Def — friendly units attacking it gain Unstoppable (once)","COMBAT|Unstoppable Mark on Def is ACTIVE: grants Unstoppable — applies ONCE","COMBAT|\"Unstoppable Mark\" on Def is consumed (applies once)"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_PIERCING_SHOOTING_MARK := [
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"],
	["COMBAT|Piercing Shooting Mark: Att marks Def — friendly units attacking it gain AP(+1) when shooting (once)","COMBAT|Piercing Shooting Mark on Def is ACTIVE: grants AP(+1) when shooting (shooting only) — applies ONCE","COMBAT|\"Piercing Shooting Mark\" on Def is consumed (applies once)"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_UNPREDICTABLE_SHOOTER_MARK := [
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Shooter Mark: Att marks Def — friendly units attacking it gain Unpredictable Shooter (once)","COMBAT|Unpredictable Shooter Mark on Def is ACTIVE: grants Unpredictable Shooter (shooting only) — applies ONCE","COMBAT|\"Unpredictable Shooter Mark\" on Def is consumed (applies once)"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_UNPREDICTABLE_FIGHTER_MARK := [
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"],
	["COMBAT|Unpredictable Fighter Mark: Att marks Def — friendly units attacking it gain Unpredictable Fighter (once)","COMBAT|Unpredictable Fighter Mark on Def is ACTIVE: grants Unpredictable Fighter — applies ONCE","COMBAT|\"Unpredictable Fighter Mark\" on Def is consumed (applies once)"]]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _entry(uname: String, rules: Array, system: String, faction: String) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = 5
	ou.quality = 4
	ou.defense = 4
	ou.game_system = system
	ou.special_rules.assign(rules)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 5
	ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": system}


func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


func _named(lines: Array, mark: String) -> Array:
	return lines.filter(func(l: String) -> bool: return l.begins_with("COMBAT|") and l.contains(mark))


## 16 seeds of a carrier of `mark` at a plain unit: the door's lines that name the Mark, per seed.
func _compare(mark: Array) -> Array:
	var dice := ProjectSettings.globalize_path(DICE)
	var shooter := _entry("Att", [mark[0]], mark[1], mark[2])
	var target := _entry("Def", [], mark[1], mark[2])
	var got: Array = []
	for s in SEEDS:
		var door := await RosterSweep.volley(_main, shooter, target, s, true, dice)
		got.append(_named(door["lines"], mark[0]))
	return got


func test_a_mark_says_the_pick_the_record_and_the_spend_on_both_halves() -> void:
	var want := [WANT_FURIOUS_MARK, WANT_RENDING_MARK, WANT_UNSTOPPABLE_MARK, WANT_PIERCING_SHOOTING_MARK,
		WANT_UNPREDICTABLE_SHOOTER_MARK, WANT_UNPREDICTABLE_FIGHTER_MARK]
	for i in MARKS.size():
		var got: Array = await _compare(MARKS[i])
		var fired := got.filter(func(l: Array) -> bool: return not l.is_empty()).size()
		assert_int(fired).override_failure_message("%s: the door never said a Mark line, nothing is pinned" % MARKS[i][0]).is_equal(SEEDS)
		assert_array(got).override_failure_message("%s: the door's Mark lines moved from the pinned values" % MARKS[i][0]).is_equal(want[i])
