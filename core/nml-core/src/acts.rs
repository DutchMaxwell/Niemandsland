//! Loader for the ACT corpus written by `AiActRecorder` (scripts/solo/
//! act_recorder.gd): line 1 is the header
//! `{"kind":"header","profiles":{...},"terrain":{...}|null,"knobs":{...}}`,
//! every line after it is one ACTIVATION — the full input the search read plus
//! the pick it returned and the search trace (`trace.menus` is the menu oracle
//! this milestone's gate replays).
//!
//! It reuses `io.rs`'s plain-state reader wholesale: the act corpus writes the
//! SAME `BattleSim.state_to_plain` object, only with the M2-0c/M2-0d gate reads
//! stamped into each unit (`bands`, `shroud`, `charge_no_difficult`,
//! `charge_probe_r`). Unit order is document order, which is what `Ordered<T>`
//! preserves — see the note on `roster_of`.

use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::rc::Rc;

use serde::Deserialize;

use crate::io::{roster_of, spawn_templates_of, state_of, Ordered, PlainState};
use crate::menu::Candidate;
use crate::state::{Profile, ProfileCache, Profiles, Roster, State};
use crate::terrain::{PlainTerrain, Terrain};

/// The header's `"knobs"` object — `AiActRecorder._header_line`
/// act_recorder.gd:126-133. Search settings, recorded so a replay never guesses
/// which A/B arm produced the line.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct Knobs {
    #[serde(default)]
    pub top_k: i64,
    #[serde(default)]
    pub horizon: i64,
    #[serde(default)]
    pub tail_cap_p1: i64,
    #[serde(default)]
    pub tail_cap_p2: i64,
    /// Opponent-model diagnosis (c) — every root rollout stops RIGHT AFTER the opener (the candidate's
    /// own activation and its Coordinate hand-off) and is priced there, mid-round, by the same blend +
    /// net leaf: no scripted opponent reply, no scripted tail. A tail cap cannot say this (0 = no cap,
    /// 1 = one scripted step). Research knob, default OFF (byte-identical).
    /// Inert under `search_mode` tree: a tree leaf is priced at its own state already (tree.rs).
    #[serde(default)]
    pub leaf_opener_only: bool,
    #[serde(default)]
    pub imagined_round_end: bool,
    #[serde(default)]
    pub depth_discount: f64,
    #[serde(default)]
    pub seat_mode: i64,
    #[serde(default)]
    pub playout_margin: f64,
    #[serde(default)]
    pub playout_rich: bool,
    /// Opponent-model diagnosis (a) — the opponent's FIRST reply inside every root rollout (the step
    /// right after the opener) is the planner's own one-ply search for the opponent at the grade
    /// `reply_top_k` / `reply_horizon`, the leaf hook (when wired) priced from the opponent's seat,
    /// instead of the scripted four-option brain; the rest of the tail stays scripted
    /// (`plan::Search::reply_pick`). Research knob, default OFF (byte-identical).
    /// Inert under `search_mode` tree, which runs no rollout: its opponent nodes search the full menu (tree.rs).
    #[serde(default)]
    pub reply_by_net: bool,
    /// `reply_by_net`'s rollout budget; `<= 0` = `plan::REPLY_TOP_K` (3).
    #[serde(default)]
    pub reply_top_k: i64,
    /// `reply_by_net`'s horizon in rounds; `<= 0` = `plan::REPLY_HORIZON` (1).
    #[serde(default)]
    pub reply_horizon: i64,
    /// `reply_by_net`'s nested POOL cap: `> 0` = the opponent's nested reply search prices at most this many
    /// rows, the top of ITS prefilter order, with no per-unit coverage, patient-advance or second-wave row
    /// on top (`plan::Search::pool_cap`). `<= 0` = the four guarantees (#1705's nested pool). The root
    /// search's own pool is never capped. Read only with `reply_by_net` on.
    #[serde(default)]
    pub reply_pool_cap: i64,
    /// `reply_by_net`'s nested MENU: on = the opponent's nested reply search offers the scripted brain's own
    /// four-option menu (`playout::Policy::policy_candidates`) on the playout seams (no `route_root` table
    /// move) instead of the full root menu, and the reply it picks is played on those seams. Off = #1705's
    /// full root menu. Read only with `reply_by_net` on.
    #[serde(default)]
    pub reply_menu_restricted: bool,
    /// `BattleSim.cast_phase_enabled()` — NML_SIM_CAST.
    #[serde(default)]
    pub seam_cast: bool,
    /// `BattleSim.spacing_enabled()` — NML_SIM_SPACING.
    #[serde(default)]
    pub seam_spacing: bool,
    /// NML-1073 M4-7 — NML_SIM_PATH, the tier-2 path seam of the imagination.
    #[serde(default)]
    pub seam_path: bool,
    /// NML-1157 — `Seams::hero_last`: a combat intent aimed at a joined hero
    /// resolves to its HOST. Absent from every corpus recorded before it, so the
    /// default is OFF and nothing replays differently.
    #[serde(default)]
    pub hero_last: bool,
    /// NML-1157 — `Seams::cast_fold`: the CASTER is read off the activating
    /// chain, not off the host alone. Absent from every corpus recorded before
    /// it, so the default is OFF and nothing replays differently.
    #[serde(default)]
    pub cast_fold: bool,
    /// NML-1073 M3-5 — whether the CALLER wires `state["charge_illegal"]` at
    /// all. The arena does (solo_controller.gd:3002), `tools/core_selfplay.gd`
    /// never does, and both menu sites skip the gate outright for a caller that
    /// does not (`illegal_cb.is_valid()`, ai_planner.gd:1024/1308). Absent from
    /// every recorded header, so the default is `true` and no corpus moves; the
    /// Godot-free harness writes `false` because its GDScript twin is gateless.
    /// The act line records the same bit per activation as `charge_gate`.
    #[serde(default = "yes")]
    pub charge_gate: bool,
    /// NML-1157 — `Tuning::target_units`: the MENU treats a joined Hero as part
    /// of its host (GF v3.5.1 p.14) and offers the charge the unit can REACH
    /// beside the one it scores best. A MENU knob, not a seam: it changes what
    /// the search may choose, never how a chosen act resolves, so a recorded
    /// act replays byte-identical either way. Absent from every corpus recorded
    /// before it, so the default is OFF and no menu moves.
    #[serde(default)]
    pub menu_targets: bool,
    /// Wave 6 (`lead/menutargets`) — `Tuning::holders`, the MENUHOLDERS leg:
    /// the menu also offers the best shoot and charge against an enemy that
    /// holds or contests an objective not ours (within 3", owner 0 counts as
    /// not ours) or has not activated this round, when that target differs
    /// from the max-EV pick. A MENU knob, not a seam. Absent from every corpus
    /// recorded before it, so the default is OFF and no menu moves.
    #[serde(default)]
    pub menu_holders: bool,
    /// Wave 6 (`advancek`) — `Tuning::advance_k`, the MENU leg that offers the
    /// safe-advance frontier's top-k destinations instead of the single best.
    /// A MENU knob, not a seam: it widens what the search may choose and never
    /// changes how a chosen act resolves. Absent from every corpus recorded
    /// before it, so the default is 1 — byte-identical to today's one candidate.
    #[serde(default = "one")]
    pub menu_advance_k: usize,
    /// aifix action-space lane (finding 7, C1) — `Tuning::all_targets`: how many EXTRA HOLD+shoot rows (one per
    /// visible enemy in range, best EV first) the menu appends after the single max-EV one. 0 = off, every
    /// recorded corpus and shipped game byte-identical.
    #[serde(default)]
    pub menu_all_targets: usize,
    /// aifix action-space lane (finding 7, C3) — `Tuning::advance_obj_shoot`: ADVANCE rows that walk toward the
    /// nearest objective WITH a shot on a target that stays in range after the move. Default off.
    #[serde(default)]
    pub menu_advance_obj_shoot: bool,
    /// aifix F6 (inventory row M20, p.9 "has a clear path to reach it") — `Tuning::charge_needs_path`: a CHARGE row is
    /// kept only when the mover's nearest model can walk to the target within the live charge band (containers, units
    /// in the way). Default off = byte-identical.
    #[serde(default)]
    pub charge_needs_path: bool,
    /// Wave 6 (`rushk`) — `Tuning::rush_k`, the PLAYOUT leg: how many of the
    /// nearest objectives the rollout's greedy brain rushes instead of only the
    /// nearest. A MENU knob, not a seam: it widens what the search may choose and
    /// never changes how a chosen act resolves. Absent from every corpus recorded
    /// before it, so the default is 1 — byte-identical to today's single RUSH.
    #[serde(default = "one")]
    pub playout_rush_k: usize,
    /// NML-1073 M5 D1-B4b — `Seams::hero_attach`, carried in the header the way
    /// every other seam is. Absent from every corpus recorded before it, so the
    /// default is OFF and nothing replays differently.
    #[serde(default)]
    pub hero_attach: bool,
    /// NML-1073 M5 D5-1 — `Seams::charge_landing`, carried in the header the
    /// way every other seam is. Absent from every corpus recorded before it, so
    /// the default is OFF and nothing replays differently.
    #[serde(default)]
    pub charge_landing: bool,
    /// NML-1073 M5 D6a-B4 — how a volley counts its shooters. `"unit"` is the
    /// default and today's behaviour (every ALIVE model of the unit fires);
    /// `"model"` is the table's own rule, per model and per weapon. Absent from
    /// every corpus recorded before it, so the default replays byte-identical.
    #[serde(default)]
    pub sighting: Sighting,
    /// NML-1073 M5 D5-2 — `Seams::movement`, carried in the header the way every
    /// other seam is. Absent from every corpus recorded before it, so the
    /// default is OFF and nothing replays differently.
    #[serde(default)]
    pub movement: bool,
    /// NML-1160 — WHICH SIGHT the menu and the resolve read. `false` is every
    /// corpus recorded before it: a self-play state carries `los_pairs` from
    /// `SchoolTerrain.los_blocked` (a unit-CENTRE to unit-CENTRE probe,
    /// `tools/core_selfplay.gd:675`) and NO per-unit `los`, so
    /// `AiPlanner._best_shoot`'s only sight test (`BattleSim.sees`) never
    /// refuses a target and the resolve silently drops the volley instead. An
    /// ARENA recording is the other way round: `BattleSim.capture` fills `los`
    /// from `SoloController._has_los` and stamps no matrix at all. `true` gives
    /// the trainer the arena's own answer — `sight::sight_matrix` on both seams
    /// — and `Seams::los_model` then keeps a clone from rewriting it with the
    /// centre probe, exactly as `clone_state` inherits `los` untouched.
    #[serde(default)]
    pub los_model: bool,
    /// NML-1161 — `Tuning::shoot_los`: the menu's shoot leg asks the RESOLVE's
    /// whole question (`sees` AND `_los_clear`) instead of `sees` alone. Absent
    /// from every recorded header, and the default is OFF, so every corpus
    /// replays with the GDScript's own menu.
    #[serde(default)]
    pub menu_los: bool,
    /// W1 (AUDIT_rulebook_flanks_2026-09-02, top-1) — `Tuning::wide_shoot`: the
    /// menu offers ADVANCE+shoot, the leg `AiPlanner.candidates_wide` has
    /// carried since 16.08. and `menu::candidates` never had. A MENU knob, not
    /// a seam: it changes what the search may choose, never how a chosen act
    /// resolves, so a recorded act replays byte-identical either way. Absent
    /// from every corpus recorded before it, so the default is OFF and no menu
    /// moves.
    #[serde(default)]
    pub menu_wide: bool,
    /// W1, the RESOLVE half of `menu_wide` on its own. `Seams::moved_shoot` is
    /// a PERMISSION to answer a moved shooter's volley, not a rule: with no
    /// menu offering that pairing it changes nothing. It needs its own bit
    /// because a PER-SEAT A/B plans the acting seat on ITS core and RESOLVES
    /// every activation on the BASE one (`selfplay._play_round`) — so a deep
    /// seat playing the wide menu hands its ADVANCE+shoot to a base core that
    /// would decline it (`Unsupported::MovedShootLos`), and the whole game
    /// dies. `plan::seams_of` ORs it with `menu_wide`, so a single-core caller
    /// never has to think about it. Default OFF: the decline stands.
    #[serde(default)]
    pub moved_shoot: bool,
    /// NML-1152 S3 — `Seams::move_rigid`, the RED switch that keeps ADVANCE and
    /// RUSH on the rigid translation while `movement` still routes CHARGE.
    /// Absent from every corpus, so the default is OFF.
    #[serde(default)]
    pub move_rigid: bool,
    /// The search routes its ROOT moves — the menu's own resolve and every
    /// rollout's opening move — per model on the plain ADVANCE/RUSH arm
    /// (`Seams::plain_only`) and plays every deeper playout move rigid, whatever
    /// `movement` says: the measured cheap form of table thinking. A SEARCH knob:
    /// resolves outside the search keep the header's own seams. Absent from every
    /// corpus, so the default is OFF and every search is byte-identical.
    #[serde(default)]
    pub route_root: bool,
    /// NML-1073 M5 D1-B8 — the p.12 DANGEROUS-terrain test. NOT a feature knob:
    /// the test is part of `dice="table"` and defaults ON, exactly the way
    /// `charge_gate` defaults ON. It exists so a gate can switch it OFF and prove
    /// the numbers come back (`--red-no-dangerous`).
    #[serde(default = "yes")]
    pub dangerous: bool,
    /// NML-1073 M5 D5-4 — the RED switch for the attached-hero fold of the
    /// engage test. Unlike `charge_gate`/`dangerous` (rules that were always
    /// live, so an absent knob must default ON to replay old corpora
    /// unchanged), this fold is a NEW behaviour (NML-1129/1132):
    /// `act_recorder.gd:216` only started stamping it once the fold shipped,
    /// and `BattleSim.engage_fold_vintage`/`vintage_knobs()` (shoot_replay_
    /// gate.py) both read an absent key as OFF — the corpus predates the
    /// fold, so the table it was recorded on had none. Defaulting this to ON
    /// made the twin fold a hero's weapons into a pre-fold corpus's charge
    /// EV that the table never counted (found by `policy_gate.py`: qbg_ref
    /// s27 act 21, a CHARGE candidate's melee_ev included the charger's
    /// attached hero's "Dual Shock Whip" though the fold was never live for
    /// this recording). `--red-no-hero-fold` still forces it OFF regardless.
    #[serde(default)]
    pub engage_fold: bool,
    /// DEFECT_LEDGER #12 — the p.10 General Morale Test after a
    /// non-CHARGE activation's dangerous-terrain wounds. A NEW behaviour
    /// like `engage_fold`, not an always-live rule like `dangerous`: an
    /// absent key means the corpus predates the port, so it defaults OFF.
    #[serde(default)]
    pub dangerous_end_morale: bool,
    /// G4R5 R1 F-DANG-TAIL (`EPOCH_73_V36`) - REPLAY GATES ONLY: the unit's act-start `[alive, wounds]` (morale terms)
    /// of an activation whose Dangerous test the gate cut. In-game play never sets it (`knobs_of` has no key). Default None.
    #[serde(default)]
    pub dangerous_replay: Option<(i64, i64)>,
    /// aifix E1 — the imagined next-round opener is the side that finished
    /// activating first (GF p.7), not the smaller head count. Research knob
    /// for the A/B, default OFF (the AI's imagination, not the referee).
    #[serde(default)]
    pub opener_by_finish: bool,
    /// aifix D5 — no reply threat at the game-end boundary (nobody shoots after
    /// round `rounds_total`). Research knob for the A/B, default OFF.
    #[serde(default)]
    pub no_end_threat: bool,
    /// Inventory C02 — the AI's imagined volley lets only the models whose own distance to the target is
    /// within a weapon's range fire it (GF/AoF v3.5.1 p.8), instead of every living model once the nearest
    /// pair is in range. Research knob for the A/B, default OFF (byte-identical).
    #[serde(default)]
    pub fire_in_range_only: bool,
    /// Inventory C12 — a joined hero counts in the unit's size (GF/AoF v3.5.1 p.14): half strength and the
    /// morale / rout thresholds read host + hero, not the host alone. Research knob, default OFF (byte-identical).
    #[serde(default)]
    pub hero_counts_in_size: bool,
    /// Inventory C08 — a Shaken unit "always fails" its morale test, but the failure is still a failed test, so
    /// Fearless (all models) rolls its 4+ and passes half the time (p.13), as the table's dice already do
    /// (`dice::resolve_morale_with_tray`). With the knob on the imagined test of a Shaken Fearless unit fails with chance 0.5
    /// (the dither stands in for the die) instead of for certain. Research knob, default OFF (byte-identical).
    #[serde(default)]
    pub fearless_roll_when_shaken: bool,
    /// Inventory C03 — when a unit loses models, the imagined volley keeps special-weapon bearers alive LAST, as the
    /// table's dice assumption does (`sim::bearer_scaled_attacks`): a weapon carried by fewer models than the unit
    /// fires `per-copy x min(copies, alive)`, only the common weapon shrinks pro rata. Research knob, default OFF.
    #[serde(default)]
    pub casualties_bearers_last: bool,
    /// Inventory C01/C27 — the AI's imagination measures shooting range (and the over-9" modifiers)
    /// base edge to base edge, as the table does, instead of model centre to centre. Research knob
    /// for the A/B, default OFF (byte-identical).
    #[serde(default)]
    pub range_by_base_edge: bool,
    /// aifix D1 — see `Seams::morale_by_probability`. Research knob, default OFF.
    #[serde(default)]
    pub morale_by_probability: bool,
    /// aifix D2 — see `Seams::reply_v2`. Research knob, default OFF.
    #[serde(default)]
    pub reply_v2: bool,
    /// aifix E5 — see `Seams::reply_skip_activated`. Research knob, default OFF.
    #[serde(default)]
    pub reply_skip_activated: bool,
    /// aifix D2c — see `Seams::reply_hold_gate`. Research knob, default OFF.
    #[serde(default)]
    pub reply_hold_gate: bool,
    /// Inventory T03-T06 — see `Seams::reply_threat_by_speed`. Research knob for the A/B, default OFF
    /// (byte-identical).
    #[serde(default)]
    pub reply_threat_by_speed: bool,
    /// NML-1134 — which RULE VOCABULARY this corpus's board rows were slotted
    /// with (`data/encoder_rule_vocab_v1.json`, stamped by `act_recorder.gd`).
    /// THE ONE RULE, and every reader gets it from here: the header says, and a
    /// header that does NOT say was recorded before the stamp existed, which
    /// means version 2. `vocab_version_of_header` is this same default reached
    /// from Python.
    #[serde(default = "legacy_vocab_version")]
    pub rule_vocab_version: i64,
    /// The evolved-hand-eval seam: which `score::score_hand_variant` arm a
    /// call plays. Absent from every corpus recorded before it, so the
    /// default is 0 — today's frozen eval, byte-identical. Threaded like
    /// `seat_mode` (`:44`) and `move_rigid` (`:88-92`): this struct only, read
    /// where `score.rs` and `rollout::blend_score` need it. No arm but 0
    /// exists yet — this field is the registration point, not a new eval.
    #[serde(default)]
    pub eval_variant: i64,
    /// afpoints P1 — the `strength_by_points` eval arm: a unit's presence is
    /// its Army Forge cost times its remaining-wounds fraction instead of its
    /// raw wounds (score.rs `score_hand_variant` arm 5). Research knob for the
    /// afpoints A/B, default OFF. Read at the same `Rollout::blend_score_leaf`
    /// site `eval_variant` is.
    #[serde(default)]
    pub strength_by_points: bool,
    /// Tree search knob: `"oneply"` (default, today's search) or `"tree"`.
    /// Registration only; absent from every recorded corpus, so it replays
    /// byte-identical.
    #[serde(default)]
    pub search_mode: SearchMode,
    /// Tree search knob: the frontier value, today's blend or a playout to the end.
    #[serde(default)]
    pub tree_leaf: TreeLeaf,
    /// Tree search knob: chance edges as expected value or through the dice tray.
    #[serde(default)]
    pub tree_dice: TreeDice,
    /// Tree search knob: the per-decision budget in leaf evaluations.
    #[serde(default = "default_tree_budget")]
    pub tree_budget: i64,
    /// Tree search knob: dice samples per chance edge under `tree_dice: tray`.
    #[serde(default = "default_tree_samples")]
    pub tree_samples: i64,
    /// Tree search knob: children opened per expansion batch.
    #[serde(default = "default_tree_batch")]
    pub tree_batch: i64,
    /// Tree search knob (opponent wide-first batch): at an OPPONENT node the FIRST
    /// expansion batch opens up to `tree_opp_batch` children instead of
    /// `tree_batch`, so the reply set is opened wide before the search descends
    /// below it. 0 (default) = off, `tree_batch` everywhere, byte-identical.
    #[serde(default)]
    pub tree_opp_batch: i64,
    /// Tree search knob (opponent child-order shuffle): at an OPPONENT node the
    /// first batch permutes the candidate order before the take-first-`k`, so a
    /// different subset of the reply set opens first at the same width. `0`
    /// (default) = off, byte-identical; any other value is the shuffle seed.
    #[serde(default)]
    pub tree_opp_shuffle: i64,
    /// Tree search knob: wall-clock safety fallback in ms (0 = off).
    #[serde(default)]
    pub tree_wall_ms: i64,
    /// One-ply pool wall-clock fallback in ms (0 = off).
    #[serde(default)]
    pub pool_wall_ms: i64,
    /// The decision allowance in microseconds, measured from the planner call
    /// (0 = off). Parsed and carried; no search reads it yet.
    #[serde(default)]
    pub deadline_us: i64,
    /// Lab knob (stage-0 amendment A3): `deadline_us` counts from the END of the
    /// root preselection (prefilter, sort, pool) instead of the planner call, so
    /// the allowance bounds the search alone; the preselection's own time rides
    /// the pick's trace as `preselect_us`. Off (default) = the call-start clock,
    /// byte-identical; absent from every shipped header.
    #[serde(default)]
    pub deadline_after_preselect: bool,
    /// Tree search knob: the widening rate. 0.0 (default) opens every child of
    /// a node before the search descends; > 0 keeps at most
    /// ceil(max(n, 1) ^ tree_widen) children of an n-visit node open.
    #[serde(default)]
    pub tree_widen: f64,
    /// search E1 — PUCT prior at the tree root: `mean + c * p * sqrt(N) / (1 + n)` with `p` the softmax of the caller's
    /// `cand_logits` (index-parallel to the root rows), root children in prior order. 0.0 = off (UCT and the hand order,
    /// byte-identical); a root without logits keeps UCT whatever `c` is.
    #[serde(default)]
    pub tree_puct: f64,
    /// D7 (the objective is P(win), zero-sum) — tree search: an OPPONENT node orders its children (Blend leaf) and
    /// selects among them (UCT argmax) by ITS OWN leaf, priced from its seat (`tree::own_leaf`: the blend for the
    /// opponent with its `opener_seat` token, its hook value asked from that seat), instead of the argmin of the
    /// searcher's. The value backed up stays the searcher's (means), so the root statistics keep their meaning.
    /// Costs a second hook batch below every opponent node. Off (default) = today's tree, byte-identical; read only
    /// under `search_mode` tree.
    #[serde(default)]
    pub tree_opponent_own_leaf: bool,
    /// W2 S0 — `Seams::melee_reach`: `"all"` is today's behaviour (every alive
    /// model of the unit strikes); `"table"` is the p.9 rule, scaling by the
    /// models within 2" of an enemy model instead. Absent from every corpus
    /// recorded before it, so the default replays byte-identical.
    #[serde(default)]
    pub melee_reach: MeleeReach,
    /// `Seams::consolidate` — GF Advanced Rules v3.5.1 p.9 "Consolidation
    /// Moves": one side wiped in melee, the survivor may move up to 3".
    /// Mirrors `SoloController.consolidate_after_melee_win`
    /// (solo_controller.gd:4603). Absent from every corpus recorded before
    /// it, so the default is OFF and nothing replays differently.
    #[serde(default)]
    pub consolidate: bool,
    /// Rung I (AUDIT_armybook_flanks_2026-09-02, DEFECT_LEDGER row 31) — the
    /// dice path's own `p.cond_ap` fold (`dice::resolve_volley_with_tray` /
    /// `resolve_melee_with_tray`), separate from the EV path's long-shipped
    /// `LEGACY_NO_COND_AP` (which gates the STAMP itself and must stay ON for
    /// `~/selfplay_out/gen0_teacher`, recorded after that stamp shipped). A
    /// NEW dice-resolution behaviour, so it follows `melee_reach`/`consolidate`
    /// exactly: absent means the corpus predates it, defaulting OFF so a
    /// recorded rollout that never saw this AP stays byte-identical.
    #[serde(default)]
    pub cond_ap_dice: bool,
    /// `Seams::versatile_reach` — PR #582's charge-distance bonus
    /// (`sim::versatile_reach_charge_in`, table: solo_controller.gd:1781-1827
    /// "Versatile Reach"): a carrier CHARGEing with a base-edge gap in the
    /// ring `(band, band + bonus]` gets `+bonus` added to its charge band.
    /// #582 shipped with no legacy gate (2.25 % of the 143,548-game Gen-0
    /// corpus, recorded before this rule existed, no longer replays
    /// byte-identical — INVESTIGATION_gen0_replay_drift_2026-09-03.md), so
    /// this follows `cond_ap_dice`/`consolidate` exactly: absent means the
    /// corpus predates the rule, defaulting OFF so a recorded rollout that
    /// never saw this bonus stays byte-identical.
    #[serde(default)]
    pub versatile_reach: bool,
    /// The CLASS FIX (external review 03.09. item 3 / F9: "a rule port
    /// without a legacy opt-out breaks byte-exact replay of the recorded
    /// corpora"). Absent/`0` means "the rule set of the Gen-0 corpus" — every
    /// header recorded before this field existed reads back `0`, same as
    /// every other knob here. A fresh `play_game()` stamps
    /// `CURRENT_RULES_EPOCH`. See `rule_on` and `CURRENT_RULES_EPOCH`: a
    /// future rule port that has no legacy reading should NOT add another
    /// boolean knob like `cond_ap_dice`/`versatile_reach` above — it should
    /// bump `CURRENT_RULES_EPOCH`, define a NEW frozen `EPOCH_<n>_<NAME>`
    /// constant equal to the new number, and gate on
    /// `rule_on(rules_epoch, EPOCH_<n>_<NAME>)`.
    ///
    /// **Never gate on `CURRENT_RULES_EPOCH` itself.** It is the LIVE symbol:
    /// the next wave bumps it, and every gate written against it silently
    /// re-points at the new number, so records stamped with the epoch the gate
    /// was born in fall back to the pre-port behaviour. That is not a theory —
    /// it happened at epoch 4 (see the WAVE 2 paragraph on
    /// `CURRENT_RULES_EPOCH` below, which had to freeze six call sites onto
    /// `EPOCH_3_TABLE_RULES`) and again on 2026-09-13, when a rules wave landed
    /// six fresh `rule_on(rules_epoch, CURRENT_RULES_EPOCH)` gates because THIS
    /// comment still recommended the pattern its own history section records as
    /// a defect.
    #[serde(default)]
    pub rules_epoch: u32,
    /// The replay-aware half of `EPOCH_19_MOVE_GRANTS_FOLD`: the header
    /// carried `"books"` — a TABLE recording (`act_recorder.gd:266-268`
    /// writes it unconditionally; no writer in `core/nml-core/src` does) — so
    /// the record's `bands` already fold every move grant
    /// (`battle_sim.gd:1707 -> move_bands_for_props`) and the fold's live
    /// delta stays off (`sim::solo_move_grant_delta_in`). Default OFF: every
    /// core-written record and every fixture predates the key. See
    /// `Header::books` and `header_of`.
    #[serde(default)]
    pub bands_prefolded: bool,
    /// grid-search step 9 — grid widening: cells proposed per (widened unit, kind). 0 (default) = off,
    /// byte-identical; large = all reachable cells. Read only when the knob is set.
    #[serde(default)]
    pub grid_k: usize,
    /// Grid widening: units widened in pool-rank order (0 read as 1).
    #[serde(default)]
    pub grid_units: usize,
    /// Grid widening: the proposer. 0 (default) = ring shells + seeded uniform tail; 1 = learned prior
    /// (declined until step 16).
    #[serde(default)]
    pub grid_proposer: i64,
    /// Grid widening: a grid row wins the argmax only if it beats the running best by this margin; `rs`
    /// keeps the raw value.
    #[serde(default)]
    pub grid_margin: f64,
    /// PREREG_C Arm C — the shuffled-judge control. Nonzero = permute this decision's per-cell judge
    /// values among the widened grid rows before ranking, seeded by this value mixed with `Search::sig`.
    /// 0 (default) = off, byte-identical to Arm B (`grid_k` alone).
    #[serde(default)]
    pub grid_shuffle: u64,
    /// grid-search step 10 — the ANYTIME widen: cells per leaf batch on the widened grid. 0 (default) =
    /// step 9's single batch, byte-identical; n > 0 = price the widened cells in batches of n, stopping
    /// at the call-start deadline with the best so far. Read only when `grid_k` is set.
    #[serde(default)]
    pub grid_batch: usize,
    /// grid-search step 10 — the replay seam: force the widen to price exactly this many cells and
    /// switch the call-start clock off, so a deadline-cut decision replays from its stamped
    /// `grid.completed` (the `tree_budget` precedent). 0 (default) = off, byte-identical.
    #[serde(default)]
    pub grid_budget: usize,
}

/// The current rule-set generation (see `Knobs`/`Seams::rules_epoch`, `rule_on`).
/// Bump this — do not add a new boolean knob — when a table rule port has no
/// legacy opt-out of its own: give the new gate `since_epoch: CURRENT_RULES_EPOCH`
/// in the same change that bumps this constant, so `play_game()` starts
/// stamping fresh records at the new epoch and every earlier record (whose
/// `rules_epoch` reads back lower, or `0` if it predates the field) keeps
/// replaying exactly as it did before the port. `1` is the epoch at which
/// `cond_ap_dice` (PR #637) and `versatile_reach` (PR #642) — the two ports
/// that shipped without their own opt-out before this field existed — turn on
/// unconditionally; `2` is the class fix itself landing; `3` (this constant)
/// bundles the table-rule ports that landed in the same wave as the class
/// fix's own follow-ups — the Regeneration family's DATA-ALIAS wave
/// (Plaguebound, Protected, Knightborn, Cursed Undead, Angelic Blessing,
/// their Boosts and the rest — `unit::regen_targets`' alias loop mirroring
/// main.gd:6637-6652), the Bane family's scope ladder
/// (`unit.rs::stamp_unit_strikers` mirroring `_solo_striker_has_bane`
/// main.gd:6525-6560), the Lacerate+Counter wave — the Counter DATA
/// aliases ("Counter-Attack", "Counter in Melee") stamp the melee array's
/// `counter` flag in `unit::UnitStatic::build_for`, read off the `rules_epoch`
/// the closure is built under — the Surge family's own gates (the volley
/// reads the plain auto-hit form's `surge_within_in` / `surge_low` /
/// `surge_over_in`, main.gd:4465-4482), the Shred-FAMILY port
/// (`unit.rs::stamp`'s alias arm -> `dice.rs::save_batch`'s `shred_alias_dice`
/// gate: unit-level Shred-primitive rules — Destroyer/Infected/Warbound and
/// the two scoped halves — reach the tray from this epoch on), and the
/// Quick/Fast move-band family (`UnitStatic::move_rule_mods`, stamped in
/// `build_for` under the same `rules_epoch`) — every record below it keeps the
/// flat Gen-0 prefix reading and skips the Regeneration/Counter/Surge/Shred/
/// Quick-Fast gating alike.
///
/// WAVE 2 / epoch 4 (external review incident 04.09.): every one of the six
/// call sites above was written as `rule_on(rules_epoch, CURRENT_RULES_EPOCH)`
/// — the LIVE symbol, not a literal. Bumping this constant for a new wave
/// would have silently re-pointed every one of them at the new value too,
/// turning epoch-3 records into a moving target instead of a frozen one. The
/// fix: those six call sites now read `EPOCH_3_TABLE_RULES` (below), a
/// constant that never changes again, so `CURRENT_RULES_EPOCH` is free to
/// keep moving forward with each new wave gating against its OWN frozen
/// epoch number instead of this symbol. Wave 2's five family ports
/// (Lacerate, Utility Buff, Surge's own wave-2 gates, Ambush — Takedown
/// shipped 0 names) landed gating with the literal `4`, per that same
/// convention.
///
/// WAVE 2 STAMPING-GAP INCIDENT (04.09.): PR #671 bumped this constant to
/// `4` to RESERVE the epoch for wave 2 before any wave-2 rule existed. Every
/// `play_game()` in the window between that PR and the five family ports
/// landing (`rules-wave2-*`) stamped `rules_epoch: 4` with NONE of those
/// rules active — the Gen-2b corpus (41,997 records, recorded at main
/// `cf8831d1`) is exactly that window. Once the family ports landed gating
/// on the literal `4`, replaying Gen-2b against the new code silently
/// turned its records into a moving target: verified divergence tonight.
/// Freezing wave 2's gates at `4` (mirroring `EPOCH_3_TABLE_RULES` naively)
/// would PRESERVE the bug — `rule_on(4, 4)` stays `true` forever, so
/// Gen-2b keeps getting rules it was never recorded with. The fix bumps
/// this constant to `5` AND freezes wave 2's gates one past the poisoned
/// value, at `EPOCH_5_TABLE_RULES == 5` (below): a record stamped
/// `rules_epoch: 4` (Gen-2b included) now reads `rule_on(4, 5) == false` —
/// replaying exactly as it did before any wave-2 rule existed — while a
/// fresh header stamping the bumped epoch (`5`) reads `rule_on(5, 5) ==
/// true` and gets every wave-2 family. Every wave from here on must check,
/// before reusing a just-reserved epoch number for its gates, whether any
/// corpus was already stamped with it in the reservation window.
/// EPOCH 46 DISINTEGRATE REGEN (14.09., sweep E row `Disintegrate`): the
/// core's Regeneration split now refuses the heal for wounds of a weapon
/// whose Disintegrate entry carries `bypass_regen: true` (gf
/// blessed_sisters: `{ap_bonus: 2, condition: vs_armor, threshold: 3,
/// bypass_regen: true}`), the same scope the table applies —
/// `_solo_ignores_regen`'s registry-driven WEAPON-rule arm
/// (main.gd:7121-7137): the carrying weapon's own profiles, both reaches,
/// facet-checked. The cond-ap stamp routes it (`unit.rs` — the entry's
/// `bypass_regen` rides the `CondAp` spec, the weapon-rules loop stamps the
/// rule NAME onto `ShootProfile::regen_bypass_rule` behind this gate), and
/// the two dice folds read it on the SAME seam the Bane family uses
/// (`dice.rs`'s `ignores_regen` union), logging the refusal the
/// Bane-in-Melee arm's way (main.gd:7175-7176). Below 46 the field stamps
/// empty and every recorded game replays byte-exact. `46` is one past every
/// existing stamp (44 = `EPOCH_44_SURGE_MARK`, #958; 45 reserved in flight
/// by the casterboost leg), and the value `CURRENT_RULES_EPOCH` is bumped to
/// in the same change. Every call site reads THIS constant, not the literal
/// `46` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_46_DISINTEGRATE_REGEN: u32 = 46;

/// The SURGE LOW window gate (14.09., STANDALONE_SWEEP_F_2026-09-14 row
/// `Great Sergeant`, DIVERGES on both layers vs the book): the registry
/// prints the plain auto-hit form with a widened window — `Surge |
/// bonus_hits_per_six=1, surge_low=5` (aof ogres / plague_disciples; aofr
/// too) — but BOTH stamp loops read `surge_low` only off `upgrades`
/// carriers (unit.rs `stamp`'s block 3b, ai_ev.gd's Boost loop), so the
/// printed 5-6 was dead data and the folds paid the natural 6s alone (the
/// table's board picture and the sim agreed on the same wrong read, so no
/// replay diverged — this is a book-fidelity fix, not a divergence one).
/// From 50 the plain Surge aliases stamp the entry's printed `surge_low`
/// (default 6 — an alias without the param stays a 6s rule) plus the
/// sentinel `surge_over_in` -1.0 (the entry prints no distance gate, melee
/// 0.0" included; the Boost's own default stays 9.0 in block 3b), and the
/// dice consumers pay the successful unmodified 5s behind their existing
/// strict `dist > surge_over_in` gate. Below 50 nothing stamps and every
/// recorded game replays byte-exact. `50` is one past every epoch present
/// at the rebase (49 in flight by the casterinterf leg; 48 =
/// `EPOCH_48_CASTER_BOOST`, #966; 47 = `EPOCH_47_RENDING_SHOOTING_AURA`,
/// #968), and the value `CURRENT_RULES_EPOCH` is bumped to in the same
/// change. Every call site reads THIS constant, not the literal `50` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_50_SURGE_LOW: u32 = 50;

/// The Defense(X) rating gate (14.09., STANDALONE_SWEEP_E_2026-09-14 row
/// `Defense`, TABLE-ONLY): the registry's Shielded-family rating entry — gf
/// common `Defense | primitive Shielded, defense_bonus_from_rating` (aofs/
/// aof/aofr/gff too) — drives the table's Shielded coverage read off the
/// rule's own rating (main.gd:5577-5593, `maxi(rating, 0)`), so the printed
/// Defense(X) saves X better against non-spell hits on the table. The core's
/// Shielded-alias walk listed only the five +1 names and no code read
/// `defense_bonus_from_rating`, so the sim gave a Defense(X) carrier nothing.
/// From 54 `unit.rs::shielded_alias_of` reads the entry BY NAME (the #489
/// lesson — never the bare primitive) and stamps the rating kind
/// (`ShieldedAlias::DefenseRating` plus the number on `Ctx::shielded_rating`),
/// folding +X into the SAME floored non-spell-only seam the five aliases use
/// (`combat::shielded_defense` through `Ctx::shielded_bonus`), with the
/// rules-must-log line naming the rating ("Defense(X): +X Defense vs
/// non-spell hits"). Below 54 the walk keeps its five-name answer and every
/// recorded game replays byte-exact. `54` is one past every epoch present at
/// the rebase (51 casterinterf landed #972; 52 groundedprot, 53 fortifiedaura
/// in flight; 50 = `EPOCH_50_SURGE_LOW`, #973), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `54` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_54_DEFENSE_RATING: u32 = 54;


/// The UTILITY-KIND SPELL gate (14.09., CASTER_SEAM_2026-09-14.md row 5 +
/// port 3): the cast sub-phase's pick refused every non-damage/debuff kind
/// ("an effect kind the sim has no arithmetic for"), so all 56 castable
/// utility instances across the five spells_mechanics maps burned their pick
/// and tokens for nothing. From 52 `pick_cast` picks the MAPPED archetypes
/// (`spell::utility_archetype_of` — the terrain-hazard grants, the
/// fatigue-on-failed-morale flag and the attacker-side AP records, 47 of the
/// 56 instances) and `apply_cast_effect` stamps them; the 7 unmapped ones
/// (charging-scoped AP, forced displacement) still skip. Below 51 the kind
/// filter stands and every recorded corpus replays byte-exact.
pub const EPOCH_52_UTILITY_SPELLS: u32 = 52;
/// The GROUNDED PROTECTION gate (14.09., STANDALONE_SWEEP_F_2026-09-14 row
/// `Grounded Protection`, DIVERGES on both layers vs the book): the registry
/// entry `Regeneration | ignore_target=5, all_models=true,
/// terrain_within_in=1` (aof volcanic_dwarves / wood_elves; aofr, aofs) — the
/// "within 1 inch of terrain" condition is the rule's whole point, and BOTH
/// layers read `all_models` + `ignore_target` only (unit.rs `regen_targets`'s
/// alias wave, the table's `_solo_regen_pick` walk), so the protection
/// applied in the open too. From 55 the alias wave's terrain-gated entries
/// (`terrain_within_in > 0`) hold their target ASIDE on `Ctx::regen_pending`
/// (below 56 the recorded flat fold replays byte-exact), and `sim::ctx_live`
/// resolves it per save moment on the snapshot's own `in_cover` — the
/// Shielded family's terrain-pending resolution, the table's
/// `_solo_majority_in_cover` gate in `_solo_regen_pick` is the twin. Both
/// verdicts trace (rules-must-log). `55` is one past every epoch present at
/// the rebase (54 = `EPOCH_54_DEFENSE_RATING`, #976; 53 the fortifiedaura
/// leg in flight; 52 = `EPOCH_52_UTILITY_SPELLS`, #975; the reservation 52
/// lost two renumber races and moved to CURRENT+1 per the epoch rules), and
/// the value `CURRENT_RULES_EPOCH` is bumped to in the same change. Every
/// call site reads THIS constant, not the literal `55` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_56_GROUNDED_PROTECTION: u32 = 56;

/// The FORTIFIED AURA gate (14.09., sweep F — row `Fortified Aura`): the
/// aofs/gff aura entries ("Fortified Aura", "Guardian Boost Aura") are
/// themselves `Fortified`-primitive entries whose `lost_if_bearer_killed`
/// and `max_picks` were read by nobody — a fallen bearer left the squad at
/// AP(-1) for ever and the 3-pick cap never bound, on the table AND in the
/// sim. From 55 the base read (`ctx.fortified`) is demoted while no bearer
/// lives (the unit itself or an alive attached hero carrying the aura
/// name — a dead hero's list leaves `ProfileDyn.attached_hero_rules`, so
/// the statics rebuild sees the loss exactly when the table does), and the
/// core's own `aura_expand` fold grants the chain capped at `max_picks`,
/// refusing the pick past it; both trace under `NML_TRACE_RULES=1`
/// (`Fortified Aura: N picks -> <units>` / `Fortified Aura: bearer killed
/// -> benefit lost`). The aof spelling (`Aura Channel`, `grants`) carries
/// no knobs and is untouched. Below 55 nothing demotes and every recorded
/// game replays byte-exact. `55` is CURRENT+1 at the second rebase (the
/// first rebase took 53 one past every epoch then present, but the rebase
/// window then landed 52 = `EPOCH_52_UTILITY_SPELLS`, #975, and 54 =
/// `EPOCH_54_DEFENSE_RATING`, #976, skipping 53 — the gate refuses any new
/// constant below the live epoch, so the number moves to 55; 51 =
/// `EPOCH_51_CASTER_INTERFERENCE`, #972; 50 = `EPOCH_50_SURGE_LOW`, #973),
/// and the value `CURRENT_RULES_EPOCH` is bumped to in the same change.
/// Every call site reads THIS constant, not the literal `55` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_55_FORTIFIED_AURA: u32 = 55;

/// The PRECISION MARKERS gate (15.09., PRECISION_TEXT_2026-09-15 §3-§5 — the
/// trio's book text IS on disk, lifting the "no book text" blocker the
/// `EPOCH_23_INERT_MARKS` note names): the three placeholder "Utility Buff"
/// entries — Precision Spotter, Precision Tag, Precision Target — carried
/// `hit_mod: "X"`/`"Y"` placeholders nobody could read. From 61 they carry the
/// real shape (`bonus: "per_removed_marker" | "per_placed_marker"` plus
/// `markers`, the carried rule string's rating overriding the default 1) and
/// `unit.rs::utility_buffs_of` stamps it; placement is
/// `sim::tray_precision_markers` (Spotter: once per activation, 4+ on the
/// tray, 30", pool `State::spot_markers`; Tag: once per game, 24", pool
/// `State::tag_markers`; Target: once per game, 18", a PERSISTENT
/// attackers-side record — +markers for EVERY friendly attack, no spending,
/// the book text has no removal clause), consumption the volley's
/// (`sim::precision_markers_spend`, take-all — the table's own headless
/// policy). Below 61 the placeholders parse as hit_mod 0 and every recorded
/// game replays byte-exact. `61` is one past every epoch present at the
/// rebase (57 stealthbuild and 58 precisiondebuff in flight; 56 =
/// `EPOCH_56_GROUNDED_PROTECTION`, #976), and the value `CURRENT_RULES_EPOCH`
/// is bumped to in the same change. Every call site reads THIS constant, not
/// the literal `61` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_61_PRECISION_MARKERS: u32 = 61;

/// The CASTING MOD SNAPSHOT gate (16.09., D-MAGIC step 3): the spell-side
/// `effect.modifier.casting_mod` family (18 catalogue rows across gf/aof/
/// aofr/aofs/gff — "Sky Blaze", "Hex" & kin, kind "debuff", word-identical
/// text, registry numeric everywhere) finally lands in the CORE imagination.
/// Until now `modifier_of` dropped the field: a landed casting debuff priced
/// at EV 0 was still picked (best_spell_target accepts ev 0 > -1) but the
/// "scaled stamp on the target's mods" wrote NOTHING a cast roll could read.
/// From 62 the generic modifier arm writes `scale * casting_mod` into the NEW
/// `Mods.casting` snapshot slot (gated write: io.rs's `mods` record export
/// must stay byte-exact below the gate), and `casting_net_of` folds the
/// ROUNDED snapshot reading into the cast target next to the EPOCH_6
/// unit-rule ledger — the table's own round-at-read shape
/// (ai_spell.gd:105-130: `casting_net = round(mods.casting)`). A landed
/// debuff can never see its own caster (the snapshot walk reads only the
/// caster's own chain), so there is no self-feedback loop. Below 62 the slot
/// is never written and the fold adds nothing — every recorded corpus
/// replays byte-exact. `62` is one past every epoch present at the rebase
/// (61 = `EPOCH_61_PRECISION_MARKERS`), and the value `CURRENT_RULES_EPOCH`
/// is bumped to in the same change. Every call site reads THIS constant, not
/// the literal `62` or `CURRENT_RULES_EPOCH`. MIRROR HOLD: core-only PR —
/// `battle_sim.gd` has no casting snapshot slot yet, so bumping
/// `act_recorder.gd` here would stamp new table recordings 62 while their
/// replay never had the behaviour; the mirror bumps with the table-side port.
pub const EPOCH_62_CASTING_MOD: u32 = 62;

/// The MELEE HEIGHT gate (27.09., heights B1-b): OPR "Who Can Strike" (GF/AoF
/// Advanced Rules v3.5.1 p.9) reads "within 2” horizontally AND 4” vertically
/// of an enemy model" — `combat::striking_models` dropped the vertical half
/// (`s[1]`/`e[1]`) and let a unit standing on a 6" ruin floor strike (and be
/// struck by) infantry at the wall foot. From 63 `striking_models` also
/// requires `within_melee_height` (`combat::MELEE_VERTICAL_IN`, 4"). Below 63
/// the vertical filter is off. Every recorded corpus has y = 0 for every
/// model (Phase A/B1 do not move the AI), so no replay changes at any epoch
/// (L1, `PLAN_heights_2026-09-27.md`). `63` is one past every epoch present
/// at the rebase (62 = `EPOCH_62_CASTING_MOD`), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `63` or `CURRENT_RULES_EPOCH`.
/// MIRROR HOLD: the table applies the melee-height rule unconditionally (it
/// is table truth, not a corpus-gated behaviour) and every recorded corpus
/// has y = 0, so `act_recorder.gd`'s `rules_epoch` mirror stays at 61 (the
/// casting-mod slot is still unported, see EPOCH_62_CASTING_MOD above); it
/// carries only its own
/// `EPOCH_63_MELEE_HEIGHT` constant for reference.
pub const EPOCH_63_MELEE_HEIGHT: u32 = 63;
/// The DEPLOYLARGE gate (F4, 27.09.): #1048 mirrored the table's whole-zone
/// forward respot for large bases (`deployment::deploy_place_id`) UNGATED,
/// so every corpus recorded before it re-deployed its large bases on replay
/// and the Gen-0 teacher corpus (epoch 0) parted at the first activation.
/// From 64 the respot fires; below it the section spot stands and every
/// earlier corpus replays byte-exact. Corpora recorded at 62/63 between #1048
/// (2026-09-22) and this gate carry the respot and replay without it.
/// MIRROR HOLD: core-only gate — the table runs `large_zone_search`
/// unconditionally and its recordings carry the deployed positions, so no
/// table replay re-runs the core deployment; `act_recorder.gd` stays at 61
/// (`EPOCH_62_CASTING_MOD` is unmirrored too, `EPOCH_63_MELEE_HEIGHT` held).
pub const EPOCH_64_DEPLOY_LARGE_RESPOT: u32 = 64;

/// The MELEE & MORALE TRUTH gate (27.09., wave 3 batch B): one epoch for the
/// batch's core behaviour changes. First item S1-02 (GF/AoF v3.5.1 p.10
/// SHAKEN UNITS: "Shaken units must stay idle, but may strike back counting
/// as fatigued"): from 65 a Shaken unit's melee ctx carries `fatigued`, so
/// its strike-back hits on unmodified 6s (`sim::ctx_of_melee`); the table's
/// strike groups carry the same flag. Below 65 a Shaken strike-back rolls at
/// its full Quality and every recorded corpus replays byte-exact. `65` is one
/// past every epoch present at the rebase (64 = `EPOCH_64_DEPLOY_LARGE_RESPOT`), and
/// the value `CURRENT_RULES_EPOCH` is bumped in the same change. Every call
/// site reads THIS constant, never the literal `65` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_65_MELEE_TRUTH: u32 = 65;

/// The PRECISION DEBUFF gate (15.09., the precision text sweep — row
/// `Precision Debuff`; gf Infected Colonies / Alien Hives, aof Deep-Sea
/// Elves / Dragon Empire / Kingdom of Angels / High Elves, word-identical
/// text, registry numeric in all five maps: `Utility Buff | hit_mod: -1,
/// range_in: 18, target: "enemy", once, needs_los`). The generic
/// utility-buff seam (`unit.rs::utility_buffs_of` -> `sim.rs
/// tray_utility_buff` -> `record_buff`, the #961 seam) stamps ANY
/// primitive-resolving entry from epoch 5 on, so this row rode UNGATED at
/// every epoch before it: from 58 the name is read explicitly — below 58
/// the entry stamps NOTHING (no utility-buff stamp, no record on any
/// ledger) and every corpus recorded before the bump replays byte-exact;
/// from 58 the seam's own enemy pick (best value inside the printed 18" in
/// line of sight) + record fold carry the once `hit_mod: -1` row, and the
/// fold names itself (`rules-must-log`: "Precision Debuff: -1 to hit on
/// <unit> until end of round"; the table's `_solo_apply_utility_buffs`
/// battle-log line is the twin). `58` is one past every epoch present at
/// the rebase (57 in flight by the stealthbuild leg; 56 =
/// `EPOCH_56_GROUNDED_PROTECTION`, #974), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `58` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_58_PRECISION_DEBUFF: u32 = 58;
pub const EPOCH_66_DISTANCE_TRUTH: u32 = 66;
/// The MARKERS & BURSTS gate (28.09., wave 3 batch D, D42 a): Piercing
/// Target's +AP(X) stands while the target lives (army-book v3.5.3, no
/// removal clause) instead of spending on the first volley like the rest of
/// the Piercing-Tag family — `piercing_tag_spend` reads
/// `State.piercing_tag_persistent[ti]`, set by the placement
/// (`tray_piercing_tag`) only for the "Piercing Target" name, itself gated
/// on this constant so a record below it keeps the old spend-whole reading.
/// `67` is one past every epoch present at the rebase (66 =
/// `EPOCH_66_DISTANCE_TRUTH`), and `CURRENT_RULES_EPOCH` is bumped to it in
/// the same change. Every call site reads THIS constant, never the literal
/// `67` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_67_MARKERS_BURSTS: u32 = 67;
/// D21 (S1-03), modifier arithmetic (wave 3 batch E): GF p.5 MODIFIERS — every
/// modifier is simply added to the roll and the new value counts as the final
/// result. From this epoch the save target is ONE sum (Defense - Shielded -
/// Guarded - Cover + AP) clamped once at `[2, 6]`; below it each -1 floors at
/// 2+ before the AP is added (Def 2+ in cover vs AP(1) saves on 3+). `68` is
/// one past `EPOCH_67_MARKERS_BURSTS`; every call site reads THIS constant.
pub const EPOCH_68_MODIFIER_SUM: u32 = 68;
/// B8 (stage-0 freeze 02.10.), the trainer's arena hero fold: from this epoch
/// `selfplay._deploy_arena` hands a host ONLY its own models (below it the host
/// also kept the joined hero's slice — a phantom model with no wound slot), and
/// the joined hero of an Ambush host waits dormant with it and drops with it
/// (below it the hero kept its wounds with no model on the table, and a Deadly
/// spill onto it panicked `land_deadly_wounds`). Py-side only, like
/// `EPOCH_7_TABLE_RULES`'s transport gate: the table's `BattleSim.capture`
/// always wrote one wound and one position per living model of THAT unit.
pub const EPOCH_69_HERO_FOLD: u32 = 69;
/// Tray-exact series (maintainer D151=B, 03.10.): from this epoch `Seams::tray_exact` is ON for
/// every fresh game: casualties come off in the table's chain-keeping order (S6), Takedown lands on
/// the attacker's pick as a unit of [1] (S7-S10), Guarded over 9" reaches Impact and the charged
/// side's melee saves, and Counter walks the joined chain. Below it every record replays the
/// core's old slot order and flags, byte-exact.
pub const EPOCH_70_TRAY_EXACT: u32 = 70;
/// #845 core half (Rapid Charge Mark): from this epoch `tray_vs_marks` records the Rapid Charge
/// Mark on the MARKED ENEMY (the entry's own scope and beneficiary), where `rapid_charge_mark_bonus_in`
/// reads it. Records stamped 66-70 were recorded while that writer was missing and replay byte-exact
/// with the legacy bearer-side once-grant. Every call site reads THIS constant, not `71`.
pub const EPOCH_71_RAPID_CHARGE_MARK: u32 = 71;
/// The 29.10.2026 play-test fixes (A1/A2/A4), the table's #1911/#1912/#1914 in the core and its
/// GDScript sim twins: from this epoch (A1) a printed Lacerate keeps the defender's Regeneration
/// roll (only Bane bypasses it), (A2) wounds that leave a unit at half strength or less trigger
/// the shooting morale test without a lost model, and (A4) a Deadly(X) wound against the
/// Regeneration family rolls all X dice before the model's cap (the EV prices the same). Below it
/// every record replays byte-exact. Every call site reads THIS constant, not `72`.
pub const EPOCH_72_PLAYTEST_RULES: u32 = 72;
/// The rules 3.6 wave (release 0.3.15, D-EPOCH): ONE epoch for the whole wave instead of one per
/// step. Every 3.6 behaviour change in the core and its GDScript twins gates on THIS constant, and
/// nobody bumps again inside the wave. Records stamped 72 or below replay with every 3.6 gate off.
/// Corpus recordings from main are frozen from this bump until the release tag, so no corpus mixes
/// half-ported 3.6 rules under one stamp. Every call site reads THIS constant, not `73`.
pub const EPOCH_73_V36: u32 = 73;
/// The AI's multi-model move pays every climb within its band (GF p.11, #2608 and its core port): from this epoch the
/// flow's coherency pull and untangle re-route, the solver leg, the distance-truth trim and the gate slack price the
/// climb (`CallOpts::climb_cost`, `MoveRules::world_ledges`). Records stamped 73 or below were recorded with the flat
/// trims and replay byte-exact. Every call site reads THIS constant, not `74`.
pub const EPOCH_74_CLIMB_COST: u32 = 74;
/// The core ports of three table rules repairs that landed in `scripts/main.gd` behind `EPOCH_73_V36` (#2612 Crossing
/// Strike volley keeps unit-level Shred, #2613 Protection Feat rolls once per game, #2615 Enhanced Shred forms pay on
/// unmodified 1s at any distance on shots and charges, never on a strike-back). The core gates them HERE so every
/// record stamped 74 or below, recorded while the core lacked them, replays byte-exact. Introduced inert: the three
/// ports read this constant in their own PRs. Every call site reads THIS constant, not `75`.
/// MIRROR HOLD: this PR stays out of `scripts/`; the table already applies all three rules from 73, so
/// `act_recorder.gd` must stamp 75 (one line plus its `EPOCH_75_TABLE_FIXES` constant) in the same merge sitting.
pub const EPOCH_75_TABLE_FIXES: u32 = 75;
/// Move fixes (maintainer decision E (a), 12.11.): three AI defects in one epoch. E1 core: the Great Musician +1" is
/// spent by the buffed unit's next move (`resolve_with`). E2 table: the AI spends its once-per-game Speed Feat only on
/// an activation that moves (`solo_controller.gd _act`). E3 table: Grounded Speed asks the majority of the unit, not its
/// first model (`move_bands_for_unit`). Records stamped 75 or below replay byte-exact. Every call site reads THIS
/// constant, not `76`. The recorder mirror (`act_recorder.gd`) stamps 76 in the same change.
pub const EPOCH_76_MOVE_FIXES: u32 = 76;
/// Charge cap (#183): a charging model whose gate-corrected, retraced trail outruns its band (12", or 6" over difficult)
/// stops at the farthest point of its correction that still fits; the declaration then tests that capped landing.
/// Records stamped 76 or below replay the uncapped charge trails byte-exact. Every call site reads THIS constant, not
/// `77`. The recorder mirror (`act_recorder.gd`) stamps 77 in the same change as `CURRENT_RULES_EPOCH`.
pub const EPOCH_77_CHARGE_CAP: u32 = 77;
/// Flier cut (#2827 core twin): a Flying unit's model whose end rests on forbidden ground (a container footprint, a wall
/// line) is cut back along its own route to the first rest-legal spot before the placement gate, instead of the gate
/// shortening the whole move. Records stamped 77 or below replay byte-exact. Every call site reads THIS constant, not
/// `78`. The recorder mirror (`act_recorder.gd`) stamps 78 in the same change.
pub const EPOCH_78_FLIER_CUT: u32 = 78;
/// FAB-A5 (#G3 port): the sim's shoot EV builds the defender with its `moved_round`/`round` stamp, so an Artillery
/// target that moved this round hands the shooter no -1 to hit (table twin `BattleSim._held_for`). Records stamped 78
/// or below replay byte-exact. Every call site reads THIS constant, not `79`. The recorder mirror stamps 79 with it.
pub const EPOCH_79_EV_MOVED_ROUND: u32 = 79;
/// Cumbersome in the rollouts (ai_03b): the Rust rollout policy menu (`Policy::policy_candidates`) gives a Cumbersome
/// unit only Hold or a plain Advance (GF 3.6 "May only use Hold or Advance actions, but can't shoot when moving"),
/// as the hand menu and the table twin `_policy_candidates` already do. Records stamped 79 or below replay byte-exact.
/// Every call site reads THIS constant, not `80`. The recorder mirror stamps 80 with it.
pub const EPOCH_80_ROLLOUT_CUMBERSOME: u32 = 80;
/// A Shaken unit's morale test fails without a die and spends no once morale buff: the table's `_solo_morale_test` spends the
/// once-mods only after the die it throws (#2804), the core spent them at both of its morale-test sites even for the
/// auto-failed test of an already Shaken unit (or of a dead Shaken host's unit). Records stamped 80 or below replay byte-exact.
/// Every call site reads THIS constant, not `81`. The recorder mirror stamps 81 with it.
pub const EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF: u32 = 81;
/// Wound-ignore rules by name (#2595, table twin `_solo_ignore_wounds`): a bypass (Bane, Rending, Unstoppable, ...) skips only the
/// roll of the rule named Regeneration (own, aura / buff granted, Medical Training); a unit whose ignore rule is anything else
/// (Self-Repair, Resistance, Plaguebound, Angelic Blessing, ...) still rolls the bypassed wounds with the rest. Before, the core
/// folded the whole family into one roll that a bypass skipped entirely. Records stamped 81 or below replay byte-exact. Every call
/// site reads THIS constant, not `82`. The recorder mirror stamps 82 with it.
pub const EPOCH_82_IGNORE_BY_NAME: u32 = 82;
/// Lone hero as the shot target (S1 shadow soak): a volley named at a host with no models left while a joined hero
/// lives is resolved against that hero - its Defense, its models for range and sight, its wounds - as the table does
/// ("Hero: X is the unit now — shots ... are measured and saved as the hero", main.gd `_solo_defense_holder`); the
/// morale test still reads the chain (`morale_root`). Records stamped 82 or below replay byte-exact. Every call site
/// reads THIS constant, not `83`. The recorder mirror (`act_recorder.gd`) stamps 83 in the same change.
pub const EPOCH_83_LONE_HERO_TARGET: u32 = 83;
/// Differently named wound-ignore rules roll one after the other (#2595, table twin `_solo_regen_pick` / `_solo_ignore_wounds`): the
/// core's `Ctx::regen_groups` hold the ignore rules by NAME (Regeneration first, then the most generous target, then the name), a
/// bypassed wound skips only the Regeneration roll and joins the pool at the first other group; before, the family was one roll at the
/// best target. Records stamped 83 or below replay byte-exact. Every call site reads THIS constant, not `84`. The recorder mirror
/// stamps 84 with it.
pub const EPOCH_84_IGNORE_GROUPS: u32 = 84;
/// The pooled target gate of a step-path volley lets through a target nobody sees when a living chain member's weapon carries an Indirect
/// that waives the sight test and reaches it (table twin `_solo_pick_overlay_target`, whose per-shot sight count ignores LOS for a weapon's
/// own Indirect; rules 3.6 SHO-01a: a Hold not kept loses the waiver where the entry says so). Before, a holding Artillery beast with an
/// Indirect gun fired nothing at a unit hidden behind a blocker, the table fired. Records stamped 84 or below replay byte-exact. Every
/// call site reads THIS constant, not `85`. The recorder mirror stamps 85 with it.
pub const EPOCH_85_INDIRECT_GATE: u32 = 85;
/// The played volley's modifier distance (Valiant gate, over-9" modifiers) counts only the model pairs within the vertical reach (3", `melee_vertical_in`),
/// and a unit with no pair in reach keeps the horizontal unit-centre distance: the table's `_solo_ai_volley_distance_in` over `nearest_melee_gap_in`.
/// Before, a unit on a platform measured as close as the ground beside it (the soak's Hive Bond +1, table 4+ vs core 5+). Step path only. Records
/// stamped 85 or below replay byte-exact. Every call site reads THIS constant, not `86`. The recorder mirror stamps 86 with it.
pub const EPOCH_86_VOLLEY_HEIGHT_REACH: u32 = 86;
/// The table's Dangerous count of a move (`SoloController._execute_move`) reads the route the models WALKED: a gate that holds a model back at a
/// container or wall retraces its trail to the gated end, and a crossing the model never reached no longer costs a test. Before, the count read
/// the planned route, so S1's soak had a Mega-Giant held at its start (a 0.002" trail) roll 15 Dangerous dice the core never asked for. A table-side
/// epoch (the core has nothing to change: its landing already reads the walked trail); records stamped 86 or below replay the planned-route count.
/// The recorder mirror stamps 87 with it.
pub const EPOCH_87_WALKED_DANGEROUS: u32 = 87;
/// Split fire at a lone hero (S1 wide-gate prep): a split-fire group aimed at a host with no models left while a joined hero
/// lives is shot as that hero (`split_plan`), as the one-target volley is from `EPOCH_83_LONE_HERO_TARGET` and as the table
/// does for every group (`_solo_defense_holder`). Records stamped 87 or below replay byte-exact. Every call site reads THIS
/// constant, not `88`. The recorder mirror (`act_recorder.gd`) stamps 88 in the same change.
pub const EPOCH_88_SPLIT_LONE_HERO: u32 = 88;
/// Two profiles of one weapon share its sighted bearers (T-DUP-WEAPON-BEARERS): a unit that lists one weapon twice
/// (the Jesters' Atom Pistol x8 plain + x2 AP(1)) fires ONE die per sighted living bearer in total, not per entry.
/// `living_bearers` keys the kits by weapon NAME, so both entries read every bearer and the core double-counted
/// (8 sighted pistols rolled 8+8=16 dice where the table rolls 8). From this epoch the entries split the bearers in
/// order, each capped by its own copies, as the table does (main.gd `_solo_resolve_ai_volley`, key `_solo_bearer_key`).
/// Records stamped 88 or below replay byte-exact. Every call site reads THIS constant, not `89`. The recorder mirror
/// (`act_recorder.gd`) stamps 89 in the same change.
pub const EPOCH_89_SHARED_BEARERS: u32 = 89;
/// A hero joined to a unit rolls ONE Battleborn-family recovery with its host (T-JOINED-ONE-RECOVERY): the playout's
/// round boundary skips an attached hero and copies the host's result to it, as the table does (main.gd
/// `_solo_battleborn_recovery`, `_solo_mirror_shaken`). Before 90 the hero drew its own die and the pair could split.
/// Records stamped 89 or below replay byte-exact. The recorder mirror (`act_recorder.gd`) stamps 90 in the same change.
pub const EPOCH_90_JOINED_ONE_RECOVERY: u32 = 90;
/// A melee fatigues the unit's joined heroes with it (T-JOINED-HERO-FATIGUE, maintainer ruling 19.11.: a joined hero is
/// part of the unit): the core marks the host Fatigued at the charge and at the strike-back, and from 91 it marks every
/// attached hero too, as the table's `_solo_set_fatigued` does. Before 91 only the host index was set, so a joined hero
/// kept striking at full Quality while the table's hero struck on unmodified 6s. Records stamped 90 or below replay
/// byte-exact. The recorder mirror (`act_recorder.gd`) stamps 91 in the same change.
pub const EPOCH_91_JOINED_HERO_FATIGUE: u32 = 91;
/// The melee cause groups of Plan E land together (GMC1, GMC2, GMC3; each is a measured table-vs-core difference of the
/// melee matrix, and the table is the reference). From 92 on, on EVERY path (seeded and step):
///
/// GMC1: Regenerative Strength token wounds land before the strikes, so the Retaliate pool no longer counts them as
/// wounds taken (the table's `pools_before` snapshot); the Self-Destruct survival hits land in the table's casualty
/// order (`land_wounds_with(.., tray_exact)`, a wounded Tough model first).
///
/// GMC2: a moved model's charge endpoint converts through `to_world_f32` and an unmoved one keeps its world position
/// (`Move::execute`, the table's `_plan_positions`); Melee Shrouding shortens the charge band (`melee_shroud_charge_in`).
///
/// GMC3: a unit-level Counter rule folds onto the melee profiles (the unit strikes first); a melee conditional AP reads
/// the target's state (Destructive); the weapon-seat `ranged_over_or_charge` rules (Havocbound, Piercing Warrior, the
/// Piercing Hunter seat) expand into the table's charge + ranged legs.
///
/// Records stamped 91 or below replay byte-exact. Every call site reads THIS constant, not `92` or
/// `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 92 in the same change.
pub const EPOCH_92_MELEE_CAUSES: u32 = 92;
/// Three changes of Plan G land together (each a measured table-vs-core difference; the table is the reference). From 93
/// on, on EVERY path:
///
/// DANGER_AVOID (#3090 part 2, plain moves only): the AI steps into Dangerous ground it could skirt. First, the
/// "destination is Dangerous, route straight in" exception reads the unit's own goal (its centre at the end of the rigid
/// move, base edge included), no longer any single model's rigid end point. Second, a plan that still crosses Dangerous
/// re-plans with the goal shifted sideways, perpendicular to the move (+1, -1, +2, -2, +3, -3, +4, -4 inches, + = right
/// of travel), and keeps the FIRST plan that crosses none. Table twin `SoloController._execute_move`.
///
/// RULES_ALIAS (3.6 faction-folder aliases in the RULES registry; the spell-book twins landed ungated in #3098): an old
/// folder (`wormhole_/rift_daemons_of_*`, `saurian_starhost`) resolves its same-system 3.6 book's rules, so units that
/// gain their rules change outcomes; below 93 the old common-only read stays. Python reads it as
/// `nml_core.EPOCH_93_DANGER_RULES_RIDER`.
///
/// RIDER_OFF (the volley's LEGACY SPELL RIDER, `sim::resolve`, the `!seams.cast` branch): below 93 a seam-off volley by a
/// caster with spare tokens prices (and, on the dice path, pays for) the best affordable in-range damage spell inside the
/// shoot pick, a cast nobody makes: the table has no such rider (its casts are the planned ones, paid at plan time), so a
/// 4-token caster ended a plain volley at 3 tokens in the core against 4 at the table. From 93 the rider is off on EVERY
/// path (dice and expectation alike): the volley is the weapons only and spends no spell token. `seam_cast` ON never had
/// the rider, so its paths are untouched. The GDScript fallback planner (`BattleSim.resolve`) drops its own rider from
/// the same epoch.
///
/// Records stamped 92 or below replay byte-exact. Every call site reads THIS constant, not `93` or
/// `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 93 in the same change.
pub const EPOCH_93_DANGER_RULES_RIDER: u32 = 93;
/// The EPOCH 94 BATCH: thirteen table-vs-core differences that sat behind `PENDING_EPOCH_*` placeholders (all 94) are now one frozen
/// constant, and `CURRENT_RULES_EPOCH` is bumped to it in the same change. Records stamped 93 or below replay byte-exact. Every call site
/// reads THIS constant, not the literal `94` or `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 94 in the same change.
/// - FLYING_THROUGH: a Flying unit's route ignores the other units' spacing zones (the Traversal read); rest legality stays strict.
/// - VERSATILE_MODIFIED_HIT: the Versatile Attack pick is made inside the dice, on the first eligible shot's modified to-hit number.
/// - DEADLY_INLINE: a volley's Deadly weapons land inline; a target wiped by an earlier weapon lends no rules to the later ones.
/// - EXACT_STRIKER_LABELS: the unit-level Bane / Lacerate / Rending / Unstoppable scans match exact labels, not prefixes.
/// - HEIGHT: the core reads a generated board's tier heights (heightfield plan); a header with no `tiers` plays flat at every epoch.
/// - CASUALTY_TIES: the casualty order measures distance as the table's f32 `Vector2.length()`.
/// - HERO_MOVED_STAMP: a joined hero that walks with its host is stamped moved too.
/// - SHAKEN_MIRROR: a joined chain's Shaken flag follows the table's toggle and mirror; a lone hero reads its own flag.
/// - DEADLY_STOPS: a melee Deadly landing stops rolling ignore dice once the chain is dead.
/// - ZERO_MOVE_STAMP: a placement in which no model left its place keeps the chain's stamps.
/// - OWN_INDIRECT: an Indirect granted to the shooter's own unit is read (sight and the moved-penalty note).
/// - SLAYER_MARK_GRANT: the Slayer Mark's grant reaches the marked unit's attackers.
/// - MELEE_MARK_SCOPE: a melee-scoped Piercing Fighting Mark stays on the marked unit after a volley.
pub const EPOCH_94_PARITY_BATCH: u32 = 94;
/// The EPOCH 95 BATCH: five table-vs-core differences that sat behind `PENDING_EPOCH_*` placeholders (all 95) are now one frozen
/// constant, and `CURRENT_RULES_EPOCH` is bumped to it in the same change. Records stamped 94 or below replay byte-exact. Every call site
/// reads THIS constant, not the literal `95` or `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 95 in the same change.
/// - COVER_SCREEN: a unit shot at gets the Cover +1 Defense also when most of its models stand behind a sight blocker (`sight::screen`).
/// - VOLLEY_DEADLY_STOPS: a volley's Deadly wounds stop rolling ignore dice once the target's chain is dead (the volley twin of the melee one).
/// - VOLLEY_DEFENCE_DECLARED: a volley keeps the killed target's declared Defense for the weapons still to fire (Guarded, Shielded).
/// - SPELL_NO_STACK: the same spell does not stack; a second identical record refreshes the first.
/// - UPR_NEEDS_SHOT: no Unpredictable Shooter die for a volley in which no weapon is in reach.
pub const EPOCH_95_PARITY_BATCH: u32 = 95;
/// The EPOCH 96 BATCH: twelve table-vs-core differences that sat behind `PENDING_EPOCH_*`
/// placeholders (all 96) are now one frozen constant, and `CURRENT_RULES_EPOCH` is bumped to it in the same change. Records stamped 95 or
/// below replay byte-exact. Every call site reads THIS constant, not the literal `96` or `CURRENT_RULES_EPOCH`. The recorder mirror
/// (`act_recorder.gd`) stamps 96 in the same change.
/// - UNIT_IMPRECISE: a unit's own Imprecise folds its -1 into the shooting to-hit and names it (`unit::stamp_shot_modifier`).
/// - UNIT_BANE_ALIAS: a unit-level conditional Bane-family rule (Obliterate, Reap, Decimate, Fragment, Smash) reads like the weapon form.
/// - TAKEDOWN_SHOT_PER_MODEL: Takedown Shot's bonus group rolls one attack per living model of the bearer (`sim::takedown_shot_gate`).
/// - SPOTTER_ROLL_RECORD: the Precision / Piercing Spotter placement die pushes its roll record (the step driver no longer refuses it).
/// - ENHANCED_PRIMAL_NEEDS_PRIMAL: an Enhanced Primal grant on a member with no printed extra-attack form rolls no extras group.
/// - ENHANCED_ALWAYS_ALIAS: with a Stealth-family base and its Enhanced form both carried, the wider (any-range) window wins.
/// - ENHANCED_VINCI_ONE_PICK: Enhanced Vinci Tech makes ONE pick at any range instead of both arms past 9" and nothing inside.
/// - BANE_MARK: the Bane Mark rides the Utility Buff path; the next friendly attack on the marked unit gets Bane once.
/// - OUT_OF_REACH_NO_VOLLEY: a target-side range cut that leaves no weapon in reach builds no volley and spends nothing (`sim::cut_out_of_reach`).
/// - REVIVE_SPOT: Reanimation needs the rule on every standing chain model and places a restored model only on a legal spot.
/// - CONSOLIDATE_PLAN: a melee winner's consolidation aims where the table's round planner aims it when the transcript carries the inputs.
/// - HIT_AND_RUN_PLAIN: on a real board the Hit & Run step is the table's own fallback move away from the nearest enemy (`sim::tray_hit_and_run`).
pub const EPOCH_96_PARITY_BATCH: u32 = 96;
/// The EPOCH 97 BATCH: one table-vs-core difference that sat behind the `PENDING_EPOCH_WIPED_TO_HIT_DECLARED` placeholder (97) is now one
/// frozen constant, and `CURRENT_RULES_EPOCH` is bumped to it in the same change. Records stamped 96 or below replay byte-exact. Every call
/// site reads THIS constant, not the literal `97` or `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 97 in the same change.
/// - WIPED_TO_HIT_DECLARED: when a Deadly weapon of a volley kills the target's last model, the weapons still to fire keep the target's
///   to-hit penalties as declared (Stealth family, Evasive family, Aircraft, the Artillery target); the per-hit carrier reads
///   (Fortified, the Regeneration family) still drop (`Ctx::wiped` -> `keep_to_hit_of`).
pub const EPOCH_97_WIPED_TO_HIT_DECLARED: u32 = 97;
/// The EPOCH 98 BATCH: three outcome changes that sat behind the `PENDING_EPOCH_FIREFIGHT_CHAIN`, `PENDING_EPOCH_SKIRMISH_HERO` and
/// `PENDING_EPOCH_COMMAND_GAINS` placeholders (all 98) are now three frozen constants, and `CURRENT_RULES_EPOCH` is bumped to 98 in the
/// same change. Records stamped 97 or below replay byte-exact. Every call site reads these constants, not the literal `98` or
/// `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 98 in the same change.
/// - FIREFIGHT_CHAIN (the 3.6 Firefight book): a `gff` unit's coherency chain is 9 in, not 6 in; AoF: Skirmish keeps 6 in. Read only
///   through `rules::Book::chain_in_at`.
pub const EPOCH_98_FIREFIGHT_CHAIN: u32 = 98;
/// - SKIRMISH_HERO (the 3.6 Firefight and AoF: Skirmish books): every friendly Hero within 6 in lends its Quality to a morale test,
///   with no Tough minimum, and Heroes never join units, so the Blast cap counts the target unit alone. Read only through
///   `rules::Book::hero_aura_at`.
pub const EPOCH_98_SKIRMISH_HERO: u32 = 98;
/// - COMMAND_GAINS (table realism, every system): a rule-only upgrade (Banner, Musician, Sergeant, Great Banner) reaches its unit
///   from the selected option's `gains`, the way the table's `_apply_selected_upgrade_rules` reads a real Army Forge export. Read
///   only by the Python list loader (`list_to_profile._units_from_list`).
pub const EPOCH_98_COMMAND_GAINS: u32 = 98;
/// The EPOCH 99 BATCH: one outcome change that sat behind the `PENDING_EPOCH_SKIRMISH_BLAST` placeholder (99) is now one frozen
/// constant, and `CURRENT_RULES_EPOCH` is bumped to 99 in the same change. Records stamped 98 or below replay byte-exact. Every call
/// site reads THIS constant, not the literal `99` or `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 99 in the same change.
/// - SKIRMISH_BLAST (the 3.6 Firefight and AoF: Skirmish books): a Blast's hits spread over the target's side's units within 3 in,
///   each capped at its models; the neighbours roll their own saves, take wounds and test morale. Read only through
///   `rules::Book::blast_spread_in_at`.
pub const EPOCH_99_SKIRMISH_BLAST: u32 = 99;
/// The EPOCH 100 BATCH: one outcome change that sat behind the `PENDING_EPOCH_SKIRMISH_JUMP` placeholder (100) is now one frozen
/// constant, and `CURRENT_RULES_EPOCH` is bumped to 100 in the same change. Records stamped 99 or below replay byte-exact. Every call
/// site reads THIS constant, not the literal `100` or `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 100 in the same change.
/// - SKIRMISH_JUMP (the 3.6 Firefight and AoF: Skirmish books, Jumping): a drop of over 3 in and up to 6 in, or a gap, is a jump - one
///   die per inch at 2+, its height not counted toward the move; deeper drops stay refused. A failed jump falls: the falling model takes
///   the fall's wounds, lands at the foot of the drop and its activation ends. Read only by `activation::check_move` and
///   `activation::jump_dice_of`.
pub const EPOCH_100_SKIRMISH_JUMP: u32 = 100;
/// The EPOCH 101 BATCH: one outcome change that sat behind the `PENDING_EPOCH_SKIRMISH_PUSH` placeholder (101) is now one frozen
/// constant, and `CURRENT_RULES_EPOCH` is bumped to 101 in the same change. Records stamped 100 or below replay byte-exact. Every call
/// site reads THIS constant, not the literal `101` or `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 101 in the same change.
/// - SKIRMISH_PUSH (the 3.6 Firefight and AoF: Skirmish books, Pushing): a unit Shaken by an attack may be pushed by the attacker
///   (`activation::Input::Push`): on 4+ one model moves up to 2 in and the rest regroup within 1 in; pushed off 2 in or more it falls.
///   An activation that declares no push says so where one would hold. Read only by `sim.rs` (the push step after an attack).
pub const EPOCH_101_SKIRMISH_PUSH: u32 = 101;
/// The EPOCH 103 BATCH: two outcome changes that sat behind the `PENDING_EPOCH_CASUALTY_CHAIN` (102) and
/// `PENDING_EPOCH_COMMAND_BANNER` (103) placeholders are now two frozen constants, and `CURRENT_RULES_EPOCH` is bumped to 103 in the
/// same change. Records stamped 101 or below replay byte-exact; no record was ever stamped 102. Every call site reads these
/// constants, not the literals or `CURRENT_RULES_EPOCH`. The recorder mirror (`act_recorder.gd`) stamps 103 in the same change.
/// - CASUALTY_CHAIN (the 3.6 Firefight book, step 9c): the casualty order keeps a gff unit's chain at the Firefight 9 in
///   (`Book::chain_in_at`), where it kept the recorded 6 in while the movement chain was already 9 in (`EPOCH_98_FIREFIGHT_CHAIN`).
///   Read only by `casualty::chain_casualty_order`.
pub const EPOCH_102_CASUALTY_CHAIN: u32 = 102;
/// - COMMAND_BANNER (the AoF: Skirmish book, steps S4a/S4b, ruling D17): a command group's Banner (+1 to morale test rolls that
///   shooting or melee caused) reaches the units its profile picked (`Profile::command_picks`) while its bearer
///   (`State::cmd_bearer`) lives, and its own unit and the picks lose it when the bearer is killed; the Musician's +1 in on move
///   actions the same way. Read only by `sim.rs` (`command_banner` in the rolled morale test, `command_musician_in` in the move band).
pub const EPOCH_103_COMMAND_BANNER: u32 = 103;
/// The EPOCH 104 BATCH (plan O-FT-5, D5 satisfied 27.11.): the change that sat behind the `PENDING_EPOCH_TWO_BEARERS` (104)
/// placeholder is now one frozen constant, and `CURRENT_RULES_EPOCH` is bumped to 104 in the same change. Records stamped 103
/// or below replay byte-exact. The recorder mirror (`act_recorder.gd`) stamps 104 in the same change.
/// - TWO_BEARERS (KIT-BEARER-NAME, lead ruling 26.11.): each command upgrade lives with the model that carries it - the Musician
///   is lost only when ITS model dies (`State::cmd_musician`, named by the table from the model's equipment), where it rode
///   with the Banner's bearer. A list that names none keeps one bearer for both (the last model). Read only by `sim.rs`
///   (`musician_dead`).
pub const EPOCH_104_TWO_BEARERS: u32 = 104;
/// The EPOCH 105 BATCH (plan O-FT-5): the change that sat behind the `PENDING_EPOCH_ZONE_BASE_EDGE` (105) placeholder is now
/// one frozen constant, and `CURRENT_RULES_EPOCH` is bumped to 105 in the same change. Records stamped 104 or below replay
/// byte-exact. The recorder mirror (`act_recorder.gd`) stamps 105 in the same change.
/// - ZONE_BASE_EDGE (step 8b, the 3.6 books p.6 "fully within 12 in", every system): a deployment zone admits a model only
///   when its whole base is inside (centre + 8 rim points, `deployment::zone_admits_base`), where it tested the base centre
///   and a base overhung the line by up to one radius. Moves AI deployment spots in every system. Read only by
///   `deployment::zone_admits_base`.
pub const EPOCH_105_ZONE_BASE_EDGE: u32 = 105;
/// The EPOCH 106 BATCH (plan O-FT-5): the change that sat behind the `EPOCH_106_CORE_TIERS` (106) placeholder is now one
/// frozen constant, and `CURRENT_RULES_EPOCH` is bumped to 106 in the same change. Records stamped 105 or below replay
/// byte-exact (their terrain line has no `tiers`). The recorder mirror (`act_recorder.gd`) stamps 106 in the same change.
/// - CORE_TIERS (plan step 27-pre): the table hands the core a generated board's ledges - the `tiers` and `solid_cells` of
///   `boardgen::plain::to_plain` for the board on the table - so a table game's jumps, falls and climbs (and the AI's
///   moves) play on the board the player sees, where the core played a flat board. Read only by the recorder mirror
///   (`act_recorder.gd` `_tiers_for_line`); the core reads whatever terrain it is handed.
pub const EPOCH_106_CORE_TIERS: u32 = 106;
/// The EPOCH 107 BATCH (plan O-FT-5): the change that sat behind the `EPOCH_107_RUIN_LEDGES` (107) placeholder is now one
/// frozen constant, and `CURRENT_RULES_EPOCH` is bumped to 107 in the same change. Records stamped 106 or below replay
/// byte-exact. The recorder mirror (`act_recorder.gd`) stamps 107 in the same change.
/// - RUIN_LEDGES (plan step 27-pre-R, lead 26.11.): a free ruin's floors are ledges to the core - a model on a floor that
///   walks off it drops (`Terrain::slab_drops`), in the SAME walk-ordered edges as a tier board's cliffs, so the same bands
///   decide (a plain drop up to `LEDGE_CLIMB_MAX_IN`, a jump by `mv::jump::drop_kind`, else refused). Sight is unchanged.
///   Read only by `activation::cliff_drop_in`'s two callers (`check_move`, `jump_dice_of`).
pub const EPOCH_107_RUIN_LEDGES: u32 = 107;
/// The EPOCH 108 BATCH (plan O-FT-5): the change that sat behind the `EPOCH_108_BLAST_EVEN` (108) placeholder is now one
/// frozen constant, and `CURRENT_RULES_EPOCH` is bumped to 108 in the same change. Records stamped 107 or below replay
/// byte-exact. The recorder mirror (`act_recorder.gd`) stamps 108 in the same change.
/// - BLAST_EVEN (plan step 29a, ruling D-29-R1): the skirmish Blast spread splits the WHOLE attack's hits evenly over the
///   target and its units within reach (`dice::blast_split_at`), not each original hit on its own with the remainder always
///   on the target: 2 hits of Blast(3) over two units with room are 3 + 3, not 4 + 2; the remainder goes where the target's
///   owner picks (29b). A single hit, or no neighbour, lands as before. Only where a book spreads Blast (the skirmish books).
pub const EPOCH_108_BLAST_EVEN: u32 = 108;
/// PENDING (epoch 109, plan SKIRMISH-CATALOGUE; frozen as `EPOCH_109_SKIRMISH_SHOT_MODS` by the bump): the skirmish catalogues (`rules_mechanics_gff/aofs.json`) had no
/// primitive for Precision Charge (+1 to hit on the charge) or the unit-borne Imprecise (-1 to hit), so both never fired
/// in a Firefight / AoF: Skirmish game. Their rows, copied from the gf / aof sibling where the 3.6 army-book text reads the
/// same, carry `"since_epoch": 109` (`rules::Entry::since_epoch`): records stamped 108 or below replay byte-exact.
pub const PENDING_EPOCH_SKIRMISH_SHOT_MODS: u32 = 109;
pub const CURRENT_RULES_EPOCH: u32 = 108;
/// The GROUNDED STEALTH gate (15.09., D-STEALTH): the Stealth family's
/// terrain-conditional alias (`Grounded Stealth | primitive Stealth,
/// hit_penalty 1, terrain_within_in 1` — aofs hidden_syndicates, gf/gff
/// machine_cults) reads the book wording: the -1 to be hit applies only
/// while the target actually stands in/at terrain — per model within the
/// entry's own proximity of ANY terrain — not the table's
/// majority-in-cover-CELL approximation, and not the unconditional alias
/// fold the core carried until now (the table keyed the same gate on the
/// cover-cell read). From 57 the def builds AND the per-model within-1"
/// read into the alias gate (sim.rs, both legs); `unit.rs
/// stealth_alias_split_walk` also returns whether the winning entry is the
/// terrain-gated kind (`Ctx::stealth_alias_near_terrain`), and the table's
/// alias walk replaces the cover-cell read with the same predicate over the
/// #969 id-rail. Below 57 the alias folds unconditionally (the core's old
/// read) and every recorded game replays byte-exact. `60` is one past every
/// epoch present at the push (58 = `EPOCH_58_PRECISION_DEBUFF` on main, 59 = Precision Markers in flight),
/// and the value `CURRENT_RULES_EPOCH` is bumped to in the same change.
/// Every call site reads THIS constant, not the literal `60` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_60_GROUNDED_STEALTH: u32 = 60;

/// The frozen `since_epoch` for the six families that landed together at
/// epoch 3 (Regeneration's DATA-ALIAS wave, the Bane scope ladder, the
/// Lacerate+Counter wave, Surge's own gates, the Shred-family port and the
/// Quick/Fast move-band family — see `CURRENT_RULES_EPOCH`'s doc above for
/// where each one lives). Every one of their call sites in `unit.rs`/`sim.rs`
/// reads THIS constant, not `CURRENT_RULES_EPOCH` — so a record stamping
/// `rules_epoch: 3` keeps getting all six forever, no matter how many times
/// `CURRENT_RULES_EPOCH` moves on for later waves.
pub const EPOCH_3_TABLE_RULES: u32 = 3;

/// EPOCH GATES BY RECORDING SHA (05.09., correcting `EPOCH_5_TABLE_RULES`
/// below): the Gen-2b recording fleet launched at `cf8831d1` — the Lacerate
/// family's OWN merge commit (14:54Z), landed before the fleet's 15:17Z
/// launch — so Lacerate WAS live in the recorder for every `rules_epoch: 4`
/// record. Utility Buff (`a27456d8`, 16:31Z), Takedown (`9efca1ed`, 17:14Z,
/// 0 names), Surge (`e941277d`, 17:48Z), Ambush (`9001b7ae`, 20:57Z) and
/// Shred (`99aee491`, 21:55Z) all merged AFTER the fleet launched and were
/// NOT in the recorder — those five (Takedown moot) correctly stay gated at
/// `EPOCH_5_TABLE_RULES` below. Lacerate alone needs its OWN frozen value —
/// the epoch a record needs to reach to get IT is `4`, not `5` — so a record
/// stamping `rules_epoch: 4` (Gen-2b included) keeps getting Lacerate
/// forever, while `rules_epoch: 3` and below still don't. Only
/// `unit.rs::rules_of_primitive`'s Lacerate-family call site reads this
/// constant.
pub const EPOCH_4_TABLE_RULES: u32 = 4;

/// The frozen `since_epoch` for wave 2's remaining family ports (Utility
/// Buff, Surge's own wave-2 gates, Ambush, Shred's widened save-fail window —
/// Takedown ported 0 names, nothing to freeze; Lacerate moved to its OWN
/// `EPOCH_4_TABLE_RULES` above, 05.09. correction: it was live in the Gen-2b
/// recorder, the other four and Shred were not). Named the same way
/// `EPOCH_3_TABLE_RULES` is: the epoch a record needs to reach to get these
/// rules — NOT the epoch their code happened to be written under (every
/// "WAVE 2" comment in `unit.rs`/`sim.rs` still says the literal `4`, since
/// that's what wave 2 was written against before this fix). See the WAVE 2
/// STAMPING-GAP INCIDENT note on `CURRENT_RULES_EPOCH` above for why the
/// NEEDED epoch is `5`, one past the family ports' own literal: Gen-2b was
/// already stamping `rules_epoch: 4` before this wave's rule code existed,
/// so `4` would keep that corpus wrongly getting these rules forever. `5`
/// instead excludes every record stamped `4` or below (Gen-2b included)
/// while still catching every wave-2 call site's original intent (a fresh
/// record from the moment these rules landed onward). Every one of
/// `unit.rs`/`sim.rs`'s remaining wave-2 call sites (and `sim.rs`'s Shred
/// Boost gate, moved here 05.09. — it merged AFTER the recording fleet
/// closed, gated on the literal `4` until now) reads THIS constant, not the
/// literal `4` or `CURRENT_RULES_EPOCH`, so a record stamping `rules_epoch:
/// 5` keeps getting all of them forever, no matter how many times
/// `CURRENT_RULES_EPOCH` moves on for later waves.
pub const EPOCH_5_TABLE_RULES: u32 = 5;

/// WAVE 3 GATE (05.09.): reserved for wave 3's table-rule ports before any of
/// them exist — the same shape as `EPOCH_3_TABLE_RULES`/`EPOCH_4_TABLE_RULES`/
/// `EPOCH_5_TABLE_RULES` above, a frozen epoch number instead of the moving
/// `CURRENT_RULES_EPOCH` symbol, so wave 3's family ports (landing in later
/// changes) read THIS constant from the day their gates are written and never
/// drift when a later wave bumps `CURRENT_RULES_EPOCH` again.
///
/// `6`, not `5`: the Gen-3 recording fleet launched 05.09. 04:27Z at main
/// `bb10c227` and is stamping `rules_epoch: 5` right now — wave 3's ports do
/// not exist in that recorder. Freezing wave 3's gates at `5` (the epoch
/// already live and being stamped) would repeat the exact WAVE 2
/// STAMPING-GAP INCIDENT that `EPOCH_5_TABLE_RULES` above had to correct for
/// (PR #685, refined by PR #688): once a wave-3 family port landed gating on
/// `rule_on(rules_epoch, 5)`, replaying the Gen-3 corpus against that code
/// would silently start applying rules it was never recorded with. `6`
/// instead excludes every record stamped `5` or below (Gen-3 included) while
/// still catching every fresh record from the moment wave 3's rules land —
/// and this constant is reserved in the SAME change that bumps
/// `CURRENT_RULES_EPOCH` to `6`, so no window opens between the reservation
/// and the first wave-3 rule landing (the gap that poisoned Gen-2b at epoch
/// 4). Every wave-3 call site must read THIS constant, not the literal `6`
/// or `CURRENT_RULES_EPOCH`.
pub const EPOCH_6_TABLE_RULES: u32 = 6;

/// WAVE 4 GATE (06.09.): reserved for wave 4's table-rule ports before any of
/// them exist — the same shape as `EPOCH_3_TABLE_RULES`/`EPOCH_4_TABLE_RULES`/
/// `EPOCH_5_TABLE_RULES`/`EPOCH_6_TABLE_RULES` above, a frozen epoch number
/// instead of the moving `CURRENT_RULES_EPOCH` symbol, so wave 4's family
/// ports (landing in later changes) read THIS constant from the day their
/// gates are written and never drift when a later wave bumps
/// `CURRENT_RULES_EPOCH` again.
///
/// `7`, not `6`: wave 3's ports are already merged and gated at
/// `EPOCH_6_TABLE_RULES`, so `6` is the epoch every fresh recorder stamps
/// TODAY — and wave 4's ports exist in none of those records. Freezing wave
/// 4's gates at `6` (the epoch already live and being stamped) would repeat
/// the WAVE 2 STAMPING-GAP INCIDENT that `EPOCH_5_TABLE_RULES` above had to
/// correct for (PR #685, refined by PR #688) and that wave 3 avoided the same
/// way: once a wave-4 family port landed gating on `rule_on(rules_epoch, 6)`,
/// replaying a corpus recorded now against that code would silently start
/// applying rules it was never recorded with. `7` instead excludes every
/// record stamped `6` or below while still catching every fresh record from
/// the moment wave 4's rules land — and this constant is reserved in the SAME
/// change that bumps `CURRENT_RULES_EPOCH` to `7` (wave 4's plan §5 makes the
/// bump W4-0, the first PR of the wave), so no window opens between the
/// reservation and the first wave-4 rule landing. Every wave-4 call site must
/// read THIS constant, not the literal `7` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_7_TABLE_RULES: u32 = 7;

/// The PLANNER MENU gate (#821, frozen at 8 on 08.09.): the rollout policy's
/// rush demotion (playout.rs) — a rush capped to the advance band with a shot
/// in range is demoted to an advance + shoot — is gated
/// `rule_on(rules_epoch, EPOCH_8_PLANNER_MENU)`. #821 landed gating the same
/// behaviour on `EPOCH_7_TABLE_RULES`, which shrank the epoch-7 fixtures'
/// replayed menus (109 -> 97, seed 1) and turned main's python suite red: a
/// menu change is a NEW frozen gate per the epoch contract, never a re-read of
/// an older one. `8` excludes every record stamped 7 or below (the pre-#821
/// corpora replay their 109-wide menus byte-exact) while fresh headers stamp
/// `CURRENT_RULES_EPOCH == 8` and get the demotion. Every call site reads THIS
/// constant, not the literal `8` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_8_PLANNER_MENU: u32 = 8;

/// The MARK-FAMILY gate (#870, frozen at 9 on 11.09.): #870 flipped ten
/// registry entries from `vs_marked` to `vs_target` — Rapid Charge Mark (aof/aofr
/// dark_elves, gff city_runners), Piercing Fighting Mark (aof/aofr goblins, gff
/// berserker_clans), Slayer Mark (aofs hidden_syndicates, gff worker_unions),
/// Piercing Shooting Mark (gf dao_union), Unpredictable Shooter Mark (gf
/// goblin_reclaimers) — so the Godot table finally grants them. The Rust core
/// reads the same registry files, and its grant (`sim::tray_vs_marks`) had no
/// epoch gate — a replay of a game recorded BEFORE the fix would receive grants
/// the table never gave, and pre-fix recordings all stamp `rules_epoch: 8`, so
/// the core could not tell old from new. `9` (one past every pre-fix stamp, and
/// the value `CURRENT_RULES_EPOCH` is bumped to in the same change) excludes
/// those records — they replay as they were recorded — while fresh headers get
/// the five. Every call site reads THIS constant, not the literal `9` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_9_MARK_FAMILY: u32 = 9;

/// The CHARGE-BAND gate (12.09., #879/#880 wave): the core's `Bands` gains a
/// distinct `charge` reach (the table's `bands["charge"]`, the `charge_only`
/// move-band rules — the 12.09. census measured exactly two names, "Rapid
/// Charge" and "Rapid Charge Aura"). Every recorded corpus was played by a
/// table that ALREADY gave those units their distinct charge reach while the
/// core replayed them with the plain rush band, so making the charge seams
/// read the band CHANGES how existing records replay — toward the table, but
/// it changes them. `10` (one past every pre-port stamp, and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change) excludes those
/// records — they replay exactly as they were recorded — while fresh headers
/// get the band. Every call site reads THIS constant, not the literal `10` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_10_CHARGE_BAND: u32 = 10;

/// The SOLO move-grant read gate (13.09., census rows 1-5): the evidence-only
/// accessor reads of the Slow/Fast/Swift/Rapid Advance/Rapid Rush grants. The
/// reads are trace-only and fold nothing (the recorded dynamic band already
/// carries each grant — semantics §2(a)/§12), but a record below `11` still
/// sees nothing, exactly like it never saw those reads. `11` is one past every
/// pre-port stamp and the value `CURRENT_RULES_EPOCH` is bumped to in the same
/// change. Every call site reads THIS constant, not the literal `11` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_11_SOLO_GRANT_READS: u32 = 11;

/// #845 option (b), 13.09.: a vs-target Mark's attacker-side grant now LIVES ON THE MARKED
/// ENEMY (the record's `beneficiary` is `"attackers"` on the target, with no live overlay on
/// the bearer) and the table's charge seams read a target's "Rapid Charge" grant for the
/// friendly charger's one charge. TABLE-only port: no core replay path consumes this constant
/// yet, it is the reservation that lets the next port gate on it without re-dating records
/// recorded at epoch 10 or below. Every table-side reader/writer names #845 in its comment.
pub const EPOCH_11_RAPID_CHARGE_MARK: u32 = 11;

/// The MOVE-BUFF gate (the Great Musician port): the "Utility Buff" family's
/// move-only knob (`move_mod`, carried by exactly one registry name) becomes a
/// recorded ledger row AND a live band read. The TABLE has applied it since
/// #846 (main.gd:16980 -> the `spell_move_mod` prop -> move_bands_for_props),
/// so a recorded corpus's `bands` ALREADY carry the table's answer: the core's
/// delta is added only for rows the core itself wrote during its own playout
/// (io.rs keeps `advance_in`/`rush_in` unparsed, which is what keeps the two
/// from meeting). `12` is one past every existing stamp, and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change, so every corpus
/// recorded at 11 or below replays byte-exact. Every call site reads THIS
/// constant, not the literal `12` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_12_MOVE_BUFF: u32 = 12;

/// The unit.rs who-wins wave (audit 2026-09-13 §2.2–§2.4) — Counter's both
/// halves (`Ctx::counter_models`, the tray's COUNTER_ONLY pre-phase), the
/// Bane aliases' regen-bypass split (`ShootProfile::bypass_regen`) and the
/// Sturdy-kind Boost's gate replacement all read THIS frozen value, so a
/// later epoch bump cannot re-date what these gates mean. `13` is one past
/// every existing stamp, and the value `CURRENT_RULES_EPOCH` is bumped to in
/// the same change, so every corpus recorded at 12 or below replays
/// byte-exact. Every call site reads THIS constant, not the literal `13` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_13_WHO_WINS: u32 = 13;

/// The DEADLY LANDING gate (audit 2026-09-13 §2.1): the core's dice path stops
/// multiplying Deadly at the POOL level against the unit's printed Tough and
/// lands it PER MODEL with no carry-over — the book's own shape (GF v3.5.1
/// p.14) and the table's (`SoloController.apply_deadly_wounds`,
/// solo_controller.gd:8333). Below 14 the pool multiply is kept VERBATIM
/// (`dice.rs` `save_batch`'s legacy leg, the landing spilling as before), so
/// every corpus recorded at 13 or below replays byte-exact. `14` is one past
/// every existing stamp (13 is `EPOCH_13_WHO_WINS`), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `14` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_14_DEADLY_LANDING: u32 = 14;

/// The MARK BENEFICIARY gate (14.09., the Precision-marks wrong-side fix):
/// the `Precision Fighting Mark` / `Precision Shooting Mark` entries (plus the
/// aofs ap_mod variant, registry-named `Piercing Shooting Mark`, furious_
/// tribes) gain the family's own `beneficiary: "attackers"` key — the +1 (or
/// AP(+1)) feeds the rolls made AGAINST the marked unit (`mods::Role::VsTarget`,
/// table `_solo_spell_hit_mod_vs`) instead of the marked unit's own rolls, the
/// side MARK_FAMILY_SWEEP_2026-09-14 measured in both layers. Below `15` the
/// key reads as absent (`unit.rs utility_buffs_of`), so every corpus recorded
/// at 14 or below replays the wrong side it was recorded with. `15` is one
/// past every existing stamp, and the value `CURRENT_RULES_EPOCH` is bumped to
/// in the same change. Every call site reads THIS constant, not the literal
/// `15` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_15_MARK_BENEFICIARY: u32 = 15;

/// The FREE PLACEMENT gate (14.09., the sweeps A/C defect — one bug under three
/// names, rows `Vanguard`/`Drakesworn`/`Fanatic`): all three books print
/// "After this model is deployed, it may be placed anywhere fully within 9\" of
/// its position" and all three carry the registry primitive
/// `Vanguard {place_in: 9}`, yet both layers ran a directional PUSH toward the
/// table centre (`deployment::vanguard_push` / `solo_controller.gd
/// _vanguard_push`) — the model could never step sideways or backwards. From 16
/// the move is the rule's FREE choice within the radius
/// (`deployment::vanguard_free_place` / `solo_controller.gd
/// _vanguard_free_place`); below 16 every corpus replays the directional push
/// it was recorded with. `16` is one past every existing stamp, and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site reads
/// THIS constant, not the literal `16` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_16_FREE_PLACEMENT: u32 = 16;

/// The SURGE SCOPE gate (14.09., sweep B — row `Surge when Shooting`,
/// `STANDALONE_SWEEP_B_2026-09-14.md`): the book prints "This model gets Surge
/// when shooting", yet the registry entry (`gf`/`gff` common) carried no scope
/// key, so both layers stamped `surge` onto the bearer's MELEE profiles too —
/// +1 hit per unmodified 6 with every melee weapon, in table play and core
/// sims alike. The entry now carries `shooting_only: true` (the registry's own
/// convention — `Predator Shooter`, the `scope`-carrying Utility Buffs); from
/// 17 the core honours it (unit.rs stamp block 3 and build_for's named walk)
/// and the table's alias loop does the same (ai_ev.gd's Surge loop, the
/// recorder's frozen mirror). Below 17 the entry replays the unscooped walk
/// every corpus was recorded with. `17` is one past every existing stamp, and
/// the value `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call
/// site reads THIS constant, not the literal `17` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_17_SURGE_SCOPE: u32 = 17;

pub const EPOCH_19_MOVE_GRANTS_FOLD: u32 = 19;

/// The SCREENED MELEE gate (14.09., sweep B — row `Screened`): the army-book
/// entries aliased to the Stealth primitive with `applies_charged: true`
/// (Screened, Changebound, Machine-Fog, Empyrean Spirit, Gloom-Mist) print
/// "When units where all models have this rule are shot or charged from over
/// 9\" away, enemy units get -1 to hit rolls" — yet the core folded the
/// Stealth DATA-alias pair (`stealth_alias_penalty`/`stealth_alias_over_in`)
/// on the shooting path only: `melee_hit_modifier`'s signature had nowhere to
/// put it, so a charge launched from over 9" rolled unpenalised hits in every
/// core-simulated game. From 22 the dice melee fold
/// (`dice.rs::melee_hit_target` through `resolve_melee_leg`'s
/// `screened_melee` gate) applies the alias's own `hit_penalty` when the
/// strike is a charge from over the alias's `over_in`, measured the table's
/// own way (`geom::centre_dist_in` on the pre-move snapshot — the
/// `report["charge_from_in"]` measure). Below 22 the fold never sees the
/// alias, so every corpus recorded at 19 or less replays byte-exact. `22` is
/// one past every existing stamp, and the value `CURRENT_RULES_EPOCH` is
/// bumped to in the same change. Every call site reads THIS constant, not the
/// literal `22` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_22_SCREENED_MELEE: u32 = 22;

/// The INERT MARKS gate (14.09., MARK_FAMILY_SWEEP_2026-09-14 finding 1 — the
/// two #870 vs_target marks whose grant lands but never folds): Piercing
/// Fighting Mark (`aof`/`aofr` goblins, `gff` berserker_clans) and Piercing
/// Shooting Mark (`gf` dao_union) carry the entry's own `grants_rule`
/// ("AP(+1) in melee" / "AP(+1) when shooting"), but `tray_vs_marks` pushed
/// the mark's once-grant under the BASE name ("Piercing Fighting") and the
/// only grant readers ask for the `grants_rule` strings — so both layers
/// stamped and spent the mark and nothing folded. From 23 the grant rides the
/// entry's own string and `ctx_live` reads it with the exact-string twin
/// (`mods::granted_exact`); below 23 the base name rides and every corpus
/// replays the recorded inert mark. The two Precision-family Registry entries
/// with undefined/underdetermined effect data (`Precision Tag`'s `hit_mod:
/// "Y"` placeholder, `Precision Target`'s missing `beneficiary` +
/// `uses_per_game` seam) are deliberately NOT wired — no book text on disk.
/// `23` is one past every existing stamp (22 = #932's Screened melee leg,
/// 19 = #935's fold), and the value `CURRENT_RULES_EPOCH` is bumped to in the same
/// change. Every call site reads THIS constant, not the literal `23` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_23_INERT_MARKS: u32 = 23;
/// The TERRAIN DEBUFF gate (14.09., sweep A — rows `Dangerous Terrain Debuff`
/// / `Difficult Terrain Debuff`, `STANDALONE_SWEEP_A_2026-09-14.md`): both
/// layers announce the debuff — the table's log even appends a dead
/// `Dangerous Terrain (spell)` rule to the marked unit — but no reader ever
/// treated a unit-level terrain rule as a hazard. The once-per-move Dangerous
/// test and the movement cost keyed on the CELL a unit crossed, never on a
/// rule the unit carried, so the marked enemy walked open ground unwounded
/// and at full speed. From 26 the core folds the grant the same way it folds
/// a cell, through the ONE `mods::granted_terrain_debuff` reader:
/// `sim::dangerous_dice` ORs a granted "Dangerous Terrain" into the per-model
/// trigger, `mv::step`'s p.11 cap and `mv::cost::terrain_cost_at` (carried on
/// the move call's own debuff knobs) consult a granted "Difficult Terrain"
/// the way they consult the cell. Below 26 the grant is inert — every
/// recorded game replays unchanged. `27` is one past every existing stamp
/// (26 is reserved in flight by the placed3 activation leg, PR #940; 25 =
/// `EPOCH_25_ETHEREAL_BANDS`, 23 = `EPOCH_23_INERT_MARKS`, 19 = #935's
/// fold), and the value `CURRENT_RULES_EPOCH` is bumped to in the same
/// change. Every call site reads THIS constant, not the literal `27` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_27_TERRAIN_DEBUFF: u32 = 27;

/// The STRAFING gate (14.09., sweep row `Strafing`, TABLE-ONLY): the book's
/// "Once per activation, when this model moves through enemy units, pick one
/// of them and attack it with this weapon as if it was shooting. This weapon
/// may only be used in this way." The table resolves it at main.gd:1092-1097
/// (`_solo_apply_strafing` main.gd:2964-3007) and the registry carries
/// `Strafing {move_through_attack: true, weapon_only: true}`, but the core
/// only ever stamped the weapon flag (unit.rs:1130) and marked the volley fold
/// (dice.rs:945-946) — no move-through seam existed, so a strafing aircraft
/// flew past in silence and the net never learned to overfly anything. From 32
/// the core resolves ONE shooting exchange through the shared volley resolver
/// (`sim::tray_strafing`) when the executed move's trails cross an enemy unit
/// (the table's `trails_cross_unit_bases` segment-vs-disc test, the NEAREST
/// crossed enemy as the pick, main.gd:3000-3004). Below 32 the slot is inert —
/// every recorded game replays byte-exact. `32` is one past every existing
/// stamp (30 = `EPOCH_30_SCRAPPER_BOOST`, #945; 31 is reserved in flight by
/// the re-deployment leg), and the value `CURRENT_RULES_EPOCH` is bumped to in
/// the same change. Renumbered from the reserved 29 at rebase (#945's 30
/// landed first) per the epoch rules. Every call site reads THIS constant,
/// not the literal `32` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_32_STRAFING: u32 = 32;
/// The RE-DEPLOYMENT gate (14.09., STANDALONE_SWEEP row "Re-Deployment",
/// TABLE-ONLY; GF v3.5.1 p.15: "After all other units are deployed (excluding
/// units that were set aside), you may remove up to two friendly units from
/// the table and deploy them again."). The table re-places up to two carriers
/// at the game-start transition (`solo_controller.gd:9762-9816
/// redeployment_pass`, invoked from main.gd:1165-1174); the core only stamped
/// `re_deployment_max_units` (`unit.rs:1067`) and never re-placed anyone —
/// every core-simulated game answered the opponent's final setup with the
/// deployment it made blind. From 33 `deployment::redeployment_pass` runs at
/// the same moment (after both sides are deployed) with the table's own scan.
/// Below 33 the carrier stays where it first stood — every recorded game
/// replays unchanged. `33` is one past every existing stamp (32 =
/// `EPOCH_32_STRAFING`, #947; 31 reserved in flight, 28 was this
/// leg's first reservation, renumbered twice at rebase per the epoch
/// rules). Every call site reads THIS constant, not the literal `33` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_33_REDEPLOYMENT: u32 = 33;
/// The WATCHBORN LATCH gate (14.09., sweep row `Watchborn`, BOTH layers; the
/// `Versatile Attack`/`Versatile Reach` `pick_one` pair, book text: "When this
/// unit is activated, pick one effect: until the end of the activation, when
/// shooting or charging enemies over 9" away, gets AP(+1) or +1 to hit").
/// Both layers re-decided PER VOLLEY before (the AI took the EV-best mode per
/// shot, the human was re-prompted for every volley) and the core's melee dice
/// fold had NO versatile leg at all — a core-simulated Watchborn charge fought
/// without the bonus its own planner (`combat::profile_ev`'s `!melee ||
/// charging` leg) counted on. From 38 the pick is made ONCE per activation:
/// the first eligible attack decides by EV, the stamp lives on the State's
/// per-unit round latch (one act per unit per round) on the core and on
/// `unit_properties["versatile_pick_round"]` on the table, and every later
/// volley/charge of the activation reuses it. Below 38 every recorded game
/// replays byte-exact. `38` is one past every existing stamp at rebase time
/// (36 was this gate's first reservation, renumbered at rebase when #957's
/// 37 landed first, per the epoch rules; 37 =
/// `EPOCH_37_UNSTOPPABLE_AURA`, #957). Every call site reads THIS constant,
/// not the literal `38` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_38_WATCHBORN_LATCH: u32 = 38;

/// EPOCH 41 SELF-DESTRUCT SURVIVORS (14.09., sweep H row `Self-Destruct`,
/// `STANDALONE_SWEEP_H_2026-09-14.md`): the registry primitive
/// `Self-Destruct; hits=X, rating=X, trigger=death_in_melee_or_post_melee`
/// carries a SURVIVAL half the core never ported. The table's
/// `_solo_self_destruct_post_melee` (main.gd:17346-17370, called for BOTH
/// combatants at main.gd:8431-8433 and :10456-10458, after both sides have
/// finished attacking and BEFORE the melee result / morale test) removes
/// every surviving carrier ("it is immediately killed" — main.gd:17363's
/// 9999-wound application, no saves) and pays the enemy X hits per removed
/// model (X = the rule's own `maxi(rating, 1)`, main.gd:17357-17358), saved
/// at the enemy's Shielded melee Defense with ap 0. The core had only the
/// death half (sim.rs Block C4): a Self-Destruct model that SURVIVED the
/// melee neither detonated nor died, so a core-driven fight never learned
/// the suicide unit the table plays. From 41 the tray charge epilogue runs
/// the survival half in the table's order (the charger's carriers first,
/// then the defender's). Below 41 every recorded game replays byte-exact.
/// `41` is one past every existing stamp at rebase time (40 =
/// `EPOCH_40_STEADFAST_ROLL`, #960; 39 = `EPOCH_39_MORALE_RATING`, #959;
/// 38 = `EPOCH_38_WATCHBORN_LATCH`, #955). Every call site reads THIS
/// constant, not the literal `41` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_41_SELF_DESTRUCT_SURVIVORS: u32 = 41;

/// EPOCH 34 UNSTOPPABLE MARK (PR #951, sweep C row `Unstoppable Mark`): "Once
/// per activation, before attacking, pick one enemy unit within 18" in line of
/// sight, which friendly units get Unstoppable against once." Unstoppable =
/// ignore all negative to-hit modifiers AND ignore the target's Regeneration.
/// The once-grant's REGENERATION half reached the core's regen split since B2b
/// (`dice.rs`'s `att.unstoppable_grant`), but the two TO-HIT clamps read the
/// weapon's own `p.unstoppable` only — the "ignores all negative modifiers"
/// half never fired for a granted mark, while the table's bridge folds the
/// mark into the profile flag and its clamp works. From 34 `ctx_live` stamps
/// the grant into `Ctx::unstoppable_mark` and the clamps read it like the
/// weapon flag (one record, spent once per attack sequence — the Regeneration
/// half's consumption is shared, never doubled). Below 34 the clamps stay
/// `p.unstoppable`-only and every recorded corpus replays its own rolls.
/// `34` is one past every existing stamp (32 = `EPOCH_32_STRAFING`, #947; 33
/// is reserved in flight by #946). Every call site reads THIS constant, not
/// the literal `34` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_34_UNSTOPPABLE_MARK: u32 = 34;

/// The UNSTOPPABLE-IN-MELEE CLAMP gate (14.09., sweep C — row `Unstoppable in
/// Melee`, `STANDALONE_SWEEP_C_2026-09-14.md`): the book's "This model gets
/// Unstoppable in melee." carries BOTH halves of Unstoppable — ignore all
/// negative to-hit modifiers AND ignore the target's Regeneration — but the
/// registry models the name as `Lacerate {bypass_regen, melee_only}` and the
/// unit-level Unstoppable stamp (`unit.rs::stamp_unit_strikers`) skipped every
/// name containing " in ", exactly as the table's point-sim stamp does
/// (battle_sim.gd). Only the Regeneration cut-through ever fired; the melee
/// strike ate the Evasive -1 and every moved penalty the book told it to
/// ignore. From 35 the stamp accepts the "Unstoppable in Melee" name for the
/// MELEE profiles (the clamp READ at the melee hit fold, dice.rs
/// `melee_hit_target`, reads the profile's own `unstoppable` flag — a melee
/// profile never reaches the volley fold, so the scoping rides the profile
/// split and the clamp sites themselves stay untouched). Below 35 the name
/// keeps firing its Regeneration half alone — every recorded game replays
/// byte-exact. `35` is one past every existing stamp (34 =
/// `EPOCH_34_UNSTOPPABLE_MARK`, #951; 33 = `EPOCH_33_REDEPLOYMENT`), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `35` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_35_UNSTOPPABLE_MELEE: u32 = 35;

/// EPOCH 37 UNSTOPPABLE AURA (14.09., sweep C row `Unstoppable when Shooting
/// Aura`): the book's "This model and its unit get Unstoppable when shooting."
/// is a Utility Buff carrying `{grants_rule: "Unstoppable", scope: "shooting"}`,
/// but the grant overlay read its records scope-blind on both layers — the
/// aura-granted "Unstoppable" cut through Regeneration in MELEE too, and its
/// clamp half reached the core only through #951's scope-blind mark stamp,
/// logging "(once)" for a persistent grant. From 37 `ctx_live` splits the live
/// "Unstoppable" grant by the record's own scope: `Ctx::unstoppable_aura` (the
/// shooting-scoped part) arms the SHOOTING to-hit clamp and names the SHOOTING
/// Regeneration line, `Ctx::unstoppable_regen_melee` answers the melee
/// Regeneration read only for records that are NOT shooting-scoped, and the
/// mark's clamp stamp reads the melee half. Below 37 every read stays
/// scope-blind and every recorded corpus replays its own rolls. `37` is one
/// past every existing stamp (35 = `EPOCH_35_UNSTOPPABLE_MELEE`, #953; 36 is
/// reserved in flight by the watchborn leg). Every call site reads THIS constant, not the
/// literal `37` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_37_UNSTOPPABLE_AURA: u32 = 37;
/// The MORALE RATING gate (14.09., STANDALONE_SWEEP_G row `Morale`,
/// TABLE-ONLY): `Morale` with rating X adds +X to its morale tests — the
/// registry primitive `Morale; rating=X`, the value the raw rule string's
/// own `Morale(2)`. The table folds it into the SAME number as the Banner
/// family's bonus (`morale_bonus_of` = Banner best-of over unit + heroes
/// PLUS `morale_rating_of`'s rating best-of, solo_controller.gd:5638, the
/// walk :5642-5653; consumed at main.gd:8586; stamped as one dict value,
/// battle_sim.gd:1598). The core's capture twin read the Banner half only,
/// so every core-driven Morale carrier tested X too low. From 39 the twin
/// folds the rating into the SAME `morale_bonus` stamp and the rolled test
/// names it (rules-must-log). Below 39 every recorded game replays
/// byte-exact. One past every epoch in flight at stamping (35 on main; 36,
/// 37, 38 reserved); the value `CURRENT_RULES_EPOCH` is bumped to in the
/// same change. Call sites read THIS constant, never the literal or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_39_MORALE_RATING: u32 = 39;

/// The STEADFAST ROLL gate (14.09., sweep H — row `Steadfast`): the army-book
/// round-start recovery — "If a unit where all models have this rule is Shaken
/// at the beginning of the round, roll one die. On a 4+, it stops being
/// Shaken." (the registry `Steadfast; recover_target=4` entry) — was FREE in
/// the core: `round_start_refresh` cleared Shaken the moment `steadfast_active`
/// (or the dynamic grant) read true, no die, and the die-roll alias list
/// omitted Steadfast — while the table's own round-start beat
/// (`_solo_battleborn_recovery`, main.gd:10718-10740) rolls the REAL tray die:
/// `_solo_tray_roll(1, target, ..)`'s seeded `randi_range(1, 6)` per Shaken
/// eligible unit (main.gd:10730), read back by
/// `AiCombatMath.battleborn_recovers(face, target)` (main.gd:10731) — so the
/// unit stays Shaken a third of the time. From 40 the core rolls the SAME die
/// from the SAME stream shape (one `GodotRng` face per Shaken eligible unit at
/// the round boundary, roster order) the playout already answers the
/// Battleborn aliases with (`battleborn_recovery_roll`, arbitration.rs), and
/// the target rides the entry's OWN `recover_target` (the alias stamp's
/// Steadfast arm, unit.rs) — never a literal. Below 40 the free clear stays
/// and every recorded game replays byte-exact. `40` is one past every
/// existing stamp (37 = `EPOCH_37_UNSTOPPABLE_AURA`, #957; 36/38/39 reserved
/// in flight), and the value `CURRENT_RULES_EPOCH` is bumped to in the same
/// change. Every call site reads THIS constant, not the literal `40` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_40_STEADFAST_ROLL: u32 = 40;

/// The BATTLEBORN ROLL gate (14.09., sweep E — row `Battleborn`): the plain
/// "Battleborn" entry (the registry `Battleborn; recover_target=4` entry,
/// gf/battle_brothers — the TUTORIAL faction) rode the wave-3 FREE clear:
/// `round_start_refresh` wiped Shaken the moment `battleborn_active` read
/// true, no die, and the die-roll alias stamp listed only the four
/// "Honor Code"/"Vale Oath"/"Vale Oath Boost"/"Unmovable" aliases (plus
/// "Steadfast" from 40) — never the plain name — while the table's own
/// round-start beat (`_solo_battleborn_recovery`) rolls the REAL tray die
/// for it exactly as for the aliases: `_solo_tray_roll(1, target, ..)`'s
/// seeded `randi_range(1, 6)` per Shaken eligible unit, read back by
/// `AiCombatMath.battleborn_recovers(face, target)` — so the unit stays
/// Shaken half the time. From 43 the plain entry joins the aliases: the
/// alias stamp resolves its OWN `recover_target` (the four-alias arm's
/// shape, lowest-wins), the free clear stands only below 43
/// (`battleborn_recovery_rolls` false), and the die leg
/// (`battleborn_recovery_roll`, arbitration.rs) rolls the seeded face the
/// table's `_solo_tray_roll` draws. Below 43 the free clear stays and every
/// recorded game replays byte-exact. `43` is one past every existing stamp
/// (41 = `EPOCH_41_SELF_DESTRUCT_SURVIVORS`, #963; 42 reserved in flight by
/// the surge-mark leg), and the value `CURRENT_RULES_EPOCH` is bumped to in
/// the same change. Every
/// call site reads THIS constant, not the literal `43` or
/// `CURRENT_RULES_EPOCH`.
pub const EPOCH_43_BATTLEBORN_ROLL: u32 = 43;

/// EPOCH 44 SURGE MARK (sweep C row `Surge Mark`, PR #958): "Once per
/// activation, before attacking, pick one enemy unit within 18" in line of
/// sight, which friendly units get Surge against once." The registry modelled
/// the name as a plain Surge alias, so both layers made the bearer a permanent
/// extra-hits machine against everyone (melee and shooting, every attack, the
/// whole game) and no enemy was ever marked — the printed pick was dead data.
/// From 44 the entry is a vs_target mark like its siblings (the Precision
/// marks #929, the Piercing marks #936): the attack seam (`tray_vs_marks`)
/// places it, `ctx_live` stamps the once-grant ("Surge") into
/// `Ctx::surge_mark_grant`, the two Surge folds read it against the marked
/// target only, and the exchange spends it. Below 44 the entry replays the
/// recorded permanent self-Surge (the stamp's own name-based fallback leg) and
/// the mark reads as absent. `44` is one past every existing stamp (43 =
/// `EPOCH_40_STEADFAST_ROLL`, #960; 39 = `EPOCH_39_MORALE_RATING`, #959; 38 =
/// `EPOCH_38_WATCHBORN_LATCH`, #955). Every call site reads THIS constant,
/// not the literal `41` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_44_SURGE_MARK: u32 = 44;

/// The CASTER BOOST gate (14.09., analysis/CASTER_SEAM_2026-09-14.md row 1,
/// DIVERGES 16:1x by reading): the table's caster spends spell tokens on the
/// cast roll — the caster's OWN leftover tokens are the FIRST boost source
/// (solo_controller.gd:4336-4342), then friendly casters and Spell
/// Accumulator batteries within the `Caster` rule's `aura_in` (18") in line
/// of sight (:4565-4625, the battery on its own 12" reach, a Shaken battery
/// refused per NML-936), +1 per token, clamped [2,6] (ai_spell.gd:105-107),
/// paid BEFORE the roll, one try per spell (:4387-4395), the spend policy
/// `plan_boost`'s marginal-EV calculus (ai_spell.gd:328-339). The core's
/// `cast_phase` rolled a flat 4+ and never spent a token on the boost, so
/// the net learned spells as coin flips. From 48 the cast sub-phase builds
/// the boost pool (`sim::caster_boost_pool`), plans the spend
/// (`sim::plan_caster_boost`), folds the boost into `spell::
/// cast_success_chance`'s second argument and pays it in the same order the
/// threshold rides. Below 48 the pool is empty, the plan is zeros and every
/// recorded game replays byte-exact. `48` is one past every epoch present at
/// the rebase (47 = `EPOCH_47_RENDING_SHOOTING_AURA`, #968; 46 =
/// `EPOCH_46_DISINTEGRATE_REGEN`, #967; the leg's earlier reservation 45 was
/// renumbered to CURRENT+1 per the epoch rules), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `48` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_48_CASTER_BOOST: u32 = 48;

/// The CASTER INTERFERENCE gate (14.09., analysis/CASTER_SEAM_2026-09-14.md
/// row 2, DIVERGES by reading): the OPPOSING side's casters holding spell
/// tokens within the `Caster` rule's `aura_in` (18") in line of sight of the
/// caster's unit may spend them to LOWER the announced cast one step per
/// token (ai_spell.gd:105-107, `cast_target`'s own +`maxi(interference, 0)`
/// fold), paid before the roll alongside the boost (solo_controller.gd:
/// 4377-4397, one try per spell), the spend policy `plan_interference`'s
/// deterministic mirrored marginal-EV calculus (ai_spell.gd:518-527 — the
/// boost calculus without the coin-flip clause, priced at the cast's own EV,
/// so an unpriced cast draws no counter). The table auto-plans it in both-AI
/// (:4379-4386) and prompts the human at resolve time otherwise (main.gd:
/// 3474-3478); the core had no reader anywhere, so the sim never priced
/// cast-vs-counterplay. From 49 the cast sub-phase builds the interference
/// pool (`sim::interference_pool`, the boost pool's opposing-side mirror),
/// plans the spend in the same one-shot plan as the boost and pays it in the
/// same order the threshold rides, one rules-must-log line per interfered
/// cast. Below 51 the pool is empty and every recorded game replays
/// byte-exact. `49` is one past every epoch present at write time (48 =
/// `EPOCH_48_CASTER_BOOST`, #966; 47 = `EPOCH_47_RENDING_SHOOTING_AURA`,
/// #968; 46 = `EPOCH_46_DISINTEGRATE_REGEN`, #967), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `49` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_51_CASTER_INTERFERENCE: u32 = 51;

/// The RENDING SHOOTING AURA gate (14.09., sweep G — row `Rending when
/// Shooting Aura`, TABLE-ONLY): the Utility-Buff aura's own grant
/// (`grants_rule: "Rending"`, `scope: "shooting"`, the bearer itself at
/// `range_in` 0) is stamped but consumed by nobody, so a core sim never gave
/// the bearer's SHOOTING profiles the wound-6 AP(+4) or the Regeneration
/// bypass the table stamps (ai_ev.gd:330-341 granted-or-direct,
/// main.gd:7104's bypass). From 47 `unit.rs::stamp_unit_strikers`'s
/// granted-or-direct Rending read consumes the aura's own entry: the
/// `grants_rule` lands on the profiles its `scope` names, one trace line per
/// profile that received the grant. Below 47 the aura replays
/// stamped-but-unconsumed, exactly as the sweep measured it. `47` is one past
/// every epoch reserved in flight at write time (44 the surge-mark leg, 45
/// the caster-boost leg, 46 the disintegrate leg), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `47` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_47_RENDING_SHOOTING_AURA: u32 = 47;

pub const EPOCH_25_ETHEREAL_BANDS: u32 = 25;

/// The D3" ACTIVATION PLACEMENT gate (14.09., sweep C rows Wave-Step/Wolfborn
/// plus sweep B row Rapid Blink — the `Bounding {place_d3 ..}` primitive): the
/// book's "When this unit is activated, you may place all models with this
/// rule in it anywhere fully within D3\" of their position." The table rolls
/// the die at the activation's head on its seeded stream
/// (solo_controller.gd:1688-1710) and values it as a move-band bonus; the
/// core replayed that band only through the RECORDED `bounding_d3` trace
/// (`sim::bounding_bonus_in`), so every fresh core-simulated game never
/// hopped and the carrier's reach ran short by up to the roll. From 26 a
/// FRESH sim (an act with no recorded `bounding_d3` trace) rolls its own
/// dice from the seeded stream and re-places the carrier BEFORE the move
/// with #930's free-placement scan (`deployment::vanguard_free_place`,
/// radius = the rolled inches). Below 26 the trace replay stays the whole
/// effect, byte-exact. Renumbered from the reserved 24 at rebase (#941's
/// 25 landed first) per the epoch rules. Every call site reads THIS
/// constant, not the literal `26` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_26_PLACE_D3: u32 = 26;

/// The SCRAPPER BOOST gate (14.09., DEAD_PARAM_TRIAGE_2026-09-14 dead-knob
/// row 1): `gf` `Scrapper Boost` carries `reroll_save_from: 5` — the Bane
/// family's widened save re-roll window (successful saves of 5-6 re-roll
/// strictly past the entry's `over_in`, exactly "Mischievous Boost"'s
/// epoch-6 shape) — but no reader anywhere opened it: the stamp reads
/// `reroll_save_low` only, so the bearer re-rolled fewer saves than the
/// book gives. From 30 the widening stamps through the same seam under its
/// own param name; below 30 the bearer keeps the base 6s-only window,
/// byte-exact. `30` is one past every existing stamp (29 = the strafing
/// leg's, 28 = the re-deployment leg's, both reserved in flight), and the
/// value `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call
/// site reads THIS constant, not the literal `30` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_30_SCRAPPER_BOOST: u32 = 30;

/// The class-fix gate itself: true once `rules_epoch` has reached `since_epoch`.
/// `cond_ap_dice` and `versatile_reach` are re-expressed through it at
/// `since_epoch: 1` as `knob || rule_on(rules_epoch, 1)` at their call sites,
/// so a pre-epoch record with the boolean at its legacy `false` (or the key
/// altogether absent) still replays exactly as before this fix, while a fresh
/// record stamping `rules_epoch: CURRENT_RULES_EPOCH` gets both rules
/// regardless of what the two booleans read. A future port with no legacy
/// reading should call this directly instead of adding a third boolean knob.
pub fn rule_on(rules_epoch: u32, since_epoch: u32) -> bool {
    rules_epoch >= since_epoch
}

/// Resolve the epoch a record actually played at. The explicit knob wins;
/// Gen-2 recorded it beside prescreen.knobs, and later unstamped arena records
/// identify their playing build under prescreen.core_build. Older records are 0.
pub fn record_rules_epoch(knobs: &serde_json::Value, prescreen: &serde_json::Value) -> u32 {
    [knobs.get("rules_epoch"), prescreen.get("rules_epoch"),
        prescreen.get("core_build").and_then(|b| b.get("rules_epoch"))]
        .into_iter()
        .flatten()
        .find_map(|v| v.as_u64().and_then(|n| u32::try_from(n).ok()))
        .unwrap_or(0)
}

/// The `melee_reach` knob's two settings — written the way `sighting` is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MeleeReach {
    /// `combat::effective_attacks` scaled by the whole unit's `alive` count.
    #[default]
    All,
    /// GF v3.5.1 p.9 "Who Can Strike": only models within 2" of an enemy model.
    Table,
}

/// The `sighting` knob's two settings — the header writes them as strings, the
/// way `dice` writes `"expected"` / `"table"`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Sighting {
    /// `BattleSim._profiles_of` (battle_sim.gd:714-749): the whole unit fires.
    #[default]
    Unit,
    /// `main._run_ai_shooting` :3131-3134: per (member, weapon), the models with
    /// both range and line of sight (GF Advanced Rules v3.5.1 p.8).
    Model,
}

/// `#[serde(default)]` on a `bool` is `false`; `charge_gate` defaults the other
/// way, because a header that predates the field came from a gated caller.
fn yes() -> bool {
    true
}

/// NML-1134 — `#[serde(default)]` on the vocabulary version: absent means a
/// corpus recorded before the stamp, and every one of those is version 2.
fn legacy_vocab_version() -> i64 {
    crate::rows::LEGACY_VOCAB_VERSION
}

/// Wave 6 (`advancek`) — `#[serde(default)]` on `menu_advance_k`: an absent key
/// is a corpus recorded before the knob, whose menu carried exactly one patient
/// safe-advance candidate.
fn one() -> usize {
    1
}

/// NML-1134 — the vocabulary version one act header asks to be replayed under,
/// read through the SAME serde default every corpus reader uses. Python calls
/// it as `nml_core.vocab_version_of_header(header)`; the Rust tests call it
/// directly; neither owns a second copy of the "absent means 2" rule.
pub fn vocab_version_of_header(text: &str) -> i64 {
    #[derive(Deserialize)]
    struct KnobsOnly {
        #[serde(default)]
        knobs: Knobs,
    }
    serde_json::from_str::<KnobsOnly>(text)
        .map(|k| k.knobs.rule_vocab_version)
        .unwrap_or(crate::rows::LEGACY_VOCAB_VERSION)
}

impl Default for Knobs {
    fn default() -> Self {
        Knobs {
            top_k: 6,
            horizon: 2,
            tail_cap_p1: 0,
            tail_cap_p2: 0,
            leaf_opener_only: false,
            imagined_round_end: true,
            depth_discount: 0.5,
            seat_mode: 0,
            playout_margin: 0.02,
            playout_rich: true,
            reply_by_net: false,
            reply_top_k: 0,
            reply_horizon: 0,
            reply_pool_cap: 0,
            reply_menu_restricted: false,
            seam_cast: false,
            seam_spacing: false,
            seam_path: false,
            hero_last: false,
            cast_fold: false,
            charge_gate: true,
            menu_targets: false,
            menu_holders: false,
            menu_advance_k: 1,
            menu_all_targets: 0,
            menu_advance_obj_shoot: false,
            charge_needs_path: false,
            playout_rush_k: 1,
            hero_attach: false,
            charge_landing: false,
            sighting: Sighting::Unit,
            movement: false,
            los_model: false,
            menu_los: false,
            menu_wide: false,
            moved_shoot: false,
            move_rigid: false,
            route_root: false,
            dangerous: true,
            engage_fold: false,
            dangerous_end_morale: false,
            dangerous_replay: None,
            opener_by_finish: false,
            no_end_threat: false,
            fire_in_range_only: false,
            hero_counts_in_size: false,
            fearless_roll_when_shaken: false,
            casualties_bearers_last: false,
            range_by_base_edge: false,
            morale_by_probability: false,
            reply_v2: false,
            reply_skip_activated: false,
            reply_hold_gate: false,
            reply_threat_by_speed: false,
            // NML-1134: the CORPUS reading — a header with no `knobs` block at
            // all predates the stamp just as surely as one with an unstamped
            // block does. A caller that plays a FRESH game stamps
            // `rows::RULE_VOCAB_VERSION` itself.
            rule_vocab_version: crate::rows::LEGACY_VOCAB_VERSION,
            eval_variant: 0,
            strength_by_points: false,
            search_mode: SearchMode::OnePly,
            tree_leaf: TreeLeaf::Blend,
            tree_dice: TreeDice::Ev,
            tree_budget: default_tree_budget(),
            tree_samples: default_tree_samples(),
            tree_batch: default_tree_batch(),
            tree_opp_batch: 0,
            tree_opp_shuffle: 0,
            tree_wall_ms: 0,
            pool_wall_ms: 0,
            deadline_us: 0,
            deadline_after_preselect: false,
            tree_widen: 0.0,
            tree_puct: 0.0,
            tree_opponent_own_leaf: false,
            melee_reach: MeleeReach::All,
            consolidate: false,
            cond_ap_dice: false,
            versatile_reach: false,
            rules_epoch: 0,
            bands_prefolded: false,
            grid_k: 0,
            grid_units: 0,
            grid_proposer: 0,
            grid_margin: 0.0,
            grid_shuffle: 0,
            grid_batch: 0,
            grid_budget: 0,
        }
    }
}

#[derive(Deserialize)]
struct Header {
    profiles: Ordered<Profile>,
    /// S5 (SPAWN_DESIGN_2026-09-08 §3.1) — the recorder's resolved NAMED-unit
    /// profiles, keyed `spawn:<carrier_key>:<rule_string>`, same unit shape.
    /// Optional; absent below the `EPOCH_8_PLANNER_MENU` gate and in every
    /// record with no Spawn carrier.
    #[serde(default)]
    spawn_profiles: Option<Ordered<Profile>>,
    #[serde(default)]
    terrain: Option<PlainTerrain>,
    #[serde(default)]
    knobs: Knobs,
    /// The TABLE recorder's books block (`act_recorder.gd:266-268` — written
    /// unconditionally inside the always-written header dict; no writer in
    /// `core/nml-core/src` emits it, the core's own header shape is
    /// `rows.rs:679`). The PRESENCE is the signal, the value opaque on
    /// purpose: `books` present ⇒ recorded by the table ⇒ the record's
    /// `bands` already carry every grant (`battle_sim.gd:1707 ->
    /// move_bands_for_props`), so the replay-aware
    /// `sim::solo_move_grant_delta_in` adds nothing. Read once in
    /// `header_of` into `Knobs::bands_prefolded`.
    #[serde(default)]
    books: Option<serde_json::Value>,
    /// Wave 6 — the table's mission stamp (`act_recorder.gd`: id + catalog
    /// family + scoring, from the arena selector's `NML_MISSION`). Optional:
    /// every header recorded before the stamp existed and the core's own
    /// header shape parse as `None`.
    #[serde(default)]
    mission: Option<Mission>,
}

/// One entry of `trace.scored` — `AiPlanner.plan_with_rollout` ai_planner.gd:
/// 150-155, written AFTER the sort, so the array is in ranked order and `idx`
/// is the candidate's position in the unsorted build order.
#[derive(Debug, Clone, Deserialize)]
pub struct Scored {
    pub idx: i64,
    pub unit: String,
    pub kind: i64,
    pub score: f64,
}

/// One entry of `trace.rs` — ai_planner.gd:203-204: the ROLLOUT value of one
/// pool candidate, in the order the pool was played out. This is the number
/// milestone M2-2 reproduces.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct RolloutValue {
    pub idx: i64,
    pub rs: f64,
}

/// `AiPlanner.plan_with_rollout`'s `expectation` — ai_planner.gd:273.
#[derive(Debug, Clone, Copy, Default, Deserialize)]
pub struct Expectation {
    #[serde(default)]
    pub before: f64,
    #[serde(default)]
    pub after: f64,
}

/// The pick's `runner_up` — the SECOND best rolled candidate (:274). The
/// GDScript writes an EMPTY dictionary when the pool held a single candidate,
/// which is why `action` is optional rather than the whole record.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct RunnerRec {
    #[serde(default)]
    pub unit_key: String,
    #[serde(default)]
    pub action: Option<Candidate>,
    #[serde(default)]
    pub score: f64,
}

/// The RECORDED pick — the dictionary `plan_with_rollout` returned
/// (ai_planner.gd:272-275), minus `intent` (a battle-log label, not a decision).
/// This is the M2-3 oracle.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct PickRec {
    #[serde(default)]
    pub used: bool,
    #[serde(default)]
    pub unit_key: String,
    #[serde(default)]
    pub action: Option<Candidate>,
    #[serde(default)]
    pub expectation: Expectation,
    #[serde(default)]
    pub waits: i64,
    #[serde(default)]
    pub rolled_units: Vec<String>,
    #[serde(default)]
    pub runner_up: RunnerRec,
}

/// `AiPlanner.trace` — the search bookkeeping `AiActRecorder.finish` attaches
/// (act_recorder.gd:80-82). `arbitration` carries the stochastic arbitration's
/// own verdict (:263-264); M2-4 reproduces it from the recorded `sig`, and a
/// corpus that never triggered it must still be able to PROVE that, so the field
/// is read either way.
#[derive(Debug, Default, Deserialize)]
struct PlainTrace {
    #[serde(default)]
    menus: HashMap<String, Vec<Candidate>>,
    #[serde(default)]
    scored: Vec<Scored>,
    /// The `idx` of every candidate that survived the prefilter, in pool order.
    #[serde(default)]
    pool_idx: Vec<i64>,
    #[serde(default)]
    rs: Vec<RolloutValue>,
    /// Positions in the SORTED `scored` array, not `idx` values (:210, :217).
    #[serde(default = "neg_one")]
    best_idx: i64,
    #[serde(default = "neg_one")]
    runner_idx: i64,
    /// `null` unless the stochastic arbitration decided that pick.
    #[serde(default)]
    arbitration: serde_json::Value,
    /// Tree search knob — present only on a pick the tree made.
    #[serde(default)]
    tree: Option<PlainTreeTrace>,
}

/// `trace.tree`'s replay half: the leaf evaluations the search completed.
#[derive(Debug, Deserialize)]
struct PlainTreeTrace {
    completed: usize,
}

/// `trace.arbitration` (ai_planner.gd:263-264) as a typed record — the M2-4
/// oracle. `sig` is `_playout_sig`'s value AT RECORD TIME and is an INPUT to the
/// port, not something it recomputes (see `arbitration.rs`'s module header).
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct ArbitrationRec {
    pub sig: i64,
    /// Playouts run PER BRANCH: 3, 5 or 7.
    pub n: i64,
    pub sum_b: f64,
    pub sum_r: f64,
    pub swapped: bool,
}

fn neg_one() -> i64 {
    -1
}

/// The per-act `"statics"` object — `AiActRecorder.begin` act_recorder.gd:62-63.
/// These are settings the search read off class statics rather than off the
/// state, so a replay that does not restore them replays a different search.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct ActStatics {
    /// `AiPlanner.opener_seat` — true when OUR side opened the current round.
    /// `_blend_score` (:439-441) branches on it under seat modes 1 and 2.
    #[serde(default)]
    pub opener_seat: bool,
    #[serde(default)]
    pub playout_search: bool,
    /// `AiMissionEval.fit_mode` — `score.rs` ports the HAND half only.
    #[serde(default)]
    pub fit_mode: bool,
    /// `AiPlanner.playout_net` — a NON-empty dict routes every imagined
    /// activation through a trained network (`_policy_step_net`, :627-645),
    /// which this port declines rather than approximates.
    #[serde(default)]
    pub playout_net: serde_json::Value,
    /// NML-1158b step 5 — `AiPlanner.policy_mode` (design §4/§7 step 5):
    /// "order" re-ranks WITHIN each unit's own PHASE-2 slots by the trained
    /// policy net (`policy.rs`); absent/`"off"` is the recorded default and
    /// byte-identical to before this field existed.
    #[serde(default)]
    pub policy_mode: PolicyMode,
}

/// The `policy_mode` knob's two settings — same string-enum pattern as
/// `Sighting`. "pick" (the net AS the scorer, design §4) is out of scope
/// until ORDER mode clears its own 600-gate, so this build reads only these.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PolicyMode {
    #[default]
    Off,
    Order,
}

/// The `search_mode` knob: today's one-ply search or the recursive tree.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SearchMode {
    #[default]
    OnePly,
    Tree,
}

/// The `tree_leaf` knob: how a non-terminal frontier state is valued.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TreeLeaf {
    #[default]
    Blend,
    Terminal,
}

/// The `tree_dice` knob: the tree's chance model.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TreeDice {
    #[default]
    Ev,
    Tray,
}

fn default_tree_budget() -> i64 {
    128
}

fn default_tree_samples() -> i64 {
    4
}

fn default_tree_batch() -> i64 {
    8
}

impl ActStatics {
    /// True when the recording used the heuristic playout this port implements.
    pub fn heuristic_playout(&self) -> bool {
        match &self.playout_net {
            serde_json::Value::Null => true,
            serde_json::Value::Object(m) => m.is_empty(),
            _ => false,
        }
    }
}

#[derive(Deserialize)]
struct PlainAct {
    round: i64,
    player: i64,
    state: PlainState,
    #[serde(default)]
    pool: Vec<String>,
    /// `AiActRecorder._charge_illegal_matrix` — "attacker|victim" -> the live
    /// gate's answer at the pair's ROOT gap.
    #[serde(default)]
    charge_illegal: HashMap<String, bool>,
    /// `AiActRecorder._charge_illegal_grid` — "attacker|victim" -> 29 answers at
    /// gaps 0", 0.5", ... 14".
    #[serde(default)]
    charge_illegal_grid: HashMap<String, Vec<bool>>,
    #[serde(default)]
    trace: PlainTrace,
    #[serde(default)]
    statics: ActStatics,
    #[serde(default)]
    pick: Option<PickRec>,
}

/// `AiActRecorder.GATE_GRID_STEPS` / `GATE_GRID_STEP_IN` — act_recorder.gd:239-240.
pub const GATE_GRID_STEPS: usize = 29;
pub const GATE_GRID_STEP_IN: f64 = 0.5;

#[derive(Debug)]
pub struct Act {
    pub round: i64,
    pub player: i64,
    pub state: State,
    /// The un-activated units the search chose between, in the state's own order.
    pub pool: Vec<String>,
    pub charge_illegal: HashMap<String, bool>,
    pub charge_illegal_grid: HashMap<String, Vec<bool>>,
    /// The RECORDED menu per pool unit — the oracle `menu::candidates` replays.
    pub menus: HashMap<String, Vec<Candidate>>,
    /// Every (unit, candidate) pair the 1-ply prefilter scored, RANKED.
    pub scored: Vec<Scored>,
    /// The `idx` of every candidate that reached a full rollout, in pool order.
    pub pool_idx: Vec<i64>,
    /// The RECORDED rollout value per pool candidate — the M2-2 oracle.
    pub rs: Vec<RolloutValue>,
    pub best_idx: i64,
    pub runner_idx: i64,
    pub statics: ActStatics,
    /// `trace.arbitration` — `Value::Null` unless the playout arbitration fired.
    pub arbitration: serde_json::Value,
    pub pick: Option<PickRec>,
    /// Tree search knob — `trace.tree.completed`, the leaf evaluations a tree
    /// pick completed; a replay forces it as the budget. `None` elsewhere.
    pub tree_completed: Option<usize>,
}

impl Act {
    /// The typed `trace.arbitration`, or `None` when it did not fire on this act.
    /// A present-but-malformed record panics rather than reading as "absent":
    /// a gate that quietly skipped it would report green on nothing.
    pub fn arbitration_rec(&self) -> Option<ArbitrationRec> {
        if self.arbitration.is_null() {
            return None;
        }
        Some(
            serde_json::from_value(self.arbitration.clone())
                .unwrap_or_else(|e| panic!("trace.arbitration: {e}")),
        )
    }
}

#[derive(Debug)]
pub struct ActCorpus {
    /// The HEADER table — the deployment reading. The table an act is actually
    /// replayed on is `act.state.profiles`, which carries that activation's own
    /// dynamic reading (NML-1073 M2-5b); ask `nml_core::act_statics` for the
    /// matching per-act `UnitStatic` closures rather than deriving them here.
    pub profiles: Rc<Profiles>,
    pub terrain: Terrain,
    pub knobs: Knobs,
    pub acts: Vec<Act>,
}

/// The header's mission stamp — `act_recorder.gd` writes id + the catalog's
/// family and scoring from the arena selector's `NML_MISSION`. Only `id` is
/// required when the block is present: a stamp without one is a malformed
/// record and refuses the whole header, loudly.
#[derive(Debug, Clone, Deserialize)]
pub struct Mission {
    pub id: String,
    #[serde(default)]
    pub family: String,
    #[serde(default)]
    pub scoring: String,
    /// Attack & Defend only: P1's role ("attacker"/"defender") and the match length; absent otherwise.
    #[serde(default)]
    pub role_p1: String,
    #[serde(default)]
    pub rounds: i64,
}

/// The header line's three products — the profile table, the board and the
/// search knobs. Factored out of `read_acts` so a caller that never sees the
/// file (the Python seam, NML-1073 M3-1) builds them from the SAME code path
/// instead of a second reading of the header.
#[derive(Debug)]
pub struct ActHeader {
    pub profiles: Rc<Profiles>,
    pub terrain: Terrain,
    pub knobs: Knobs,
    /// The stamped mission, or `None` for every header written before the
    /// stamp existed (and the core's own header shape). Read `mission_id()`,
    /// not this field, when you need an id to grade by.
    pub mission: Option<Mission>,
}

impl ActHeader {
    /// The stamped mission id, or "duel" — the fallback the table stamps for
    /// a game that chose no mission, and what every header recorded before
    /// the stamp existed reads as.
    pub fn mission_id(&self) -> &str {
        self.mission.as_ref().map(|m| m.id.as_str()).unwrap_or("duel")
    }
}

/// Parses one act-corpus header line (`{"kind":"header", ...}`).
pub fn read_act_header(text: &str) -> Result<ActHeader, String> {
    let raw: serde_json::Value = serde_json::from_str(text).map_err(|e| format!("act header: {e}"))?;
    // Parse the typed header from the original text: Ordered<Profile> must
    // retain JSON insertion order, which serde_json::Value would sort.
    for (key, allowed) in [
        ("search_mode", &["oneply", "tree"][..]),
        ("tree_leaf", &["blend", "terminal"][..]),
        ("tree_dice", &["ev", "tray"][..]),
    ] {
        if let Some(v) = raw["knobs"].get(key).and_then(|v| v.as_str()) {
            if !allowed.contains(&v) {
                return Err(format!("{key} {v:?}: unknown setting (only {allowed:?} exist)"));
            }
        }
    }
    let mut header: Header = serde_json::from_str(text).map_err(|e| format!("act header: {e}"))?;
    header.knobs.rules_epoch = record_rules_epoch(&raw["knobs"], &raw["prescreen"]);
    // The evolved-eval seam: variant 0 (today's frozen eval) and variant 1 (the
    // referee-shaped marker term, ledger row 7) have registered arms in
    // `score::score_hand_variant`. A header asking for anything else is
    // rejected HERE, loudly, rather than silently playing variant 0 or
    // panicking deep inside a rollout.
    // Variant 2 (wave C G-AB) is variant 0 without the C7 carry term; variant 3
    // (mission-play lane) is the `round_vp` currency.
    if !matches!(header.knobs.eval_variant, 0..=4) {
        return Err(format!(
            "eval_variant {}: no registered arm (only 0 to 4 exist)",
            header.knobs.eval_variant
        ));
    }
    if header.knobs.tree_widen.is_nan() || header.knobs.tree_widen < 0.0 {
        return Err(format!("tree_widen {}: must be >= 0 (0 opens every child first)", header.knobs.tree_widen));
    }
    if header.knobs.tree_puct.is_nan() || header.knobs.tree_puct < 0.0 {
        return Err(format!("tree_puct {}: must be >= 0 (0 = off)", header.knobs.tree_puct));
    }
    if header.knobs.deadline_us < 0 {
        return Err(format!("deadline_us {}: must be >= 0 (0 = off)", header.knobs.deadline_us));
    }
    if header.knobs.search_mode == SearchMode::Tree
        && (header.knobs.tree_budget < 1 || header.knobs.tree_samples < 1 || header.knobs.tree_batch < 1)
    {
        return Err(format!(
            "search_mode tree: tree_budget {}, tree_samples {}, tree_batch {} must all be >= 1",
            header.knobs.tree_budget, header.knobs.tree_samples, header.knobs.tree_batch
        ));
    }
    header_of(header).map_err(|e| format!("act header: {e}"))
}

fn header_of(header: Header) -> Result<ActHeader, String> {
    // `books` present ⇒ a table recording ⇒ the recorded bands carry every
    // grant (see `Header::books`). Core-written records and every fixture
    // have no `books`, so the flag reads back `false` there.
    let bands_prefolded = header.books.is_some();
    let terrain = match &header.terrain {
        Some(t) => Terrain::build(t),
        None => Terrain::absent(),
    };
    let mut profiles = Profiles::default();
    for (k, p) in header.profiles.0 {
        profiles.index.insert(k, profiles.list.len());
        profiles.list.push(p);
    }
    crate::io::index_spawn_profiles(
        &mut profiles,
        header.spawn_profiles,
        "",
        header.knobs.rules_epoch,
    )?;
    Ok(ActHeader {
        profiles: Rc::new(profiles),
        terrain,
        knobs: Knobs { bands_prefolded, ..header.knobs },
        mission: header.mission,
    })
}

/// Reads `acts.jsonl` into the profile table, the board and the activations.
pub fn load_acts(path: &str) -> Result<ActCorpus, String> {
    let file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
    read_acts(BufReader::new(file), path)
}

/// Same, from any reader — `origin` only labels the error messages.
pub fn read_acts<R: BufRead>(reader: R, origin: &str) -> Result<ActCorpus, String> {
    let path = origin;
    let mut lines = reader.lines();
    let head = lines
        .next()
        .ok_or_else(|| format!("{path}: empty file"))?
        .map_err(|e| e.to_string())?;
    let ActHeader { profiles, terrain, knobs, .. } =
        read_act_header(&head).map_err(|e| format!("{path}:1 {e}"))?;
    // NML-1073 M2-5b: the header table is the DEPLOYMENT reading. Every act
    // carries its own reading of the fields a live game rewrites, and the state
    // that act is replayed on gets the table THAT says — interned, so acts that
    // read alike share one table (and one derived `UnitStatic` closure).
    let mut profile_cache = ProfileCache::new(Rc::clone(&profiles));
    let mut cache: Option<Rc<Roster>> = None;
    let mut acts = Vec::new();
    for (i, line) in lines.enumerate() {
        let line = line.map_err(|e| e.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let pa: PlainAct =
            serde_json::from_str(&line).map_err(|e| format!("{path}:{}: {e}", i + 2))?;
        let roster = roster_of(&pa.state, &profiles, &mut cache)?;
        spawn_templates_of(&pa.state, &profiles, knobs.rules_epoch)?;
        let eff = profile_cache.effective(&roster, &pa.state.dyn_profiles());
        acts.push(Act {
            round: pa.round,
            player: pa.player,
            state: state_of(pa.state, &eff, roster, knobs.rules_epoch),
            pool: pa.pool,
            charge_illegal: pa.charge_illegal,
            charge_illegal_grid: pa.charge_illegal_grid,
            menus: pa.trace.menus,
            scored: pa.trace.scored,
            pool_idx: pa.trace.pool_idx,
            rs: pa.trace.rs,
            best_idx: pa.trace.best_idx,
            runner_idx: pa.trace.runner_idx,
            statics: pa.statics,
            arbitration: pa.trace.arbitration,
            pick: pa.pick,
            tree_completed: pa.trace.tree.map(|t| t.completed),
        });
    }
    Ok(ActCorpus { profiles, terrain, knobs, acts })
}

#[cfg(test)]
mod tests {
    /// A game recorded at epoch 97 builds its units without the gains pass (the Python list loader reads this gate; the
    /// by-value Banner check at 97 is `test_command_gains.py::test_a_record_at_epoch_97_builds_no_banner`).
    #[test]
    fn a_record_at_epoch_97_builds_without_the_command_gains() {
        assert!(!rule_on(97, super::EPOCH_98_COMMAND_GAINS), "97: no gains pass");
        assert!(rule_on(98, super::EPOCH_98_COMMAND_GAINS), "98: the gains pass");
    }

    /// The command-upgrade gains pass starts at 98: a record at 97 builds its units without it, a fresh one with it.
    #[test]
    fn command_gains_start_at_98() {
        assert_eq!(super::EPOCH_98_COMMAND_GAINS, 98);
        assert!(!rule_on(97, super::EPOCH_98_COMMAND_GAINS), "a record at 97 replays as recorded");
        assert!(rule_on(CURRENT_RULES_EPOCH, super::EPOCH_98_COMMAND_GAINS), "a fresh play_game() stamps it on");
    }

    use super::{
        read_act_header, record_rules_epoch, rule_on, MeleeReach, SearchMode, TreeDice, TreeLeaf, CURRENT_RULES_EPOCH, EPOCH_3_TABLE_RULES,
        EPOCH_4_TABLE_RULES, EPOCH_5_TABLE_RULES, EPOCH_6_TABLE_RULES, EPOCH_7_TABLE_RULES, EPOCH_73_V36,
        EPOCH_74_CLIMB_COST, EPOCH_75_TABLE_FIXES, EPOCH_76_MOVE_FIXES, EPOCH_77_CHARGE_CAP, EPOCH_78_FLIER_CUT, EPOCH_79_EV_MOVED_ROUND, EPOCH_80_ROLLOUT_CUMBERSOME,
        EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF, EPOCH_82_IGNORE_BY_NAME, EPOCH_83_LONE_HERO_TARGET, EPOCH_84_IGNORE_GROUPS, EPOCH_85_INDIRECT_GATE,
        EPOCH_86_VOLLEY_HEIGHT_REACH, EPOCH_87_WALKED_DANGEROUS, EPOCH_88_SPLIT_LONE_HERO, EPOCH_89_SHARED_BEARERS,
        EPOCH_90_JOINED_ONE_RECOVERY, EPOCH_91_JOINED_HERO_FATIGUE, EPOCH_92_MELEE_CAUSES, EPOCH_93_DANGER_RULES_RIDER,
        EPOCH_94_PARITY_BATCH, EPOCH_95_PARITY_BATCH, EPOCH_96_PARITY_BATCH,
    };

    #[test]
    fn unit_imprecise_gate_starts_at_96() {
        assert_eq!(super::EPOCH_96_PARITY_BATCH, 96);
        assert!(!rule_on(95, super::EPOCH_96_PARITY_BATCH), "a record at 95 keeps the unit-borne Imprecise unread");
        assert!(rule_on(96, super::EPOCH_96_PARITY_BATCH));
    }

    #[test]
    fn unit_bane_alias_gate_starts_at_96() {
        assert_eq!(super::EPOCH_96_PARITY_BATCH, 96);
        assert!(!rule_on(95, super::EPOCH_96_PARITY_BATCH), "a record at 95 keeps the flat unit alias read");
        assert!(rule_on(96, super::EPOCH_96_PARITY_BATCH));
    }

    #[test]
    fn takedown_shot_per_model_gate_starts_at_96() {
        assert_eq!(super::EPOCH_96_PARITY_BATCH, 96);
        assert!(!rule_on(95, super::EPOCH_96_PARITY_BATCH), "a record at 95 keeps the single bonus die");
        assert!(rule_on(96, super::EPOCH_96_PARITY_BATCH));
    }

    #[test]
    fn spotter_roll_record_gate_starts_at_96() {
        assert_eq!(super::EPOCH_96_PARITY_BATCH, 96);
        assert!(!rule_on(95, super::EPOCH_96_PARITY_BATCH), "a record at 95 keeps the silent spotter draw");
        assert!(rule_on(96, super::EPOCH_96_PARITY_BATCH));
    }

    #[test]
    fn enhanced_primal_needs_primal_gate_starts_at_96() {
        assert_eq!(super::EPOCH_96_PARITY_BATCH, 96);
        assert!(!rule_on(95, super::EPOCH_96_PARITY_BATCH), "a record at 95 keeps the grant's own extras group");
        assert!(rule_on(96, super::EPOCH_96_PARITY_BATCH));
    }

    #[test]
    fn upr_needs_shot_gate_starts_at_95() {
        assert_eq!(super::EPOCH_95_PARITY_BATCH, 95);
        assert!(!rule_on(94, super::EPOCH_95_PARITY_BATCH), "a record at 94 keeps the die of a volley with nothing in reach");
    }

    /// meleefix: the consolidation plan is read from 96 on; a record at 95 keeps the old greedy goal.
    #[test]
    fn consolidate_plan_gate_starts_at_96() {
        assert_eq!(super::EPOCH_96_PARITY_BATCH, 96);
        assert!(!rule_on(95, super::EPOCH_96_PARITY_BATCH), "a record at 95 keeps the old greedy consolidation goal");
        assert!(rule_on(96, super::EPOCH_96_PARITY_BATCH));
    }

    /// Heightfield plan step 7 (the placeholder became the frozen batch epoch at the 94 bump): the gate is 94, on in a fresh game, off one
    /// epoch below.
    #[test]
    fn the_height_gate_is_on_from_the_epoch_94_batch() {
        use super::EPOCH_94_PARITY_BATCH as gate;
        assert_eq!(gate, 94);
        assert!(rule_on(CURRENT_RULES_EPOCH, gate), "a fresh play_game() reads the heightfield gate");
        assert!(!rule_on(gate - 1, gate) && rule_on(gate, gate));
    }

    /// The CLASS FIX's one gate (external review 03.09. item 3 / F9):
    /// `rule_on` is a plain `>=`, tested at its own boundary — `since_epoch`
    /// itself turns a rule on, one below it does not, and above it stays on.
    /// Cover from sight blockers is off for every record stamped 94 or below.
    #[test]
    fn cover_screen_gate_starts_at_95() {
        assert_eq!(super::EPOCH_95_PARITY_BATCH, 95);
        assert!(!rule_on(94, super::EPOCH_95_PARITY_BATCH), "a record at 94 replays terrain-only cover");
        assert!(rule_on(95, super::EPOCH_95_PARITY_BATCH), "a record at 95 reads cover from sight blockers");
    }

    #[test]
    fn volley_deadly_stops_gate_starts_at_95() {
        assert_eq!(super::EPOCH_95_PARITY_BATCH, 95);
        assert!(!rule_on(94, super::EPOCH_95_PARITY_BATCH), "a record at 94 rolls every Deadly wound's ignore dice");
    }

    #[test]
    fn volley_defence_declared_gate_starts_at_95() {
        assert_eq!(super::EPOCH_95_PARITY_BATCH, 95);
        assert!(!rule_on(94, super::EPOCH_95_PARITY_BATCH), "a record at 94 drops the defence reads of a wiped target");
        let at = |e: u32| crate::unit::Ctx { rules_epoch: e, guarded: true, shielded: true, stealth: true, ..Default::default() }.wiped();
        let (old, new) = (at(94), at(super::EPOCH_95_PARITY_BATCH));
        assert!(!old.guarded && !old.shielded && !old.stealth, "94: a wiped target lends nothing");
        assert!(new.guarded && new.shielded, "95: Guarded and Shielded stay as declared");
        assert!(!new.stealth, "95: the to-hit penalty still drops");
    }

    #[test]
    fn wiped_to_hit_declared_gate_starts_at_97() {
        assert_eq!(super::EPOCH_97_WIPED_TO_HIT_DECLARED, 97);
        assert!(!rule_on(96, super::EPOCH_97_WIPED_TO_HIT_DECLARED), "a record at 96 replays as recorded");
        assert!(rule_on(CURRENT_RULES_EPOCH, super::EPOCH_97_WIPED_TO_HIT_DECLARED), "a fresh play_game() stamps it on");
        let at = |e: u32| crate::unit::Ctx { rules_epoch: e, stealth: true, evasive: true, aircraft_hit_penalty: 1, ..Default::default() }.wiped();
        let (old, new) = (at(96), at(super::EPOCH_97_WIPED_TO_HIT_DECLARED));
        assert!(!old.stealth && !old.evasive && old.aircraft_hit_penalty == 0, "96: a wiped target drops its to-hit penalties");
        assert!(new.stealth && new.evasive && new.aircraft_hit_penalty == 1, "97: they hold for the weapons still to fire");
        assert!(!new.fortified && !new.regeneration, "97: the per-hit carrier reads still drop");
    }

    #[test]
    fn rule_on_is_true_from_its_since_epoch_onward() {
        assert!(!rule_on(0, 1), "epoch 0 is before since_epoch 1: off");
        assert!(rule_on(1, 1), "epoch reaches its own since_epoch: on");
        assert!(rule_on(2, 1), "epoch past its since_epoch: on");
        assert!(!rule_on(0, CURRENT_RULES_EPOCH), "epoch 0 is before every future port");
    }

    /// Wave 4 (epoch 6 -> 7): bumping the live epoch must NOT shift the six
    /// families frozen at epoch 3. A record stamped `rules_epoch: 3` keeps
    /// all six ON (`EPOCH_3_TABLE_RULES`) while getting none of wave 4's
    /// rules yet (`EPOCH_7_TABLE_RULES`) — and a fresh header stamps the
    /// new, bumped epoch.
    #[test]
    fn epoch_7_bump_keeps_the_six_epoch_3_families_frozen() {
        assert_eq!(CURRENT_RULES_EPOCH, 108, "the live epoch is EPOCH_108_BLAST_EVEN");
        assert_eq!(EPOCH_3_TABLE_RULES, 3, "the six epoch-3 families stay frozen at 3, forever");
        assert!(
            rule_on(3, EPOCH_3_TABLE_RULES),
            "a record at epoch 3 still replays with the six families ON"
        );
        assert!(
            !rule_on(3, EPOCH_7_TABLE_RULES),
            "a record at epoch 3 gets none of wave 4's rules"
        );
        let head = r#"{"kind":"header","profiles":{},"knobs":{"rules_epoch":108}}"#;
        let header = read_act_header(head).expect("a fresh-epoch header parses");
        assert_eq!(
            header.knobs.rules_epoch, CURRENT_RULES_EPOCH,
            "a fresh play_game() now stamps the bumped epoch, 108"
        );
    }

    /// Epoch 75 (core ports of #2612/#2613/#2615): a record stamped 74 keeps every gate of the
    /// three ports closed, a fresh record at 75 opens them, and the 3.6 wave and the climb cost stay on.
    #[test]
    fn epoch_75_gate_is_closed_at_epoch_74_and_open_from_75() {
        assert!(!rule_on(EPOCH_74_CLIMB_COST, EPOCH_75_TABLE_FIXES), "a record at 74 replays without the 75 ports");
        assert!(rule_on(EPOCH_75_TABLE_FIXES, EPOCH_75_TABLE_FIXES), "a record at 75 gets the 75 ports");
        assert!(rule_on(EPOCH_75_TABLE_FIXES, EPOCH_74_CLIMB_COST), "75 keeps the climb cost on");
        assert!(rule_on(EPOCH_75_TABLE_FIXES, EPOCH_73_V36), "75 keeps every 3.6 rule on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_75_TABLE_FIXES), "a fresh play_game() stamps the 75 ports on");
    }

    /// Epoch 76 (move fixes E1-E3): a record stamped 75 keeps every move-fix gate closed, a fresh record at 76 opens
    /// them, and 76 keeps the 75 ports, the climb cost and the 3.6 wave on.
    #[test]
    fn epoch_76_gate_is_closed_at_epoch_75_and_open_from_76() {
        assert!(!rule_on(EPOCH_75_TABLE_FIXES, EPOCH_76_MOVE_FIXES), "a record at 75 replays without the move fixes");
        assert!(rule_on(EPOCH_76_MOVE_FIXES, EPOCH_76_MOVE_FIXES), "a record at 76 gets the move fixes");
        assert!(rule_on(EPOCH_76_MOVE_FIXES, EPOCH_75_TABLE_FIXES), "76 keeps the 75 ports on");
        assert!(rule_on(EPOCH_76_MOVE_FIXES, EPOCH_74_CLIMB_COST), "76 keeps the climb cost on");
        assert!(rule_on(EPOCH_76_MOVE_FIXES, EPOCH_73_V36), "76 keeps every 3.6 rule on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_76_MOVE_FIXES), "a fresh play_game() stamps the move fixes on");
    }

    /// Epoch 77 (#183 charge cap): a record stamped 76 replays the uncapped charge trails, a fresh record caps them.
    #[test]
    fn epoch_77_gate_is_closed_at_epoch_76_and_open_from_77() {
        assert!(!rule_on(EPOCH_76_MOVE_FIXES, EPOCH_77_CHARGE_CAP), "a record at 76 replays without the charge cap");
        assert!(rule_on(EPOCH_77_CHARGE_CAP, EPOCH_77_CHARGE_CAP), "a record at 77 gets the charge cap");
        assert!(rule_on(EPOCH_77_CHARGE_CAP, EPOCH_76_MOVE_FIXES), "77 keeps the move fixes on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_77_CHARGE_CAP), "a fresh play_game() stamps the charge cap on");
    }

    /// Epoch 78 (#2827 flier cut): a record stamped 77 replays without the cut, a fresh record cuts.
    #[test]
    fn epoch_78_gate_is_closed_at_epoch_77_and_open_from_78() {
        assert!(!rule_on(EPOCH_77_CHARGE_CAP, EPOCH_78_FLIER_CUT), "a record at 77 replays without the flier cut");
        assert!(rule_on(EPOCH_78_FLIER_CUT, EPOCH_78_FLIER_CUT), "a record at 78 gets the flier cut");
        assert!(rule_on(EPOCH_78_FLIER_CUT, EPOCH_77_CHARGE_CAP), "78 keeps the charge cap on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_78_FLIER_CUT), "a fresh play_game() stamps the flier cut on");
    }

    /// Epoch 79 (FAB-A5): a record stamped 78 replays the stamp-blind EV defender, a fresh record reads the stamp.
    #[test]
    fn epoch_79_gate_is_closed_at_epoch_78_and_open_from_79() {
        assert!(!rule_on(EPOCH_78_FLIER_CUT, EPOCH_79_EV_MOVED_ROUND), "a record at 78 replays without the EV stamp");
        assert!(rule_on(EPOCH_79_EV_MOVED_ROUND, EPOCH_79_EV_MOVED_ROUND), "a record at 79 gets the EV stamp");
        assert!(rule_on(EPOCH_79_EV_MOVED_ROUND, EPOCH_78_FLIER_CUT), "79 keeps the flier cut on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_79_EV_MOVED_ROUND), "a fresh play_game() stamps the EV stamp on");
    }

    /// Epoch 80 (ai_03b): a record stamped 79 replays the old rollout menu, a fresh record restricts Cumbersome.
    #[test]
    fn epoch_80_gate_is_closed_at_epoch_79_and_open_from_80() {
        assert!(!rule_on(EPOCH_79_EV_MOVED_ROUND, EPOCH_80_ROLLOUT_CUMBERSOME), "a record at 79 replays the old menu");
        assert!(rule_on(EPOCH_80_ROLLOUT_CUMBERSOME, EPOCH_80_ROLLOUT_CUMBERSOME), "a record at 80 gets the restriction");
        assert!(rule_on(EPOCH_80_ROLLOUT_CUMBERSOME, EPOCH_79_EV_MOVED_ROUND), "80 keeps the EV stamp on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_80_ROLLOUT_CUMBERSOME), "a fresh play_game() stamps it on");
    }

    /// Epoch 81: a record stamped 80 replays the old morale-buff spend, a fresh record keeps the buff of a Shaken unit's auto-failed test.
    #[test]
    fn epoch_81_gate_is_closed_at_epoch_80_and_open_from_81() {
        assert!(!rule_on(EPOCH_80_ROLLOUT_CUMBERSOME, EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF), "a record at 80 replays the old spend");
        assert!(rule_on(EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF, EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF), "a record at 81 keeps the buff");
        assert!(rule_on(EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF, EPOCH_80_ROLLOUT_CUMBERSOME), "81 keeps the Cumbersome menu on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF), "a fresh play_game() stamps it on");
    }

    /// Epoch 82: a record stamped 81 replays the folded family roll, a fresh record rolls a bypass by name.
    #[test]
    fn epoch_82_gate_is_closed_at_epoch_81_and_open_from_82() {
        assert!(!rule_on(EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF, EPOCH_82_IGNORE_BY_NAME), "a record at 81 replays the folded roll");
        assert!(rule_on(EPOCH_82_IGNORE_BY_NAME, EPOCH_82_IGNORE_BY_NAME), "a record at 82 rolls by name");
        assert!(rule_on(EPOCH_82_IGNORE_BY_NAME, EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF), "82 keeps the Shaken buff rule on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_82_IGNORE_BY_NAME), "a fresh play_game() stamps it on");
    }

    /// Epoch 83 (S1 shadow soak): a record stamped 82 replays the host-as-target volley, a fresh record shoots the lone hero.
    #[test]
    fn epoch_83_gate_is_closed_at_epoch_82_and_open_from_83() {
        assert!(!rule_on(EPOCH_82_IGNORE_BY_NAME, EPOCH_83_LONE_HERO_TARGET), "a record at 82 replays the host target");
        assert!(rule_on(EPOCH_83_LONE_HERO_TARGET, EPOCH_83_LONE_HERO_TARGET), "a record at 83 shoots the lone hero");
        assert!(rule_on(EPOCH_83_LONE_HERO_TARGET, EPOCH_82_IGNORE_BY_NAME), "83 keeps the by-name roll on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_83_LONE_HERO_TARGET), "a fresh play_game() stamps it on");
    }

    /// Epoch 84: a record stamped 83 replays the one folded ignore roll, a fresh record rolls differently named rules in sequence.
    #[test]
    fn epoch_84_gate_is_closed_at_epoch_83_and_open_from_84() {
        assert!(!rule_on(EPOCH_83_LONE_HERO_TARGET, EPOCH_84_IGNORE_GROUPS), "a record at 83 replays the folded roll");
        assert!(rule_on(EPOCH_84_IGNORE_GROUPS, EPOCH_84_IGNORE_GROUPS), "a record at 84 rolls the groups in sequence");
        assert!(rule_on(EPOCH_84_IGNORE_GROUPS, EPOCH_82_IGNORE_BY_NAME), "84 keeps the by-name bypass on");
        assert!(rule_on(EPOCH_84_IGNORE_GROUPS, EPOCH_83_LONE_HERO_TARGET), "84 keeps the lone hero target on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_84_IGNORE_GROUPS), "a fresh play_game() stamps it on");
    }

    /// Epoch 85: a record stamped 84 replays the pooled gate that ignored a weapon's own Indirect, a fresh record opens it.
    #[test]
    fn epoch_85_gate_is_closed_at_epoch_84_and_open_from_85() {
        assert!(!rule_on(EPOCH_84_IGNORE_GROUPS, EPOCH_85_INDIRECT_GATE), "a record at 84 replays the sighted-only gate");
        assert!(rule_on(EPOCH_85_INDIRECT_GATE, EPOCH_85_INDIRECT_GATE), "a record at 85 lets an Indirect weapon open the gate");
        assert!(rule_on(EPOCH_85_INDIRECT_GATE, EPOCH_84_IGNORE_GROUPS), "85 keeps the ignore groups on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_85_INDIRECT_GATE), "a fresh play_game() stamps it on");
    }

    /// Epoch 86: a record stamped 85 replays the plain base gap, a fresh record honours the vertical reach.
    #[test]
    fn epoch_86_gate_is_closed_at_epoch_85_and_open_from_86() {
        assert!(!rule_on(EPOCH_85_INDIRECT_GATE, EPOCH_86_VOLLEY_HEIGHT_REACH), "a record at 85 replays the height-blind distance");
        assert!(rule_on(EPOCH_86_VOLLEY_HEIGHT_REACH, EPOCH_86_VOLLEY_HEIGHT_REACH), "a record at 86 honours the vertical reach");
        assert!(rule_on(EPOCH_86_VOLLEY_HEIGHT_REACH, EPOCH_85_INDIRECT_GATE), "86 keeps the Indirect gate on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_86_VOLLEY_HEIGHT_REACH), "a fresh play_game() stamps it on");
    }

    /// Epoch 87 (table side): a record stamped 86 replays the planned-route Dangerous count, a fresh record counts the walked route.
    #[test]
    fn epoch_87_gate_is_closed_at_epoch_86_and_open_from_87() {
        assert!(!rule_on(EPOCH_86_VOLLEY_HEIGHT_REACH, EPOCH_87_WALKED_DANGEROUS), "a record at 86 replays the planned-route count");
        assert!(rule_on(EPOCH_87_WALKED_DANGEROUS, EPOCH_87_WALKED_DANGEROUS), "a record at 87 counts the walked route");
        assert!(rule_on(EPOCH_87_WALKED_DANGEROUS, EPOCH_86_VOLLEY_HEIGHT_REACH), "87 keeps the volley height reach on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_87_WALKED_DANGEROUS), "a fresh play_game() stamps it on");
    }

    /// Epoch 88 (S1): a record stamped 87 replays the split group at the empty host, a fresh record shoots its lone hero.
    #[test]
    fn epoch_88_gate_is_closed_at_epoch_87_and_open_from_88() {
        assert!(!rule_on(EPOCH_87_WALKED_DANGEROUS, EPOCH_88_SPLIT_LONE_HERO), "a record at 87 replays the host group");
        assert!(rule_on(EPOCH_88_SPLIT_LONE_HERO, EPOCH_88_SPLIT_LONE_HERO), "a record at 88 shoots the lone hero");
        assert!(rule_on(EPOCH_88_SPLIT_LONE_HERO, EPOCH_87_WALKED_DANGEROUS), "88 keeps the walked-route count on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_88_SPLIT_LONE_HERO), "a fresh play_game() stamps it on");
    }

    #[test]
    fn epoch_90_gate_is_closed_at_epoch_89_and_open_from_90() {
        assert!(!rule_on(EPOCH_89_SHARED_BEARERS, EPOCH_90_JOINED_ONE_RECOVERY), "a record at 89 replays the hero's own die");
        assert!(rule_on(EPOCH_90_JOINED_ONE_RECOVERY, EPOCH_90_JOINED_ONE_RECOVERY), "a record at 90 rolls once per pair");
        assert!(rule_on(EPOCH_90_JOINED_ONE_RECOVERY, EPOCH_89_SHARED_BEARERS), "90 keeps the shared bearers on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_90_JOINED_ONE_RECOVERY), "a fresh play_game() stamps it on");
    }

    #[test]
    fn epoch_96_gate_is_closed_at_epoch_95_and_open_from_96() {
        assert!(!rule_on(EPOCH_95_PARITY_BATCH, EPOCH_96_PARITY_BATCH), "a record at 95 replays every 96 placeholder read the old way");
        assert!(rule_on(EPOCH_96_PARITY_BATCH, EPOCH_96_PARITY_BATCH), "a record at 96 plays the batch");
        assert!(rule_on(EPOCH_96_PARITY_BATCH, EPOCH_95_PARITY_BATCH), "96 keeps the 95 batch on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_96_PARITY_BATCH), "a fresh play_game() stamps it on");
    }

    #[test]
    fn epoch_95_gate_is_closed_at_epoch_94_and_open_from_95() {
        assert!(!rule_on(EPOCH_94_PARITY_BATCH, EPOCH_95_PARITY_BATCH), "a record at 94 replays every 95 placeholder read the old way");
        assert!(rule_on(EPOCH_95_PARITY_BATCH, EPOCH_95_PARITY_BATCH), "a record at 95 plays the batch");
        assert!(rule_on(EPOCH_95_PARITY_BATCH, EPOCH_94_PARITY_BATCH), "95 keeps the 94 batch on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_95_PARITY_BATCH), "a fresh play_game() stamps it on");
    }

    #[test]
    fn epoch_94_gate_is_closed_at_epoch_93_and_open_from_94() {
        assert!(!rule_on(EPOCH_93_DANGER_RULES_RIDER, EPOCH_94_PARITY_BATCH), "a record at 93 replays every placeholder read the old way");
        assert!(rule_on(EPOCH_94_PARITY_BATCH, EPOCH_94_PARITY_BATCH), "a record at 94 plays the batch");
        assert!(rule_on(EPOCH_94_PARITY_BATCH, EPOCH_93_DANGER_RULES_RIDER), "94 keeps the danger, alias and rider reads on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_94_PARITY_BATCH), "a fresh play_game() stamps it on");
    }

    #[test]
    fn epoch_93_gate_is_closed_at_epoch_92_and_open_from_93() {
        assert!(!rule_on(EPOCH_92_MELEE_CAUSES, EPOCH_93_DANGER_RULES_RIDER), "a record at 92 replays the old danger, alias and rider reads");
        assert!(rule_on(EPOCH_93_DANGER_RULES_RIDER, EPOCH_93_DANGER_RULES_RIDER), "a record at 93 plays the new ones");
        assert!(rule_on(EPOCH_93_DANGER_RULES_RIDER, EPOCH_92_MELEE_CAUSES), "93 keeps the melee causes on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_93_DANGER_RULES_RIDER), "a fresh play_game() stamps it on");
    }

    #[test]
    fn epoch_92_gate_is_closed_at_epoch_91_and_open_from_92() {
        assert!(!rule_on(EPOCH_91_JOINED_HERO_FATIGUE, EPOCH_92_MELEE_CAUSES), "a record at 91 replays the old melee causes");
        assert!(rule_on(EPOCH_92_MELEE_CAUSES, EPOCH_92_MELEE_CAUSES), "a record at 92 plays the table's melee causes");
        assert!(rule_on(EPOCH_92_MELEE_CAUSES, EPOCH_91_JOINED_HERO_FATIGUE), "92 keeps the joined hero fatigue on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_92_MELEE_CAUSES), "a fresh play_game() stamps it on");
    }

    #[test]
    fn epoch_91_gate_is_closed_at_epoch_90_and_open_from_91() {
        assert!(!rule_on(EPOCH_90_JOINED_ONE_RECOVERY, EPOCH_91_JOINED_HERO_FATIGUE), "a record at 90 tires the host only");
        assert!(rule_on(EPOCH_91_JOINED_HERO_FATIGUE, EPOCH_91_JOINED_HERO_FATIGUE), "a record at 91 tires the joined heroes too");
        assert!(rule_on(EPOCH_91_JOINED_HERO_FATIGUE, EPOCH_90_JOINED_ONE_RECOVERY), "91 keeps the one-recovery joined pair on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_91_JOINED_HERO_FATIGUE), "a fresh play_game() stamps it on");
    }

    #[test]
    fn epoch_89_gate_is_closed_at_epoch_88_and_open_from_89() {
        assert!(!rule_on(EPOCH_88_SPLIT_LONE_HERO, EPOCH_89_SHARED_BEARERS), "a record at 88 replays the by-name count");
        assert!(rule_on(EPOCH_89_SHARED_BEARERS, EPOCH_89_SHARED_BEARERS), "a record at 89 shares the sighted bearers");
        assert!(rule_on(EPOCH_89_SHARED_BEARERS, EPOCH_88_SPLIT_LONE_HERO), "89 keeps the split lone hero on");
        assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_89_SHARED_BEARERS), "a fresh play_game() stamps it on");
    }

    /// The WAVE 3 GATE's own reservation (05.09.): `EPOCH_6_TABLE_RULES` must
    /// exclude the Gen-3 recording fleet's stamping-gap window at epoch 5 —
    /// the fleet launched 05.09. 04:27Z at main `bb10c227` and is stamping
    /// `rules_epoch: 5` before any wave-3 rule exists, exactly the shape of
    /// window that poisoned Gen-2b at epoch 4 (`EPOCH_5_TABLE_RULES`'s own
    /// stamping-gap fix, PR #685/#688). Literal integers, never
    /// `CURRENT_RULES_EPOCH`, so this stays true no matter how many later
    /// waves bump the live epoch further.
    #[test]
    fn epoch_6_table_rules_excludes_the_gen3_recording_fleet_at_epoch_5() {
        assert_eq!(
            EPOCH_6_TABLE_RULES, 6,
            "wave 3's gates freeze one PAST the Gen-3 fleet's stamping epoch, not at it"
        );
        assert!(
            !rule_on(5, EPOCH_6_TABLE_RULES),
            "a record stamped rules_epoch:5 (the Gen-3 fleet's own stamping window) gets none of wave 3"
        );
        assert!(
            rule_on(6, EPOCH_6_TABLE_RULES),
            "a record stamped rules_epoch:6 (recorded after this gate) gets wave 3"
        );
    }

    /// The WAVE 4 GATE's own reservation (06.09.): `EPOCH_7_TABLE_RULES` must
    /// exclude every record stamped at the live epoch `6` — wave 3's ports are
    /// already merged and gated at `EPOCH_6_TABLE_RULES`, so `6` is the epoch
    /// fresh recorders stamp TODAY and wave 4's ports do not exist in any of
    /// them. Freezing wave 4's gates at `6` would repeat the WAVE 2
    /// STAMPING-GAP INCIDENT (`EPOCH_5_TABLE_RULES`, PR #685/#688) that wave 3
    /// already had to avoid: a corpus recorded now would silently start
    /// getting wave-4 rules the moment they land. Literal integers, never
    /// `CURRENT_RULES_EPOCH`, so this stays true no matter how many later
    /// waves bump the live epoch further.
    #[test]
    fn epoch_7_table_rules_excludes_records_stamped_at_the_live_epoch_6() {
        assert_eq!(
            EPOCH_7_TABLE_RULES, 7,
            "wave 4's gates freeze one PAST today's live stamping epoch, not at it"
        );
        assert!(
            !rule_on(6, EPOCH_7_TABLE_RULES),
            "a record stamped rules_epoch:6 (today's stamping window) gets none of wave 4"
        );
        assert!(
            rule_on(7, EPOCH_7_TABLE_RULES),
            "a record stamped rules_epoch:7 (recorded after this gate) gets wave 4"
        );
        assert!(
            rule_on(6, EPOCH_6_TABLE_RULES),
            "the same record keeps every wave-3 rule it WAS recorded with"
        );
    }

    /// REGRESSION GUARD (05.09., wave 3's gate PR; extended 06.09. by wave 4):
    /// bumping `CURRENT_RULES_EPOCH` must not silently re-date any of the
    /// constants frozen by earlier waves. Each one keeps its own historical
    /// value forever, no matter how many later waves move the live epoch on.
    #[test]
    fn earlier_waves_frozen_epochs_never_move() {
        assert_eq!(EPOCH_3_TABLE_RULES, 3, "wave 1's six families stay frozen at 3");
        assert_eq!(EPOCH_4_TABLE_RULES, 4, "Lacerate's own recording epoch stays frozen at 4");
        assert_eq!(EPOCH_5_TABLE_RULES, 5, "wave 2's remaining families stay frozen at 5");
        assert_eq!(EPOCH_6_TABLE_RULES, 6, "wave 3's family ports stay frozen at 6");
    }

    /// The WAVE 2 STAMPING-GAP INCIDENT fix itself (04.09.): `EPOCH_5_TABLE_RULES`
    /// must freeze wave 2's five family ports at `5`, NOT `4` — Gen-2b (41,997
    /// records, recorded at main `cf8831d1`) already stamped `rules_epoch: 4`
    /// in the window between `CURRENT_RULES_EPOCH` reaching `4` (PR #671) and
    /// the family ports landing, so freezing at `4` would keep it wrongly
    /// getting wave 2's rules forever. This is the RED/GREEN proof: on the
    /// unbumped code (`CURRENT_RULES_EPOCH == 4`, wave-2 call sites gated on
    /// the literal `4`), a Gen-2b-shaped header (`rules_epoch: 4`) WOULD get
    /// wave 2's rules (`rule_on(4, 4) == true`) — exactly the divergence
    /// found tonight; after this fix it must not.
    #[test]
    fn epoch_5_table_rules_excludes_the_gen2b_stamping_gap_at_epoch_4() {
        assert_eq!(
            EPOCH_5_TABLE_RULES, 5,
            "wave 2's gates freeze one PAST the poisoned epoch-4 stamp, not at it"
        );
        assert!(
            !rule_on(4, EPOCH_5_TABLE_RULES),
            "a record stamped rules_epoch:4 (Gen-2b's stamping-gap window) gets none of wave 2"
        );
        assert!(
            rule_on(5, EPOCH_5_TABLE_RULES),
            "a record stamped rules_epoch:5 (recorded after this fix) gets all of wave 2"
        );
    }

    /// EPOCH GATES BY RECORDING SHA (05.09.): `EPOCH_4_TABLE_RULES` is
    /// Lacerate's OWN frozen value — it merged (`cf8831d1`) BEFORE the
    /// Gen-2b recording fleet launched, so a record stamped `rules_epoch: 4`
    /// (Gen-2b included) gets Lacerate, unlike Utility Buff/Takedown/Surge/
    /// Ambush/Shred (all merged after the fleet launched, all frozen at
    /// `EPOCH_5_TABLE_RULES`).
    #[test]
    fn epoch_4_table_rules_is_lacerates_own_frozen_value() {
        assert_eq!(EPOCH_4_TABLE_RULES, 4, "Lacerate's gate freezes at its own recording epoch, 4");
        assert!(
            rule_on(4, EPOCH_4_TABLE_RULES),
            "a record stamped rules_epoch:4 (Gen-2b's own recording epoch) gets Lacerate"
        );
        assert!(
            !rule_on(3, EPOCH_4_TABLE_RULES),
            "a record stamped rules_epoch:3 (before Lacerate merged) does not get Lacerate"
        );
        assert!(
            rule_on(4, EPOCH_4_TABLE_RULES) && !rule_on(4, EPOCH_5_TABLE_RULES),
            "at rules_epoch:4, Lacerate is ON while the four later families and Shred are OFF"
        );
    }

    /// An absent `rules_epoch` (every corpus recorded before this field
    /// existed) defaults to 0 — "the Gen-0/Gen-1 rule set" — exactly like
    /// `eval_variant` above.
    #[test]
    fn an_absent_rules_epoch_defaults_to_0_and_parses() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{}}"#;
        let header = read_act_header(head).expect("no knobs at all still parses");
        assert_eq!(header.knobs.rules_epoch, 0);
    }

    #[test]
    fn record_epoch_uses_the_playing_build_only_when_the_record_has_no_stamp() {
        let ps = serde_json::json!({"rules_epoch": 3, "core_build": {"rules_epoch": 64}});
        assert_eq!(record_rules_epoch(&serde_json::json!({"rules_epoch": 7}), &ps), 7);
        assert_eq!(record_rules_epoch(&serde_json::json!({}), &ps), 3);
        assert_eq!(record_rules_epoch(&serde_json::json!({}), &serde_json::json!({"core_build": {"rules_epoch": 64}})), 64);
        assert_eq!(record_rules_epoch(&serde_json::json!({}), &serde_json::Value::Null), 0);
        let header = read_act_header(r#"{"kind":"header","profiles":{},"knobs":{},"prescreen":{"core_build":{"rules_epoch":64}}}"#).unwrap();
        assert_eq!(header.knobs.rules_epoch, 64);
    }

    /// A header that stamps `rules_epoch` carries it through unchanged — the
    /// reading a fresh `play_game()` recording and a replay tool that passes
    /// a record's own key both rely on.
    #[test]
    fn a_stamped_rules_epoch_parses_through() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"rules_epoch":2}}"#;
        let header = read_act_header(head).expect("a stamped rules_epoch parses");
        assert_eq!(header.knobs.rules_epoch, 2);
    }

    /// The evolved-eval seam's other RED proof — a header asking for a variant
    /// with no registered arm is refused HERE, before it can ever reach
    /// `score::score_hand_variant`'s `unreachable!` fallback.
    #[test]
    fn an_unknown_search_mode_is_refused_naming_the_key() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"search_mode":"maze"}}"#;
        let err = read_act_header(head).expect_err("search_mode maze has no arm");
        assert!(err.contains("search_mode"), "error should name the key: {err}");
    }

    #[test]
    fn a_tree_header_with_a_zero_budget_is_refused() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"search_mode":"tree","tree_budget":0}}"#;
        let err = read_act_header(head).expect_err("tree_budget 0 is no budget");
        assert!(err.contains("tree_budget"), "error should name the key: {err}");
    }

    #[test]
    fn absent_tree_knobs_parse_to_the_defaults() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{}}"#;
        let k = read_act_header(head).expect("an empty knobs block parses").knobs;
        assert_eq!((k.search_mode, k.tree_leaf, k.tree_dice), (SearchMode::OnePly, TreeLeaf::Blend, TreeDice::Ev));
        assert_eq!((k.tree_budget, k.tree_samples, k.tree_batch), (128, 4, 8));
        assert_eq!((k.tree_wall_ms, k.pool_wall_ms, k.deadline_us), (0, 0, 0));
    }

    #[test]
    fn a_negative_deadline_is_refused_naming_the_key() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"deadline_us":-1}}"#;
        let err = read_act_header(head).expect_err("a negative allowance is no allowance");
        assert!(err.contains("deadline_us"), "error should name the key: {err}");
    }

    #[test]
    fn an_unregistered_eval_variant_is_refused_at_header_parse() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"eval_variant":99}}"#;
        let err = read_act_header(head).expect_err("eval_variant 99 has no registered arm");
        assert!(err.contains("eval_variant"), "error should name the seam: {err}");
    }

    /// Wave C G-AB's ablation arm — variant 2 (variant 0 without the C7 carry
    /// term) is registered and carried through like variant 1.
    #[test]
    fn the_registered_no_carry_eval_variant_parses() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"eval_variant":2}}"#;
        let header = read_act_header(head).expect("eval_variant 2 is registered");
        assert_eq!(header.knobs.eval_variant, 2);
    }

    /// The mission-play lane's arm — variant 3 (the `round_vp` currency) is
    /// registered and carried through like variant 1.
    #[test]
    fn the_registered_vp_eval_variant_parses() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"eval_variant":3}}"#;
        let header = read_act_header(head).expect("eval_variant 3 is registered");
        assert_eq!(header.knobs.eval_variant, 3);
    }

    /// Ledger row 7's arm — variant 1 IS registered now, so the same parser
    /// that refuses 2 must accept 1 and carry it through.
    #[test]
    fn the_registered_marker_eval_variant_parses() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"eval_variant":1}}"#;
        let header = read_act_header(head).expect("eval_variant 1 is registered");
        assert_eq!(header.knobs.eval_variant, 1);
    }

    /// An absent `eval_variant` (every corpus recorded before this knob
    /// existed) defaults to 0 and parses exactly as it always did.
    #[test]
    fn an_absent_eval_variant_defaults_to_0_and_parses() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{}}"#;
        let header = read_act_header(head).expect("no knobs at all still parses");
        assert_eq!(header.knobs.eval_variant, 0);
    }

    /// W2 S0 (issue #635) — an absent `melee_reach` (every corpus recorded
    /// before this knob existed, and every corpus recorded so far: neither
    /// `TRAINER_KNOBS` nor `act_recorder.gd` stamp it yet) defaults to
    /// `MeleeReach::All`, the enum's own `#[default]` — untouched by the
    /// #635 fix, which moves only `play_game()`'s own default — so a
    /// Gen-0/Gen-1/Gen-2 replay stays byte-identical.
    #[test]
    fn an_absent_melee_reach_defaults_to_all_and_parses() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{}}"#;
        let header = read_act_header(head).expect("no knobs at all still parses");
        assert_eq!(header.knobs.melee_reach, MeleeReach::All);
    }

    /// A header that stamps `melee_reach:"table"` (what a fresh
    /// `play_game()` writes from now on) carries it through unchanged.
    #[test]
    fn a_stamped_melee_reach_table_parses_through() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"melee_reach":"table"}}"#;
        let header = read_act_header(head).expect("a stamped melee_reach parses");
        assert_eq!(header.knobs.melee_reach, MeleeReach::Table);
    }

    /// The replay-aware half of `EPOCH_19_MOVE_GRANTS_FOLD`: a header WITH
    /// `"books"` is a TABLE recording (`act_recorder.gd:266-268`), so its
    /// recorded `bands` already fold every grant — the header stamps
    /// `bands_prefolded` and the fold's live delta stays off.
    #[test]
    fn a_books_header_stamps_bands_prefolded() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"rules_epoch":19},"books":{"source":"table","sha256":"x","generated":"y"}}"#;
        let header = read_act_header(head).expect("a header with books parses");
        assert!(
            header.knobs.bands_prefolded,
            "books present ⇒ a table recording ⇒ the recorded bands are pre-folded"
        );
    }

    /// The same header WITHOUT `"books"` — the core's own header shape
    /// (`rows.rs:679`, no writer in `core/nml-core/src` emits the key) —
    /// stays `bands_prefolded: false`: bands fresh, the fold applies.
    #[test]
    fn a_core_written_header_stays_unprefolded() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"rules_epoch":19}}"#;
        let header = read_act_header(head).expect("the core's own header shape parses");
        assert!(
            !header.knobs.bands_prefolded,
            "no books ⇒ core-written ⇒ bands fresh, the live delta folds"
        );
    }

    /// Wave 6 mission stamp — a header WITH `"mission"` carries the id
    /// through to `ActHeader::mission_id()`. The table stamps id + catalog
    /// family + scoring (`act_recorder.gd`, from `NML_MISSION` and the same
    /// catalog the arena selector validated); the core only needs the id.
    #[test]
    fn a_stamped_mission_id_parses_through() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{},"mission":{"id":"domination","family":"progressive","scoring":"round_vp"}}"#;
        let header = read_act_header(head).expect("a header with mission parses");
        assert_eq!(header.mission_id(), "domination");
    }

    /// Every header recorded before this key existed — and the core's own
    /// header shape — reads as the table's fallback: "duel", the mission
    /// `core_selfplay.gd`/`solo_selfplay.gd` hard-code. Absent stays absent
    /// on the struct (`Option::None`); only the helper answers the fallback.
    #[test]
    fn an_absent_mission_reads_as_duel() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{}}"#;
        let header = read_act_header(head).expect("no mission key still parses");
        assert!(header.mission.is_none());
        assert_eq!(header.mission_id(), "duel");
    }
}
