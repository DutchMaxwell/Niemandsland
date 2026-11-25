# One-core switches

The environment switches that steer the one-core doors (the Rust rules core taking an activation
instead of the GDScript table). Each one is read ONCE per process unless the row says otherwise, so
set it before the game starts; the tests bypass the env and set the static seam instead.

## The door switches

| Switch | Default | Read at | What it does | Retires with |
|---|---|---|---|---|
| `NML_CORE` | ON when unset or `1`; any other value (e.g. `0`) turns it off | `scripts/solo/battle_sim.gd:89` (`core_enabled`); the pure rule is `core_wanted` at `battle_sim.gd:102` | Asks the Rust core for the AI's decision (`SoloController._core_plan` → `plan_with_rollout`) and, together with `NML_CORE_MOVE`, for movement planning. A missing library warns once and leaves the GDScript planner in charge. Also decides whether a solo seat may be Erlkönig (`shipped_brain_ready`) | no step named yet: "the core is mandatory" is P4.D-40, and the GDScript search it still guards dies only when the P4.D-63 gates G1–G4 hold |
| `NML_ONE_CORE_ACTIVATION` | ON (unset or `1`; `0` / `off` is the kill switch) | `scripts/solo/core_activation.gd:13` | The master door flag: `CoreActivation.applies()` is asked by every core door (AI volley, human shot, lifecycle). Off restores the table path without the core doors (the flow before they shipped) | P4.D-41 (AI door) and P4.D-43 (human door), each dropping the kill switch in its own deletion diff |
| `NML_ONE_CORE_HOTSEAT` | ON (unset or `1`; `0` / `off` is the way back) | `scripts/solo/core_activation.gd:38` | Whether a local hotseat Automatic table (two human sides, no AI seat, no peer) counts as a core room: both sides' plain units then resolve their shot, End and move path through the core. Off keeps the table path; Manual rooms never enter the door | P4.D-43c / H-31 |
| `NML_CORE_SLICE` | unset (or `deny`) = both doors read the measured deny-list (C-19 for the AI door, H-30 / DS-109 for the human door); `allow` (or `plain`) = the allow file for both doors (the way back) | `scripts/solo/core_slice.gd` (`allow_switched`, `live_path`, `human_path`) | Picks the slice file behind "does the core take this unit": the deny-list (`assets/solo/core_slice_deny.json`, listed primitives and names stay on the table) or the allow file (`assets/solo/core_slice_allow.json`, only the move-through group beyond units with no rule). C-19 switched the AI door (the one the gate measured); H-30 / DS-109 switched the human door (lifecycle, move path, shot) to the same slice. The first load prints one line naming both modes (`[CORE] shoot slice: ...`) | the way back goes after one release; the deny list only shrinks and the switch dies with the slice predicate |
| `NML_CORE_SHADOW` | OFF (`1` / `on` turns it on) | `scripts/solo/core_shadow.gd:59` | Soak-only: keeps a second core board and the table's tray-roll tap for EVERY OPR AI activation. The volley compare is gone (the table no longer resolves volleys); with `NML_CORE_SHADOW_CAST` the casts are still replayed and compared. No die, no line, no landing | no step named yet (decision M-2 (a) drops shadow mode; no step number assigned) |
| `NML_CORE_SELFCHECK` | OFF (`1` turns it on) | `scripts/solo/solo_controller.gd:4186`, `:4218` (read live per call), `:4508` (cached) | Debug bisect seam, never on a shipped path: runs the GDScript search on the same state right after the core and prints the FIRST field the two disagree on and a header report when the header is built; with `NML_CORE_MOVE` it also runs both move planners and keeps the GDScript answer | no step named yet (debug seam) |
| `NML_ONE_CORE_CHOICE_WOUND_ALLOC` | ON (`0` / `off` turns it off) | `scripts/solo/core_activation.gd:48` (built from `CHOICE_KINDS`, `:40`) | The per-choice family's wound-allocation member: with it on the core opens a `wound_alloc` choice and the human owner's click list answers it (one slot per wound, a slot may repeat); with it off the interim wound-prompt guard keeps such a volley on the table | P4.D-27 (switch and the interim guard are deleted after one green soak) |
| `NML_ONE_CORE_CHOICE_TAKEDOWN_MODEL` | OFF (`1` / `on` turns it on) | `scripts/solo/core_activation.gd:48` (built from `CHOICE_KINDS`, `:40`) | The same family's Takedown member: with it on the core asks which model of a target a Takedown shot kills and the table asks the player for that pick; off = the core's automatic pick | no step named yet; the kill-credit widening P4.D-34 needs the choice, no retirement step is written |

The two choice switches share one read (`NML_ONE_CORE_CHOICE_<KIND>`, upper-cased id prefix), so a
new choice kind appears here only when it enters `CHOICE_KINDS`. `CHOICE_DEFAULT_ON` (`:41`) decides
which kinds start ON.

## Other NML reads in the same files

Not door switches, listed so the reproduction below finds nothing unaccounted for:

| Switch | Default | Read at | What it does |
|---|---|---|---|
| `NML_TABLE_CENSUS` | unset = no dump | `scripts/solo/core_activation.gd:480` | A path: a both-AI game writes the runtime counter (reasons, reason sets, core runs/refusals, shadow records) as JSON when it ends |
| `NML_SIM_SPACING` | ON (`0` / `off` opts out) | `scripts/solo/battle_sim.gd:41` | Whether the imagination's resolve honours the 1" no-go spacing rule |
| `NML_SIM_CAST` | OFF (`1` / `on`) | `scripts/solo/battle_sim.gd:53` | Whether resolve() runs the cast sub-phase instead of the legacy shoot-rider |
| `NML_HERO_FOLD` | OFF (`1`) | `scripts/solo/battle_sim.gd:75` | Folds a joined hero into its host inside the imagination (process-wide; the difficulty preset also sets it) |
| `NML_PROFILE` | OFF (`1` / `on`) | `scripts/solo/battle_sim.gd:114` | Wall-clock profiling of the trainer path (buckets nest: plan/resolve/spacing/cast/clone) |
| `NML_CORE_MOVE` | `1` in release, `0` in debug builds | `scripts/solo/solo_controller.gd:4488` | Routes movement planning through the core; the SELFCHECK twin above runs both planners and keeps the GDScript answer |

## Keeping this list true

Run from the repository root. The output must match the reads tabled above (10 lines in the four
door files, 4 in the controller; the last command shows the kind list and the single read that
builds both choice names):

```
grep -rn 'OS.get_environment("NML_' scripts/solo/core_activation.gd scripts/solo/core_slice.gd \
    scripts/solo/core_shadow.gd scripts/solo/battle_sim.gd
grep -n 'OS.get_environment("NML_CORE_SELFCHECK\|OS.get_environment("NML_CORE_MOVE' \
    scripts/solo/solo_controller.gd
grep -n 'CHOICE_KINDS\|CHOICE_DEFAULT_ON\|OS.get_environment("NML_ONE_CORE_CHOICE' \
    scripts/solo/core_activation.gd
```

A new read in one of these files, or a new choice kind, is a row here in the same diff. The
retirement column follows the deletion-blocker list in `test/one_core/deletion_blockers_test.gd`
and the door-first plan's step numbers; "no step named yet" is a fact, not a promise.

See also `docs/one_core/STATE_DELTA_INVENTORY.md` for what the core may hand back to the table.
