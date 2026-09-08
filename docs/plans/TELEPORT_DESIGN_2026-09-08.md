# Teleport / Teleport Aura / Ethereal — the discretionary reposition on table and core (design note)

Date: 2026-09-08. Scope: DESIGN only. Names covered: **Teleport**, **Teleport Aura**,
**Ethereal** — `docs/plans/RULES_WAVE5_MAP_2026-09-07.md` group (a). Template:
`docs/plans/FEAT_DESIGN_2026-09-08.md` and `docs/plans/REINFORCEMENT_DESIGN_2026-09-07.md`.
Companion research note (private): the wave-4 verdict that the port is BLOCKED until a
recorded teleport decision and a placement policy seam exist. This note designs both seams.

## 1. The rule texts and their common shape

| name | text (verbatim, snapshot books) | registry params |
|---|---|---|
| Teleport | "Once per activation, before attacking, you may place this model anywhere fully within 3\" of its position when using Advance/Charge actions, or fully within 6\" of its position when using Rush actions." | `advance_bonus_in: 3.0, rush_bonus_in: 6.0` (primitive: `Teleport`) |
| Teleport Aura | "This model and its unit get Teleport." — a pure grant | `grants: "Teleport"` (primitive: `Aura Channel`) |
| Ethereal | "Once per activation, before attacking, place this model anywhere fully within 6\" of its position. This model moves -6\" when using Advance, and -6\" when using Rush/Charge." | `advance_bonus_in: 0.0, rush_bonus_in: 0.0, advance_mod: -6, rush_mod: -6` (primitive: `Teleport`) |

Common shape — the primitive is a **discretionary reposition**:

- **Latch: ONCE PER ACTIVATION** (resets every activation — unlike the FEAT family's
  `uses_per_game`, nothing persists across rounds).
- **Slot: BEFORE ATTACKING** — the activation-order slot is "after the move/charge
  resolves, before the strike". It is an EXTRA placement, not a replacement of the move;
  the anchor is the model's own position (the band-bonus approximation used today implies
  the post-move position).
- **Band-dependent cap:** 3" on Advance/Charge actions, 6" on Rush actions (Teleport);
  Ethereal's reposition is flat 6" and its text is imperative ("place"), not optional
  ("you may place").
- **Dice-free:** no roll anywhere, hence no tray — the existing activation-beat trays
  (Crossing Attack, Surprise Attack) are DICE trays and do not fit.
- **Who chooses:** the acting side. Teleport is discretionary ("may"); Ethereal is
  mandatory placement, which makes Ethereal the *smaller* policy problem (no "should we?",
  only "where?").

The registry today carries only the band magnitudes (3/6 bonus; -6/-6 mods). The
reposition itself is not a parameter — it is an action, and no act token or ledger row
records it. That is the gap.

## 2. What the TABLE does today (measured on this commit)

| aspect | state | evidence |
|---|---|---|
| Teleport reposition, human | **manual drag** — the player places models by hand; nothing enforces the 3"/6" cap or the once-per-activation latch | no rule handler: `rg -i teleport scripts/main.gd` hits only glide-animation comments (main.gd:4877, :7646-7675, :8105, :9499) |
| Teleport, solo AI | **band approximation only** — `tele_rule` from `RulesRegistry.unit_rule_active` or the first primitive-`Teleport` DATA alias (Ethereal); `advance += t_adv; rush += t_rush; charge_reach += t_adv` with params 3.0/6.0, once per activation "by construction" (a move is chosen once) | scripts/solo/solo_controller.gd:1729-1746 |
| Ethereal -6/-6 mods | **live** — the "Teleport" primitive joins the registry band pass so `advance_mod`/`rush_mod` fold into the bands; Teleport's own bonus params deliberately do NOT ride this pass | scripts/movement_range_controller.gd:142-166 (NML-1121); second AI read at solo_controller.gd:5629-5637 |
| Teleport Aura | **live via base** — epoch-6 aura fold grants "Teleport" onto the unit; the aura name is known to the core's Aura Channel name table | core/nml-core/src/unit.rs:2331 |
| Core reader for any of the three | **none** — the gap is deliberate: the GDScript adds `max_activation_advance_bonus_in` (Bounding/Quick/Teleport) on top of the advance band, "which this crate does not model at all" | core/nml-core/src/menu.rs:278-284 |

Closest existing table actions:

- **Ambush Re-Deployment** (main.gd:1225-1258): the nearest *discretionary* pick-up — but
  it is end-of-activation and round-delayed, not a before-attacking placement, and the
  repo already declined to invent an optional-choice policy for it (the same blocker the
  research note cites).
- **Rapid Ambush arrival** (main.gd:1170-1219): a placement search with a legal-landing
  predicate and a "may" that can be passed up *with a log line* — the closest shape for
  "where would the AI land?".
- **Reinforcement arrival (#803)** — the replay precedent: its driver only fills in what
  the record already carries (`reinforcement_used` ledger, act_recorder.gd:439). Teleport
  has no recorded state at all — that is the contrast.

## 3. The core seam proposal

**Action: `Reposition` — a dice-free, once-per-activation candidate in the activation
menu, slotted AFTER the move step and BEFORE the attack step.** (Not *instead of* the
move: the rule text is an extra placement, and the band approximation already treats the
move as taken.)

- **Candidate shape:** `Reposition { unit, from, to, band }` where `band` ∈ {advance,
  charge → 3", rush → 6"} is inherited from the action the activation chose; Ethereal is
  always 6" (params `advance_bonus_in: 0.0` / `rush_bonus_in: 0.0` must NOT be read as
  "no reposition" — the reposition cap for Ethereal is the flat 6" of the text, keyed by
  the rule NAME, not by the bonus params).
- **Placement policy — bounded, no search explosion:** score a fixed candidate set, not
  a free-space search. Exactly three probes per bearer, each landing on an *existing*
  point the planner already knows:
  1. **nearest objective within reach** — the closest objective centroid inside the cap
     circle (capture/hold value);
  2. **out of melee threat** — the point on the cap circle away from the nearest enemy
     contact (escape value);
  3. **into cover** — nearest known cover point inside the cap (defense value).
  Score = the planner's existing move-EV terms evaluated at `to` (same EV vocabulary the
  move step uses); take max, with the "may" gate = take the action only if the best
  score beats staying by a fixed margin. Three probes, no flood-fill, no LOS re-probing
  (menu.rs already documents that per-point sight does not exist in the state — the
  policy must not need it).
- **Latch:** `teleport_used_this_activation: bool` per unit, cleared at activation start.
  On `State` as a per-unit flag (or a round-indexed stamp like Delayed Action's shape);
  reset — not spend — is the semantics: it refills every activation.
- **Recorder / replayer:** an act token `rep!(teleport)` carrying the landing centroid
  (the `to` of the chosen candidate) plus the used-flag. The table's recorder
  (`_ledger_of`) gains a `teleport` block: `{"used": bool, "to": Vector2}` read off a new
  `unit_properties["teleport_used_<snake>"]` / placement key the table handler writes.
  io.rs folds it next to `storm_used` (io.rs:215-218, :844); the replay applies the
  placement and the latch. The centroid (not per-model offsets) keeps the token small;
  the table applies its own formation snap around it, the core applies the same snap
  rule — one snap function, defined once, both sides call it.
- **Epoch gate:** like `storm_of` (core/nml-core/src/unit.rs:2694), gate the token and
  the fold on the CURRENT rules epoch — older recordings never carry `teleport`, so
  replay bytes below the epoch are untouched.
- **Census by NAME:** "Teleport" (gf+aof), "Teleport Aura" (pure grant, satisfied when
  its base reads live), "Ethereal" (aof) — three names, counted by display name exactly
  as the map does. Aliases resolve to the primitive but the census stays on names.

## 4. The smallest honest first PR on each side — and the order

**Recommendation: TABLE FIRST, then core — because a record must exist before a replay
can consume it.** A core-first PR would need a synthetic record (a hand-written ledger
with a `teleport` block) to test against; that tests the core against an imagined table,
and the first real recording would then be the first byte-identity test — the exact
failure mode the research note documents (both directions diverge). Table-first gives
recordings that carry real placements before the core ever reads them, and the RED test
on the core side is then a plain replay of a real record.

- **PR 1 — table: handler + solo policy + record (≤ 80 lines GDScript).** A
  before-attack beat: if the activation's action is Advance/Charge/Rush and the unit
  carries the rule and the latch is unset, the solo controller probes the three-bounded
  policy above, applies the placement (glide, per the house rule that nothing
  teleports-invisibly), sets `unit_properties["teleport_used_<snake>"]` + the placement
  key, logs (`_rule_note`, rules-must-log), and the recorder's `_ledger_of` writes the
  `teleport` block. Humans keep their manual placement; the beat only *validates* the
  cap when the flag is written.
- **PR 2 — core: candidate + replay (≤ 120 lines).** `State` latch + io fold +
  `rep!(teleport)` + epoch gate + the `Reposition` candidate in the activation menu with
  the three-probe policy, driven off the recorded landing centroid when one exists
  (replay) and off the policy when the act is live-side (solo parity). RED tests: replay
  a real recorded activation with a teleport → carrier lands at the recorded centroid,
  latch set; a second activation in the same recording → latch unset (reset semantics);
  an epoch-below recording → no `teleport` key, byte-identical.

The Aura needs no PR of its own (pure grant — it reads live as soon as the base name
does).

## 5. Open decisions for the maintainer (max 3)

1. Anchor = post-move position (as the band approximation implies) vs pre-move —
   **recommend post-move** (matches the only existing automated read, one behavior, no
   second interpretation to keep alive).
2. Policy margin for the discretionary "may": fixed EV-margin vs always-take —
   **recommend fixed margin** (a reposition is not free; the Ambush Re-Deployment
   precedent shows a pass-up must be logged, and a margin makes the pass-up principled).
3. Order table-first vs core-first — **recommend table-first** (a record must exist to
   replay; core-first forces a synthetic ledger, §4).

## 6. Risks

- **Replay byte-identity:** a new ledger key in old recordings changes replay bytes.
  Mitigation: epoch gate like `storm_of` (unit.rs:2694); `rep!(teleport)` only under the
  new epoch bit.
- **Planner branching:** a `Reposition` candidate per bearer per activation adds menu
  entries. Mitigation: bounded candidate set (three probes, one candidate per bearer —
  not per landing spot), and the "may" margin prunes it to a no-op when EV does not
  improve.
- **Table/core divergence:** the table snaps a formation around the centroid; if the
  core snaps differently, parity fails on the first multi-model carrier. Mitigation: one
  shared snap rule, defined in the core, consumed by the table (the bands already flow
  recorded-state-first, io.rs:109-114).
- **The aura grant:** "Teleport Aura" grants the base name; if the loader's grant path
  and the census ever disagree about when the grant lands, the aura counts GRANT-MISSING
  while its base fires (or vice versa). Mitigation: census the aura off the base's live
  read, not off a second independent check.
