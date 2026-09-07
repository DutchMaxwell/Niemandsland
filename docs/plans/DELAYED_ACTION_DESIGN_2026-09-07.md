# Delayed Action — the Pass-Turn primitive the fast core is missing

Measured at `5fc1f7a5` (origin/main, 2026-09-07) with one run of `core/nml-core-py/tools/rule_universe_census.py
--books <private snapshot>` (89 books, 452 names). The research verdict this note builds on is PORT: the name *is* the
Pass-Turn primitive it is mapped to (private research index, kept outside this repo).

## 1. What the rule does on the table

Book text, word-identical in all 11 snapshot books that carry it (6 gf, 5 aof), at book level in each book's
`specialRules[]`:

> "Once per round, if your opponent has more units left to activate than you, then this model's unit
> may pass its turn instead of activating (may still be activated later)."

Four clauses, all four already enforced on the table: once per round **per carrier unit** (`DELAYED_ACTION_STAMP`,
`solo_controller.gd:7950`), **strictly** more (`delayed_action_surplus`, `:7959` — antisymmetric, so two carriers
cannot pass at each other forever), pass **instead of** activating (`main.gd:1499`), still activatable later (no
`is_activated` write on the path).

## 2. Correction to the finding this job was briefed on

The finding said `_solo_pass_turn` (`main.gd:1484-1526`) "changes no state". It changes no **activation** state —
deliberately, that is the rule's last clause — but the pass path writes state twice:
`SoloController.delayed_action_stamp` sets `unit_properties["delayed_action_round"]` (`main.gd:1531`, `:1553`), and
`_solo_pass_turn` moves `_solo_pending_replies`. The table half is shipped and stateful (wave 5, 2026-08-01). The real
table-side gap is one layer down and measurable: **`AiActRecorder._ledger_of` (`act_recorder.gd:403-425`) does not
export the stamp.** It exports `hit_and_run_round`, `vs_mark_round`, `growth`, `second_wind_used`, `storm_used` —
every other per-unit ledger the table keeps between activations — and not this one. A core that grew the stamp would
therefore replay every act with the pass unspent and could grant a second one in a round the table already closed: the
`#493`/`#498` divergence shape. The ledger row ships with the core field.

## 3. The primitive the core needs

Core state models a **spent** activation and nothing else (`state.rs:392`, `activated: Vec<bool>`), and the
alternation is strict (`rollout.rs:142,163,189` — `other_player` after every step, the only escape a dry side). No
read of the name or of "Pass Turn" exists anywhere in `core/nml-core/src`, only a docstring naming the gap
(`sim.rs:1358`) — so `core: MISSING` in both systems is correct.

**Chosen shape: a per-unit round stamp plus a pass STEP in the rollout alternation** — three pieces, two of them
mirroring parts that already exist:

| piece | file | mirrors |
|---|---|---|
| `UnitStatic.delayed_action_active` from `unit_rule_active(reg, p, "Delayed Action")` | `unit.rs:4142` block | `second_wind_active` |
| `State.delayed_action_round: Vec<i64>` (-1 = never; no reset, `== state.round` self-clears) | `state.rs` | `hit_and_run_round` |
| the pass step in `rollout_traced`'s loop, gated on `rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES)` | `rollout.rs:150` | — new |

**Why the rollout and not a root action.** Delayed Action is an activation-ORDER rule, and the only place the core
orders activations is the rollout loop. `sim.rs::resolve_with` applies ONE activation and is the replay/parity path —
a pass is not an activation, produces no act record on the table and must not appear there. A root-level pass
`Candidate` would need a new act kind on both sides with no recorded table act to gate it against: a second beat (§7),
not this port.

**Why no `CONSUMED_PARAM_KEYS` row for "Pass Turn".** It would credit future Pass-Turn names off the primitive token,
and Delayed Action is measurably the primitive's only user in the snapshot — the row would buy nothing and ride ahead
of its reader (house rule 6). The core reads the literal name, the `second_wind_active` precedent; a second user
(Combat Hesitation, GF Advanced p.41) costs one `||`.

**Cost.** ~95 production lines: 3 `State` construction sites (`io.rs:704`, `doctrine.rs:171`, `mv/step.rs:1206`), one
field each in `state.rs`/`unit.rs`, the `PlainLedger` field + fold in `io.rs`, ~45 lines of pass step and doc in
`rollout.rs`, ~5 in `act_recorder.gd` — under the 120 cap, so core and table ship as ONE PR.

## 4. Two things the design fixes on purpose

**The guard budget.** `rollout_traced`'s backstop is `(units + 2) * rounds_left` loop turns, sized for activations
alone. A pass spends a turn without spending an activation, so a carrier-rich army would trip `Stop::Guard` — "a logic
error, never the rule path" — on the rule path. The port adds `units * rounds_left` headroom, the exact bound (at most
one pass per carrier per round, guard (b)), **inside the same epoch gate**, so a `rules_epoch < 7` record keeps its
byte-identical budget.

**The AI's taste layer is not ported — declared, not silent.** The table passes only when its most valuable
un-activated unit stands inside the reach of an enemy that has not yet committed (`solo_controller.gd:8050-8114`:
`delayed_action_threatened` + `_has_los` + `nearest_melee_gap_in`). The core's rollout is the cheap greedy playout: it
passes whenever the **rule's own condition** stands and picks the carrier with the highest `alive` — the
simplification the Second Wind port declared for `_plan_ev_of` (`sim.rs:1331`ff). The book text carries no threat
clause, so this is the rule minus a heuristic, not a weaker rule.

## 5. Census impact — predicted, to be measured against

Base at `5fc1f7a5`: `core-ported 404/450`, `all-layers 398/452`, `encoder-slot 411/452`. The row `Delayed Action` (gf
+ aof) reads `core: MISSING` / `named in Rust docs (sim.rs:1358)` today, with registry `Pass Turn`, a mechanics entry
and a unit encoder slot in both systems; it flips to `core: PORTED`, and nothing else moves — measured, it is the only
row in either system whose primitive is `Pass Turn`, and both data layers already carry it
(`rules_mechanics_gf.json:5124` ff., `uses_per_round: 1`, `requires_opponent_surplus: true`), so the PR touches no
registry JSON. **Claim: `core-ported` 404 → 405 (+1), `all-layers` 398 → 399 (+1).**

## 6. Test plan — RED first, both sides

New file `core/nml-core/src/tests/rollout/delayed_action.rs`, wired with `#[path = "tests/rollout/mod.rs"]` (the
`tests/sim` pattern; the census excludes `src/tests/`, so no test literal can credit the name). The RED fixture
**compiles on the branch before the port** — it names no new symbol: statics come from the production path
(`UnitStatic::build_for` over a profile carrying `special_rules: ["Delayed Action"]` and the faction folder
`human_inquisition`, so the shipped registry data resolves the carrier), and the assertion reads
`State.activated` alone.

1. **`a_carrier_passes_instead_of_activating_when_the_opponent_has_more_left`** — player 1 holds one un-activated
   carrier, player 2 three units, one spent as the opening action; `tail_cap_p2 = 1` truncates the rollout mid-round
   so the activation ORDER is observable at all. Before: the carrier is `activated` after the first alternation step.
   After: it is not, and player 2's second unit is. **The RED is a behavioural assertion, not a compile error.**
2. `the_pass_is_refused_without_the_surplus` — equal counts, the carrier activates (guard (a)).
3. `a_carrier_passes_at_most_once_per_round` — second offer refused (guard (b)).
4. `an_epoch_6_record_never_passes` — `rules_epoch: 6`, byte-identical to today's alternation.
5. `the_ledger_restores_a_pass_already_spent_on_the_table` — an act whose `ledger.delayed_action_round` equals the
   round replays with the pass gone (`io.rs` fold).

Table side: `test/rules_registry_test.gd` and `test/solo_controller_test.gd:2831-2917` already cover the rule; the
recorder addition asserts beside the existing `_ledger_of` coverage.

## 7. What this port does NOT do

- **No root-level pass.** The planner still cannot CHOOSE to pass for its real next move, only imagine passes
  inside the playout; closing that needs a pass act on both sides, with no recorded table act to gate parity
  against. Own beat.
- **No encoder change.** The name already holds a unit slot; `tokens.rs` is untouched, so no board row widens and
  no recorded corpus is invalidated.
- **No cross-system text check.** The snapshot covers gf + aof only, so the "word-identical in all 21 books" claim
  at `solo_controller.gd:7930` stays unverified for gff/aofr/aofs.
