# Reinforcement — the mid-game unit-creation seam the fast core does not have

Measured at `caadd053` (origin/main, 2026-09-07) with one run of
`core/nml-core-py/tools/rule_universe_census.py --books <private snapshot>` (89 books, 452 names).

The research verdict this job was briefed on says **PORT** ("a mid-game (re-)arrival mechanic of the Ambush family;
the remaining work is wiring that reading into the core's Ambush arrival seam"). **This note corrects that verdict to
DESIGN.** The seam the verdict points at is a library function with no production caller, and the half the verdict
itself flagged as missing — remove a unit as destroyed, then recreate it — is the wave-4 plan's own **S5** seam
(`docs/plans/RULES_WAVE4_2026-09-06.md` §3: *"no seam; the core creates units only at deployment"*).

## 1. What the rule does on the table

Book text, byte-identical in all four snapshot books that carry it (gf: Ratmen Clans, Soul-Snatcher Cults; aof:
Ratmen, Volcanic Dwarves):

> "When a unit where all models have this rule is Shaken or fully destroyed, you may remove it from the table as
> destroyed and place a new copy of it fully within 12" of any table edge at the beginning of the next round after
> Ambushers have been deployed. Units that deploy via Reinforcement can't seize or contest objectives on the round
> they deploy, and this rule doesn't apply to the new copy of the unit."

Two adjacent names in the same books are **different rules** and are already PORTED under other primitives — do not
conflate them: `Grounded Reinforcement` (Shielded, name token `grounded_reinforcement` at `sim.rs:1837`) and
`Grounded Reinforcement Aura` (Aura Channel, `unit.rs:2281`).

Five beats, all five shipped table-side:

| beat | table |
|---|---|
| trigger: Shaken **or** fully destroyed, all models incl. attached heroes | `solo_controller.gd:5984` (`reinforcement_chain`), `:6041` (`reinforcement_due`) |
| sacrifice: remove as destroyed, by the owner's choice | `main.gd:10192-10447` (radial entry, refusal transparency, sacrifice, arrival) |
| arrival: new copy, fully within 12" of any table edge | `solo_controller.gd:5981` (`REINFORCEMENT_EDGE_IN := 12.0`), `placement_ghost.gd:36`/`:80` (the strip; the base must be FULLY inside) |
| timing: start of the next round, **after** the Ambushers | `main.gd:10183-10186` (`await _reinforcement_arrivals` ordered after the ambush beat) |
| riders: no seize/contest on the arrival round; the copy loses the rule | `solo_controller.gd:6055` (`reinforcement_copy_rules`) |

It is not a Solo-only rule: the same arrivals run in hotseat/MP (`main.gd:11576`), beside the solo round-start hook (`main.gd:2010`).

## 2. What the core has, measured

| beat | core today |
|---|---|
| "no seize/contest on the round it arrives" | **live** — `State.ambush_arrived_round`, consumed by `score.rs` (see the contract at `deployment.rs:2389`), parity-checked at `bin/parity.rs:76` |
| re-entry onto the table | `deployment::arrive_unit` (`deployment.rs:2394`) exists — and has **exactly one caller in the whole repo, a test**: `core/nml-core/tests/deployment.rs:1914` |
| putting a live unit into reserve | **absent** — the only non-test write to `State.dormant[i]` is `deployment.rs:2402`, and it writes `false` |
| creating a unit mid-game | **absent** — S5; `dormant_models` / `dormant_wounds` are only ever *read back*, never minted |
| the 12" edge frame | **absent** — `arrive_one` searches inside a **`Rect` zone**; "fully within 12" of ANY edge" is a frame (board minus inner rect), not a rect |

Three consequences that decide this note:

1. **The core imports dormancy, it never produces it.** `dormant`, `dormant_models`, `dormant_wounds` and
   `earliest_arrival_round` arrive through the loader (`io.rs:673-679`, `:751-757`) from the table's recorded state,
   and are zero-initialised at the other two `State` construction sites (`doctrine.rs:154-157`, `mv/step.rs:1174-1180`).
   No rollout step ever flips a unit into reserve.
2. **The live arrival loop is Python, not Rust.** `core/nml-core-py/python/selfplay.py:953-1005` runs the round-start
   arrival (`nml_core.arrive_one` at `:991`, statics via `arrival_reads()`, `nml-core-py/src/lib.rs:1035`) and marks
   ambushers dormant at setup (`selfplay.py:437-447`). The census credits **only** `core/nml-core/src`
   (`rule_universe_census.py:1319`), so nothing added on that side earns the name a layer.
3. **The sibling already declared exactly this gap.** `unit.rs:2920-2926`, merged with the Ambush family port
   (`cf4bd83d`): *"Ambush Re-Deployment: `re_reserve` + `uses_per_game` — the entry's params, read and stamped. The
   once-per-game withdraw beat itself is a future port: an OPTIONAL end-of-activation choice needs a core seam (and a
   policy) this wave does not invent."* Reinforcement's beat is that same withdraw beat **plus** a fresh copy.

## 3. The primitive the core needs

Five pieces. Two mirror parts that exist; three are new.

| piece | file | mirrors |
|---|---|---|
| `UnitStatic.reinforcement` (`within_in`, `once`) from `unit_rule_active(reg, p, "Reinforcement")`, gated `rule_on(rules_epoch, EPOCH_7_TABLE_RULES)` | `unit.rs`, beside `ambush_family_of` | `second_wind_active` |
| `State.reinforcement_used: Vec<bool>` (once per game, and the copy loses the rule — a per-unit flag, because statics are per **profile** and both instances share one) | `state.rs` + 3 construction sites + `PlainLedger` fold (`io.rs`) + `parity.rs` + `tokens.rs` | `storm_used` |
| `withdraw_as_destroyed(st, i, round)`: `alive → 0`, positions cleared, `dormant = true`, `dormant_models = model_count`, `dormant_wounds = wounds_max`, `earliest_arrival_round = round + 1` | `deployment.rs` | **new** — and the exact inverse of `arrive_unit`'s contract, which restores the **parked** strength, never a fresh one (`deployment.rs:2380-2383`) |
| an edge-frame arrival zone for `arrive_one` | `deployment.rs` + the py binding | **new** |
| a round-start arrival driver inside the core | `sim.rs` round-start block (`:4266-4269`, where `growth_round_start` ticks) or `rollout.rs` | **new** — today this loop exists only in `selfplay.py` |

**Why this is not a wiring job.** Two of the five are new state transitions the core has never had, and the fourth
changes `deployment::arrive_one`'s parameter list — which is shared with `nml-core-py/src/lib.rs:2452` and
`tools/deployment_gate.py`. That is precisely the **widened shared signature** the wave rules forbid inside a family
PR (`RULES_WAVE4_2026-09-06.md` §7.5). Estimated production cost is well past the 120-line cap, across
`deployment.rs`, `state.rs`, `io.rs`, `unit.rs`, `tokens.rs`, the py binding and `selfplay.py`: at least two PRs, one
of which is a signature change that has to go first and alone.

**The seam is worth more than this one name.** The same withdraw-and-recreate primitive closes `Spawn` (S5, the plan's
own entry), the `Ambush Re-Deployment` withdraw beat quoted above, and the table's shared mid-game creation path
(`main.gd:10329-10334` builds the copy through `opr_army_manager.create_runtime_unit(..., "reinforcement")`, the same runtime-unit path the Spawn/Split family takes). Funding it for one name is a bad
trade; funding it as the S5 seam is not.

## 4. Census impact — measured, and the ceiling

Base at `caadd053`: **`core-ported 408/450`, `encoder-slot 411/452`, `all-layers 398/452`.**

Row `Reinforcement` (occ 4; gf 2, aof 2), measured in both systems: registry primitive `Reinforcement`,
`mechanics_entry: true`, `core: MISSING`, `cond_ap_param: false`, **`encoder_slot: false`**.

So even a complete, honest port is worth **`core-ported` 408 → 410 (+2) and `all-layers` +0**. The v6 vocabulary
(`data/encoder_rule_vocab_v1.json`, `comment_v6`) appended its 226-name `unit2` band for *"every core_ported rule name
that had no encoder slot"* — Reinforcement was not core_ported on 06.09., so it holds no slot, and whether a newly
ported name may be appended to `unit2` is the encoder-slot decision memo's call, not this note's.

**This PR is docs only and claims `core-ported` +0, `all-layers` +0.**

## 5. The rejected alternative — the evidence-only stamp

Add `"Reinforcement"` as a fifth arm of `unit.rs::ambush_family_of` and stamp the mechanics entry's params. The census
returns **PORTED on a bare name-token hit** (`rule_universe_census.py:832`, before the `CONSUMED_PARAM_KEYS` check
that produces STAMPED at `:836`), so this scores `core-ported +2` for roughly 25 lines.

Rejected. All six params of the mechanics entry (`trigger`, `redeploy`, `within_in`, `timing`,
`no_objective_on_arrival`, `once`) would have no reader anywhere; the census would then report the core as reading a
rule of which it models none of the ~400 table lines in §1; and the +2 lands on a number that is not the wave's goal
metric, while `all-layers` stays flat either way. Declaring it in the PR title would make it honest, not useful.

**One word from the maintainer flips this** — the arm is ~25 lines and the note above says exactly where it goes.

## 6. Test plan, when the port is funded

New file `core/nml-core/src/tests/deployment/reinforcement.rs` (the census excludes `src/tests/`, so no test literal
can credit the name). RED first, each test failing on the branch **before** the port for a behavioural reason:

1. `a_shaken_carrier_withdraws_as_destroyed_and_parks_a_fresh_copy` — after the withdraw, `alive == 0`,
   `dormant == true`, and `dormant_wounds == wounds_max` (**not** the parked strength — the `arrive_unit` contrast).
2. `the_copy_arrives_within_twelve_inches_of_an_edge` — the returned spot is inside the frame, base fully within.
3. `the_copy_cannot_seize_on_the_round_it_arrives` — `ambush_arrived_round == round`, `score.rs` yields no capture.
4. `the_copy_does_not_reinforce_a_second_time` — `reinforcement_used` blocks the second trigger.
5. `an_epoch_6_record_never_reinforces` — `rules_epoch: 6` replays byte-identical.
6. `the_ledger_restores_a_reinforcement_already_spent_on_the_table` — the `io.rs` fold.

Table side is already covered; the recorder must export the spent flag beside the ledgers it already writes, the same
correction the Delayed Action note makes for its own stamp (`DELAYED_ACTION_DESIGN_2026-09-07.md` §2).

## 7. What this note does NOT do

- **No code and no census movement.** It replaces a PORT verdict with a costed DESIGN, and names the cheap dishonest
  alternative so it can be chosen deliberately rather than by accident.
- **No decision on Spawn.** It only shows that Spawn, `Ambush Re-Deployment`'s withdraw beat and this name share one
  seam, and that the seam should be priced once.
- **No cross-system text check.** The snapshot is gf + aof; the gff/aofr/aofs wording is unverified here.
