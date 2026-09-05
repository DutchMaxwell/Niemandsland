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

use crate::io::{roster_of, state_of, Ordered, PlainState};
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
    /// gate on `rule_on(rules_epoch, CURRENT_RULES_EPOCH)` and bump the
    /// constant in the same change.
    #[serde(default)]
    pub rules_epoch: u32,
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
pub const CURRENT_RULES_EPOCH: u32 = 6;

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
            imagined_round_end: true,
            depth_discount: 0.5,
            seat_mode: 0,
            playout_margin: 0.02,
            playout_rich: true,
            seam_cast: false,
            seam_spacing: false,
            seam_path: false,
            hero_last: false,
            cast_fold: false,
            charge_gate: true,
            menu_targets: false,
            hero_attach: false,
            charge_landing: false,
            sighting: Sighting::Unit,
            movement: false,
            los_model: false,
            menu_los: false,
            menu_wide: false,
            moved_shoot: false,
            move_rigid: false,
            dangerous: true,
            engage_fold: false,
            dangerous_end_morale: false,
            // NML-1134: the CORPUS reading — a header with no `knobs` block at
            // all predates the stamp just as surely as one with an unstamped
            // block does. A caller that plays a FRESH game stamps
            // `rows::RULE_VOCAB_VERSION` itself.
            rule_vocab_version: crate::rows::LEGACY_VOCAB_VERSION,
            eval_variant: 0,
            melee_reach: MeleeReach::All,
            consolidate: false,
            cond_ap_dice: false,
            versatile_reach: false,
            rules_epoch: 0,
        }
    }
}

#[derive(Deserialize)]
struct Header {
    profiles: Ordered<Profile>,
    #[serde(default)]
    terrain: Option<PlainTerrain>,
    #[serde(default)]
    knobs: Knobs,
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

/// The header line's three products — the profile table, the board and the
/// search knobs. Factored out of `read_acts` so a caller that never sees the
/// file (the Python seam, NML-1073 M3-1) builds them from the SAME code path
/// instead of a second reading of the header.
#[derive(Debug)]
pub struct ActHeader {
    pub profiles: Rc<Profiles>,
    pub terrain: Terrain,
    pub knobs: Knobs,
}

/// Parses one act-corpus header line (`{"kind":"header", ...}`).
pub fn read_act_header(text: &str) -> Result<ActHeader, String> {
    let header: Header = serde_json::from_str(text).map_err(|e| format!("act header: {e}"))?;
    // The evolved-eval seam: variant 0 (today's frozen eval) and variant 1 (the
    // referee-shaped marker term, ledger row 7) have registered arms in
    // `score::score_hand_variant`. A header asking for anything else is
    // rejected HERE, loudly, rather than silently playing variant 0 or
    // panicking deep inside a rollout.
    if !matches!(header.knobs.eval_variant, 0 | 1) {
        return Err(format!(
            "eval_variant {}: no registered arm (only 0 and 1 exist)",
            header.knobs.eval_variant
        ));
    }
    Ok(header_of(header))
}

fn header_of(header: Header) -> ActHeader {
    let terrain = match &header.terrain {
        Some(t) => Terrain::build(t),
        None => Terrain::absent(),
    };
    let mut profiles = Profiles::default();
    for (k, p) in header.profiles.0 {
        profiles.index.insert(k, profiles.list.len());
        profiles.list.push(p);
    }
    ActHeader { profiles: Rc::new(profiles), terrain, knobs: header.knobs }
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
    let ActHeader { profiles, terrain, knobs } =
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
        let eff = profile_cache.effective(&roster, &pa.state.dyn_profiles());
        acts.push(Act {
            round: pa.round,
            player: pa.player,
            state: state_of(pa.state, &eff, roster),
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
        });
    }
    Ok(ActCorpus { profiles, terrain, knobs, acts })
}

#[cfg(test)]
mod tests {
    use super::{
        read_act_header, rule_on, MeleeReach, CURRENT_RULES_EPOCH, EPOCH_3_TABLE_RULES,
        EPOCH_4_TABLE_RULES, EPOCH_5_TABLE_RULES, EPOCH_6_TABLE_RULES,
    };

    /// The CLASS FIX's one gate (external review 03.09. item 3 / F9):
    /// `rule_on` is a plain `>=`, tested at its own boundary — `since_epoch`
    /// itself turns a rule on, one below it does not, and above it stays on.
    #[test]
    fn rule_on_is_true_from_its_since_epoch_onward() {
        assert!(!rule_on(0, 1), "epoch 0 is before since_epoch 1: off");
        assert!(rule_on(1, 1), "epoch reaches its own since_epoch: on");
        assert!(rule_on(2, 1), "epoch past its since_epoch: on");
        assert!(!rule_on(0, CURRENT_RULES_EPOCH), "epoch 0 is before every future port");
    }

    /// Wave 3 (epoch 5 -> 6): bumping the live epoch must NOT shift the six
    /// families frozen at epoch 3. A record stamped `rules_epoch: 3` keeps
    /// all six ON (`EPOCH_3_TABLE_RULES`) while getting none of wave 3's
    /// rules yet (`EPOCH_6_TABLE_RULES`) — and a fresh header stamps the
    /// new, bumped epoch.
    #[test]
    fn epoch_6_bump_keeps_the_six_epoch_3_families_frozen() {
        assert_eq!(CURRENT_RULES_EPOCH, 6, "wave 3's gate bumps the live epoch to 6");
        assert_eq!(EPOCH_3_TABLE_RULES, 3, "the six epoch-3 families stay frozen at 3, forever");
        assert!(
            rule_on(3, EPOCH_3_TABLE_RULES),
            "a record at epoch 3 still replays with the six families ON"
        );
        assert!(
            !rule_on(3, EPOCH_6_TABLE_RULES),
            "a record at epoch 3 gets none of wave 3's rules"
        );
        let head = r#"{"kind":"header","profiles":{},"knobs":{"rules_epoch":6}}"#;
        let header = read_act_header(head).expect("a fresh-epoch header parses");
        assert_eq!(
            header.knobs.rules_epoch, CURRENT_RULES_EPOCH,
            "a fresh play_game() now stamps the bumped epoch, 6"
        );
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

    /// REGRESSION GUARD (05.09., wave 3's gate PR): bumping `CURRENT_RULES_EPOCH`
    /// to 6 must not silently re-date any of the three constants frozen by
    /// earlier waves. Each one keeps its own historical value forever, no
    /// matter how many later waves move the live epoch on.
    #[test]
    fn earlier_waves_frozen_epochs_never_move() {
        assert_eq!(EPOCH_3_TABLE_RULES, 3, "wave 1's six families stay frozen at 3");
        assert_eq!(EPOCH_4_TABLE_RULES, 4, "Lacerate's own recording epoch stays frozen at 4");
        assert_eq!(EPOCH_5_TABLE_RULES, 5, "wave 2's remaining families stay frozen at 5");
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
    fn an_unregistered_eval_variant_is_refused_at_header_parse() {
        let head = r#"{"kind":"header","profiles":{},"knobs":{"eval_variant":2}}"#;
        let err = read_act_header(head).expect_err("eval_variant 2 has no registered arm");
        assert!(err.contains("eval_variant"), "error should name the seam: {err}");
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
}
