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
pub const CURRENT_RULES_EPOCH: u32 = 45;

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
/// the net learned spells as coin flips. From 45 the cast sub-phase builds
/// the boost pool (`sim::caster_boost_pool`), plans the spend
/// (`sim::plan_caster_boost`), folds the boost into `spell::
/// cast_success_chance`'s second argument and pays it in the same order the
/// threshold rides. Below 45 the pool is empty, the plan is zeros and every
/// recorded game replays byte-exact. `45` is one past every existing stamp
/// (44 = `EPOCH_44_SURGE_MARK`, #958; 43 = #964's Battleborn leg; 41 =
/// #963's self-destruct leg; 42 never used), and the value
/// `CURRENT_RULES_EPOCH` is bumped to in the same change. Every call site
/// reads THIS constant, not the literal `45` or `CURRENT_RULES_EPOCH`.
pub const EPOCH_45_CASTER_BOOST: u32 = 45;

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
            bands_prefolded: false,
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
    Ok(ActHeader { profiles: Rc::new(profiles), terrain, knobs: Knobs { bands_prefolded, ..header.knobs } })
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
        });
    }
    Ok(ActCorpus { profiles, terrain, knobs, acts })
}

#[cfg(test)]
mod tests {
    use super::{
        read_act_header, rule_on, MeleeReach, CURRENT_RULES_EPOCH, EPOCH_3_TABLE_RULES,
        EPOCH_4_TABLE_RULES, EPOCH_5_TABLE_RULES, EPOCH_6_TABLE_RULES, EPOCH_7_TABLE_RULES,
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

    /// Wave 4 (epoch 6 -> 7): bumping the live epoch must NOT shift the six
    /// families frozen at epoch 3. A record stamped `rules_epoch: 3` keeps
    /// all six ON (`EPOCH_3_TABLE_RULES`) while getting none of wave 4's
    /// rules yet (`EPOCH_7_TABLE_RULES`) — and a fresh header stamps the
    /// new, bumped epoch.
    #[test]
    fn epoch_7_bump_keeps_the_six_epoch_3_families_frozen() {
        assert_eq!(CURRENT_RULES_EPOCH, 45, "epoch 45's gate (EPOCH_45_CASTER_BOOST) bumps the live epoch to 45, one past #958's Surge-Mark leg 44 (43 = #964's Battleborn leg, 41 = #963's selfdestruct leg; 42 never used)");
        assert_eq!(EPOCH_3_TABLE_RULES, 3, "the six epoch-3 families stay frozen at 3, forever");
        assert!(
            rule_on(3, EPOCH_3_TABLE_RULES),
            "a record at epoch 3 still replays with the six families ON"
        );
        assert!(
            !rule_on(3, EPOCH_7_TABLE_RULES),
            "a record at epoch 3 gets none of wave 4's rules"
        );
        let head = r#"{"kind":"header","profiles":{},"knobs":{"rules_epoch":45}}"#;
        let header = read_act_header(head).expect("a fresh-epoch header parses");
        assert_eq!(
            header.knobs.rules_epoch, CURRENT_RULES_EPOCH,
            "a fresh play_game() now stamps the bumped epoch, 45"
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
}
