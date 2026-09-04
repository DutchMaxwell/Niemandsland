//! The live rule-GRANT family (rung D auras + rung E buffs/marks): every
//! granted base rule must reach the dice path through `mods::granted`, folded
//! by `sim::ctx_live` exactly where the static has-rule test already stamps
//! its flag — the same seam `a_furious_grant_reaches_this_rounds_melee_and_
//! is_spent_by_it` (sim.rs) pins for the spell grants. One test per grant
//! KIND: the melee attacker grant (Furious), the shooting-scoped aura grant
//! (Rending), the defender-side morale grant (No Retreat), and the rung E
//! Mark — a record on the BEARER with `attackers: true`, folded into the
//! ATTACKER's ctx by the bridge (`sim::ctx_live_vs`, main.gd:16676-16685).

use std::collections::HashMap;
use std::rc::Rc;

use nml_core::dice::{resolve_melee_with_tray, resolve_morale_with_tray, resolve_volley_with_tray, Shooter, Tray};
use nml_core::mods::LiveMod;
use nml_core::sim::{ctx_live, ctx_live_vs, ctx_of};
use nml_core::state::{Bands, Mods, MoveBands, Profile, Profiles, Roster};
use nml_core::unit::{Ctx, ShootProfile, UnitStatic};
use nml_core::IN2M;

/// Two plain single-model units: the striker (0) and its target (1), one
/// profile slot, no rules of their own — every flag under test must come from
/// the LiveMod alone.
fn two_units() -> (nml_core::State, Vec<UnitStatic>) {
    let profile = Profile {
        unit_id: "u".into(),
        name: "u".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![],
        model_count: 1,
        weapons: vec![],
        special_rules: vec![],
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: String::new(),
        faction_folder: String::new(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    };
    let st = nml_core::State {
        roster: Rc::new(Roster {
            keys: vec!["a".into(), "b".into()],
            index: HashMap::new(),
            profile: vec![0, 0],
        }),
        profiles: Rc::new(Profiles { list: vec![profile], index: HashMap::new() }),
        round: 0,
        rounds_total: 1,
        scoring: Rc::from(""),
        objectives: vec![],
        markers_meta: vec![],
        destroy_seq: vec![],
        vp: None,
        vp_flavour: None,
        vp_memo: None,
        cast_events: vec![],
        player: vec![0, 1],
        alive: vec![1, 1],
        activated: vec![false; 2],
        shaken: vec![false; 2],
        fatigued: vec![false; 2],
        in_cover: vec![false; 2],
        aircraft: vec![false; 2],
        dormant: vec![false; 2],
        dormant_models: vec![0; 2],
        dormant_wounds: vec![Vec::new(); 2],
        casts: vec![0; 2],
        morale_bonus: vec![0; 2],
        ambush_arrived_round: vec![-1; 2],
        earliest_arrival_round: vec![-1; 2],
        wound_frac: vec![1.0; 2],
        positions: vec![vec![[0.0, 0.0, 0.0]], vec![[12.0 * IN2M, 0.0, 0.0]]],
        wounds: vec![vec![1]; 2],
        radii: vec![vec![IN2M]; 2],
        mods: vec![Mods::default(); 2],
        mods_base: (0..2).map(|_| Rc::new(Mods::default())).collect(),
        attached: Rc::new(vec![vec![], vec![]]),
        attached_to: Rc::new(vec![None, None]),
        los: vec![None, None],
        los_pairs: None,
        bands: vec![Bands::default(); 2],
        shroud: vec![None; 2],
        charge_no_difficult: vec![false; 2],
        charge_probe_r: vec![0.0; 2],
        buffs: vec![Vec::new(), Vec::new()],
        vs_mark_round: vec![-1; 2],
        hit_and_run_round: vec![-1; 2],
        growth_markers: vec![0; 2],
        growth_round: vec![-1; 2],
        second_wind_used: vec![false; 2],
        second_wind_round: -1,
        second_wind_uses: 0,
        limited_used: vec![Vec::new(); 2],
    };
    (st, vec![UnitStatic::default(), UnitStatic::default()])
}

/// A single-model gf carrier with `rules` and no weapons of its own.
fn carrier(rules: &[&str]) -> Profile {
    Profile {
        unit_id: "u".into(), name: "u".into(), quality: 4, defense: 4, tough: 1,
        wounds_max: vec![], model_count: 1, weapons: vec![],
        special_rules: rules.iter().map(|s| s.to_string()).collect(),
        caster_value: 0, base_radius: 0.0, base_shape: String::new(),
        base_w_mm: 0.0, base_d_mm: 0.0, game_system: "gf".into(),
        faction_folder: "elven_jesters".into(),
        item_grants: vec![], attached_hero_rules: vec![], move_bands: MoveBands::default(),
    }
}

/// The wave-2 STAMP gate (`acts::rule_on`, `EPOCH_5_TABLE_RULES`): a "Utility
/// Buff" name this wave ports reaches `UnitStatic.utility_buffs` only from
/// epoch 5 — the real registry entry (gf elven_jesters fields "Slayer Mark")
/// proves the walk. Frozen at 5, NOT the naive 4: Gen-2b (41,997 records,
/// recorded at main `cf8831d1`) already stamped `rules_epoch: 4` before this
/// wave's rule code existed (`acts::EPOCH_5_TABLE_RULES`'s stamping-gap
/// note), so `rules_epoch: 4` must stay blind too, not just `3`.
#[test]
fn the_wave2_utility_buff_names_stamp_only_from_epoch_5() {
    let repo = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
    let mut reg = nml_core::Registries::new(&repo);
    let on = UnitStatic::build_for(&mut reg, &carrier(&["Slayer Mark"]), 5);
    let off = UnitStatic::build_for(&mut reg, &carrier(&["Slayer Mark"]), 4);
    assert_eq!(on.utility_buffs.len(), 1, "epoch 5: the wave-2 name stamps");
    assert!(
        off.utility_buffs.is_empty(),
        "the gate keeps rules_epoch 4 (Gen-2b's stamping-gap window) blind too, RED before the fix"
    );
    assert_eq!(&*on.utility_buffs[0].grants_rule, "Slayer", "the entry's grants_rule");
}

fn grant(rule: &str, scope: &str, once: bool) -> LiveMod {
    LiveMod {
        hit_mod: 0,
        casting_mod: 0,
        morale_mod: 0,
        grants_rule: rule.into(),
        scope: scope.into(),
        attackers: false,
        once,
    }
}

/// The Mark family's landing shape: `beneficiary == "attackers"` — the record
/// sits on the BEARER and belongs to whoever attacks it (main.gd:3652).
fn mark(rule: &str) -> LiveMod {
    LiveMod { attackers: true, once: true, ..grant(rule, "", true) }
}

fn live_ctx(st: &nml_core::State, statics: &[UnitStatic], i: usize, melee: bool) -> Ctx {
    ctx_live(ctx_of(&statics[st.roster.profile[i]], st, i), statics, st, i, melee, 4)
}

/// The brief's own example, on the real tray: a unit WITHOUT Furious plus a
/// `grants_rule: "Furious"` LiveMod (scope "melee") charges — the melee roll
/// gains the Furious extra attacks (one per unmodified 6, charge only); the
/// same state without the mod does not.
#[test]
fn a_live_furious_grant_gains_the_melee_extra_attacks() {
    let (st, statics) = two_units();
    let plain = live_ctx(&st, &statics, 0, true);
    assert!(!plain.furious, "the bare profile carries no Furious");

    let profile = [ShootProfile { range: 0, attacks: 6, ..Default::default() }];
    let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    let without = resolve_melee_with_tray(
        &[Shooter { profiles: &profile, keep: &[0], attacks: &[6], att: &plain, owner: "att" }],
        &def, "def", true, false, true, &mut Tray::seeded(7),
    );

    let mut buffed_state = st;
    buffed_state.buffs[0].push(grant("Furious", "melee", true));
    let buffed = live_ctx(&buffed_state, &statics, 0, true);
    assert!(buffed.furious, "the grant reaches THIS round's melee context");
    let with = resolve_melee_with_tray(
        &[Shooter { profiles: &profile, keep: &[0], attacks: &[6], att: &buffed, owner: "att" }],
        &def, "def", true, false, true, &mut Tray::seeded(7),
    );
    assert!(
        with.wounds > without.wounds,
        "the Furious grant adds the extra-6 attacks on this seed: {} -> {}",
        without.wounds, with.wounds
    );
}

/// The Rung D aura kind ("Rending when Shooting Aura"): a scope-"shooting"
/// passive grant of Rending must feed the tray's on-6 AP batch — the sixes
/// save one step worse — where the bare profile has no rending at all.
#[test]
fn a_live_rending_grant_shoots_with_the_on6_ap_bonus() {
    let (st, statics) = two_units();
    let plain = live_ctx(&st, &statics, 0, false);
    assert!(!plain.rending_grant, "the bare profile carries no Rending");

    let profile = [ShootProfile { range: 24, attacks: 6, ..Default::default() }];
    let def = Ctx { defense: 3, models: 1, tough: 1, ..Default::default() };
    let without = resolve_volley_with_tray(
        &[Shooter { profiles: &profile, keep: &[0], attacks: &[6], att: &plain, owner: "att" }],
        &def, "def", 12.0, 12.0, false, true, true, &mut Tray::seeded(12),
    );

    let mut buffed_state = st;
    buffed_state.buffs[0].push(grant("Rending", "shooting", false));
    let buffed = live_ctx(&buffed_state, &statics, 0, false);
    assert!(buffed.rending_grant, "the aura grant reaches the shooting context");
    let with = resolve_volley_with_tray(
        &[Shooter { profiles: &profile, keep: &[0], attacks: &[6], att: &buffed, owner: "att" }],
        &def, "def", 12.0, 12.0, false, true, true, &mut Tray::seeded(12),
    );
    assert!(
        with.wounds > without.wounds,
        "the granted sixes cut one step deeper on this seed: {} -> {}",
        without.wounds, with.wounds
    );
}

/// The morale kind ("No Retreat Buff"): a friendly-granted No Retreat must pay
/// a FAILED melee morale test in self-wounds and stand (Passed) where the bare
/// profile routes with no wounds at all.
#[test]
fn a_live_no_retreat_grant_pays_a_failed_test_in_self_wounds() {
    let (st, mut statics) = two_units();
    statics[0].ctx.quality = 5; // the morale target under test
    let plain = live_ctx(&st, &statics, 0, true);
    assert!(!plain.no_retreat, "the bare profile carries no No Retreat");
    let without = resolve_morale_with_tray(&plain, "u", true, true, false, 2, &mut Tray::seeded(3));
    assert_eq!(without.0, nml_core::dice::Morale::Routed, "quality 5 below half routes on this seed (face 1)");
    assert_eq!(without.1.wounds, 0, "no No Retreat, no self-wounds");

    let mut buffed_state = st;
    buffed_state.buffs[0].push(grant("No Retreat", "", true));
    let buffed = live_ctx(&buffed_state, &statics, 0, true);
    assert!(
        nml_core::mods::granted(&buffed_state, 0, "No Retreat"),
        "the grant is visible to the ledger read the morale seam folds"
    );
    let (result, out) =
        resolve_morale_with_tray(&buffed, "u", true, true, false, 2, &mut Tray::seeded(3));
    assert_eq!(result, nml_core::dice::Morale::Passed, "No Retreat stands instead");
    assert!(out.wounds > 0, "and pays for it in self-wounds on this seed");
}

/// The rung E Mark kind ("Rending Mark"): the record lands on the BEARER
/// (unit 1) with `attackers: true` — the attacker's volley gains Rending
/// through the bridge fold (`ctx_live_vs`), the same state without the mark
/// rolls plain, and the bearer itself gains NOTHING: `granted` skips its own
/// attackers-records (main.gd:3652) and its own ctx stays grant-blind.
#[test]
fn a_mark_on_the_bearer_hands_its_attacker_the_rending_grant() {
    let (st, statics) = two_units();
    let plain = live_ctx(&st, &statics, 0, false);
    assert!(!plain.rending_grant, "no mark, no grant");

    let profile = [ShootProfile { range: 24, attacks: 6, ..Default::default() }];
    let def = Ctx { defense: 3, models: 1, tough: 1, ..Default::default() };
    let without = resolve_volley_with_tray(
        &[Shooter { profiles: &profile, keep: &[0], attacks: &[6], att: &plain, owner: "att" }],
        &def, "def", 12.0, 12.0, false, true, true, &mut Tray::seeded(12),
    );

    let mut marked_state = st;
    marked_state.buffs[1].push(mark("Rending"));
    assert!(
        nml_core::mods::granted_vs(&marked_state, 1, "Rending"),
        "the attackers-side read answers for whoever attacks the bearer"
    );
    assert!(
        !nml_core::mods::granted(&marked_state, 1, "Rending"),
        "the bearer itself does NOT gain the rule (main.gd:3652)"
    );
    assert!(
        !live_ctx(&marked_state, &statics, 1, false).rending_grant,
        "the bearer attacking anyone else stays grant-blind"
    );
    let marked = ctx_live_vs(
        ctx_of(&statics[marked_state.roster.profile[0]], &marked_state, 0),
        &statics, &marked_state, 0, 1, false, 4,
    );
    assert!(marked.rending_grant, "the mark reaches the ATTACKER's shooting context");
    let with = resolve_volley_with_tray(
        &[Shooter { profiles: &profile, keep: &[0], attacks: &[6], att: &marked, owner: "att" }],
        &def, "def", 12.0, 12.0, false, true, true, &mut Tray::seeded(12),
    );
    assert!(
        with.wounds > without.wounds,
        "the granted sixes cut one step deeper on this seed: {} -> {}",
        without.wounds, with.wounds
    );
}
