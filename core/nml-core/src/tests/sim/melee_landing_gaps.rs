//! DS-GMC1 — step-API landings and rule lines for non-strike melee damage phases:
//! Impact, Heavy Impact, Brace, Retaliate, Deathstrike, Self-Destruct (death & survival),
//! Hazardous self-wounds, and Regenerative Strength pre-strike landing.

use super::*;
use crate::acts::{CURRENT_RULES_EPOCH, EPOCH_91_JOINED_HERO_FATIGUE, EPOCH_92_MELEE_CAUSES};
use crate::state::Kit;

fn two_unit_melee(att_models: usize, def_models: usize, tough: i64) -> (Vec<UnitStatic>, State) {
    let mut att = UnitStatic {
        ctx: Ctx { quality: 4, defense: 4, tough, models: att_models as i64, ..Default::default() },
        name: "Att".into(),
        model_count: att_models as i64,
        wounds_max: vec![tough; att_models],
        melee: vec![ShootProfile {
            name: "Blade".into(), attacks: (att_models * 2) as i64, count: att_models as i64, range: 0,
            ..Default::default()
        }],
        ..Default::default()
    };
    let def = UnitStatic {
        ctx: Ctx { quality: 4, defense: 4, tough, models: def_models as i64, ..Default::default() },
        name: "Def".into(),
        model_count: def_models as i64,
        wounds_max: vec![tough; def_models],
        melee: vec![ShootProfile {
            name: "Blade".into(), attacks: (def_models * 2) as i64, count: def_models as i64, range: 0,
            ..Default::default()
        }],
        ..Default::default()
    };
    att.ctx.rules_epoch = CURRENT_RULES_EPOCH;
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u","game_system":"gf"}"#).unwrap();
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.round = 1;
    st.player = vec![2, 1];
    st.alive = vec![att_models as i64, def_models as i64];
    st.shaken = vec![false, false];
    st.fatigued = vec![false, false];
    st.in_cover = vec![false, false];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions = vec![
        (0..att_models).map(|i| [5.0 * IN2M, 0.0, i as f64 * 1.3 * IN2M]).collect(),
        (0..def_models).map(|i| [6.2 * IN2M, 0.0, i as f64 * 1.4 * IN2M]).collect(),
    ];
    st.wounds = vec![vec![tough; att_models], vec![tough; def_models]];
    st.radii = Rc::new(vec![vec![0.6 * IN2M; att_models], vec![0.6 * IN2M; def_models]]);
    st.growth_markers = vec![0, 0];
    st.growth_strike_round = vec![-1, -1];
    st.limited_used = Rc::new(vec![vec![], vec![]]);
    st.feats_used = Rc::new(vec![vec![], vec![]]);
    (vec![att, def], st)
}

fn exact_seams() -> Seams {
    seams_at(CURRENT_RULES_EPOCH)
}

fn seams_at(rules_epoch: u32) -> Seams {
    Seams { rules_epoch, tray_exact: true, ..Seams::default() }
}

#[test]
fn impact_and_heavy_impact_emit_landings_and_lines() {
    let (mut statics, mut st) = two_unit_melee(3, 5, 1);
    statics[0].ctx.impact = 2;
    statics[0].ctx.heavy_impact = 1;
    statics[1].ctx.brace_models = 5;
    statics[1].ctx.brace_impact_per_model = Some(1);
    statics[1].brace_rule = "Brace".into();
    // Brace(1) strips 1 die from Heavy Impact(1)*3=3 -> 2 heavy dice, plain stays 6 dice.
    // Plain: 6 dice -> 4 hits, Def saves 4 dice -> 2 fail -> 2 dead.
    // Heavy: 2 dice -> 2 hits, Def saves 2 dice (AP 1 -> 5+) -> 2 fail -> 2 dead.
    let mut tray = Tray::supplied(vec![
        vec![2, 3, 4, 5, 1, 1], // Impact hits (4)
        vec![4, 5, 1, 2],       // Impact saves (2 fail)
        vec![6, 5],             // Heavy Impact hits (2)
        vec![4, 3],             // Heavy Impact saves at 5+ (2 fail)
    ]);
    let mut shot = ShootResult::default();
    let caused = impact_phase(&statics, &mut st, 0, 1, &mut tray, &mut shot, CURRENT_RULES_EPOCH, 7.0, true);
    assert_eq!(caused, 4);
    assert_eq!(st.alive[1], 1);
    let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
    assert!(lines.iter().any(|l| l == "Brace: Def takes 1 Impact dice off Att"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Att: Impact(2) rolls 6 dice → 4 hits"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Att: Heavy Impact(1) rolls 2 dice → 2 hits"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Def takes 2 wounds (3/5)"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Def takes 2 wounds (1/5)"), "lines: {lines:?}");
    let dead: usize = tray.all_landings().iter()
        .filter(|l| l.unit == 1)
        .flat_map(|l| l.models.iter())
        .filter(|m| m.dead)
        .count();
    assert_eq!(dead, 4, "all 4 Impact/Heavy Impact kills must land on tray: {:?}", tray.all_landings());
}

#[test]
fn retaliate_emits_landing_and_line() {
    let (mut statics, mut st) = two_unit_melee(3, 3, 1);
    statics[1].ctx.retaliate_hits_per_wound = 1;
    // Att 6 attacks -> 2 hits; Def 2 saves -> 2 wounds; Retaliate 2 hits -> Att 2 saves -> 2 dead.
    let mut tray = Tray::supplied(vec![
        vec![6, 5, 1, 1, 1, 1], // Att hits (2)
        vec![1, 2],             // Def saves (2 fail)
        vec![1, 2],             // Att Retaliate saves (2 fail)
    ]);
    let mut shot = ShootResult::default();
    strike_phase(&statics, &mut st, 0, 1, true, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
    assert_eq!(st.alive[0], 1);
    let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
    assert!(lines.iter().any(|l| l == "Retaliate: Def lashes back — 2 hits (Def: 2 wounds × 1)"), "lines: {lines:?}");
    let att_dead: usize = tray.all_landings().iter()
        .filter(|l| l.unit == 0)
        .flat_map(|l| l.models.iter())
        .filter(|m| m.dead)
        .count();
    assert_eq!(att_dead, 2, "Retaliate kills on Att must land: {:?}", tray.all_landings());
}

#[test]
fn deathstrike_and_self_destruct_death_half_emit_landings_and_lines() {
    for (is_sd, want_rule) in [(false, "Deathstrike"), (true, "Self-Destruct")] {
        let (mut statics, mut st) = two_unit_melee(3, 3, 1);
        statics[1].ctx.death_hits_per_kill = 2;
        if is_sd {
            statics[1].ctx.self_destruct_rating = 2;
        }
        // Att 6 attacks -> 1 hit -> Def fails 1 save (1 killed) -> 2 lash-out hits -> Att fails 2 saves.
        let mut tray = Tray::supplied(vec![
            vec![5, 1, 1, 1, 1, 1],
            vec![1],
            vec![1, 2],
        ]);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, true, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
        assert_eq!(st.alive[0], 1);
        let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        let want = format!("{want_rule}: Def's dying models lash out — Att takes 2 hits");
        assert!(lines.iter().any(|l| l == &want), "missing {want:?} in {lines:?}");
        let att_dead: usize = tray.all_landings().iter()
            .filter(|l| l.unit == 0)
            .flat_map(|l| l.models.iter())
            .filter(|m| m.dead)
            .count();
        assert_eq!(att_dead, 2, "{want_rule} kills on Att must land: {:?}", tray.all_landings());
    }
}

#[test]
fn self_destruct_survival_half_emits_both_landings_and_line() {
    let (mut statics, mut st) = two_unit_melee(2, 4, 1);
    statics[0].ctx.self_destruct_rating = 2;
    // Give Def kits so chain_casualty_order removes outer model first (slot 3 or 0 by centroid distance).
    st.kits = vec![
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 1 }; 2]),
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 1 }; 4]),
    ];
    // Att (2 alive) detonates -> 4 hits on Def -> 1 fails save.
    let mut tray = Tray::supplied(vec![vec![6, 5, 4, 1]]);
    let mut shot = ShootResult::default();
    self_destruct_post_melee(&statics, &mut st, 0, 1, exact_seams(), &mut tray, &mut shot);
    assert_eq!(st.alive[0], 0);
    assert_eq!(st.alive[1], 3);
    let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
    assert!(lines.iter().any(|l| l == "Self-Destruct: Att detonates after the melee — destroyed; Def takes 4 hits"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Att destroyed"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Def loses a model (3/4)"), "lines: {lines:?}");
    let att_dead: usize = tray.all_landings().iter().filter(|l| l.unit == 0).flat_map(|l| l.models.iter()).filter(|m| m.dead).count();
    let def_dead: usize = tray.all_landings().iter().filter(|l| l.unit == 1).flat_map(|l| l.models.iter()).filter(|m| m.dead).count();
    assert_eq!((att_dead, def_dead), (2, 1), "both Att detonation and Def kills must land: {:?}", tray.all_landings());
}

#[test]
fn hazardous_pinned_bearer_kills_and_wounds_emit_landings_and_lines() {
    // Tough(1) with pinned kits: two natural 1s kill capture slots 0 and 1.
    let (mut statics, mut st) = two_unit_melee(3, 3, 1);
    statics[0].melee[0].hazardous = true;
    statics[0].melee[0].ap = 4;
    st.kits = vec![
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 1 }; 3]),
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 1 }; 3]),
    ];
    st.kit_names = vec![Rc::new(vec!["Blade".into()]), Rc::new(vec!["Blade".into()])];
    let mut tray = Tray::supplied(vec![
        vec![1, 1, 5, 2, 2, 2], // Att: 2 natural 1s, 1 hit
        vec![6],                // Def saves
    ]);
    let mut shot = ShootResult::default();
    strike_phase(&statics, &mut st, 0, 1, true, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
    assert_eq!(st.alive[0], 1);
    let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
    assert!(lines.iter().any(|l| l == "Hazardous: Att model 1 takes 1 wound (Blade)"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Hazardous: Att model 2 takes 1 wound (Blade)"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Att loses a model (2/3)"), "lines: {lines:?}");
    assert!(lines.iter().any(|l| l == "Att loses a model (1/3)"), "lines: {lines:?}");
    let slots: Vec<(usize, bool)> = tray.all_landings().iter()
        .filter(|l| l.unit == 0)
        .flat_map(|l| l.models.iter().map(|m| (m.slot, m.dead)))
        .collect();
    assert_eq!(slots, vec![(0, true), (1, true)], "landings: {:?}", tray.all_landings());

    // Tough(3) with pinned kits: one natural 1 wounds slot 0 without killing it.
    let (mut statics_t3, mut st_t3) = two_unit_melee(2, 2, 3);
    statics_t3[0].melee[0].hazardous = true;
    statics_t3[0].melee[0].ap = 4;
    st_t3.kits = vec![
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 3 }; 2]),
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 3 }; 2]),
    ];
    st_t3.kit_names = vec![Rc::new(vec!["Blade".into()]), Rc::new(vec!["Blade".into()])];
    let mut tray_t3 = Tray::supplied(vec![vec![1, 2, 2, 2]]);
    let mut shot_t3 = ShootResult::default();
    strike_phase(&statics_t3, &mut st_t3, 0, 1, true, 7.0, exact_seams(), &mut tray_t3, &mut shot_t3, StrikeSet::All, Cover::Recorded(None));
    assert_eq!(st_t3.wounds[0], vec![2, 3]);
    let landed: Vec<(usize, i64, bool)> = tray_t3.all_landings().iter()
        .filter(|l| l.unit == 0)
        .flat_map(|l| l.models.iter().map(|m| (m.slot, m.wounds_left, m.dead)))
        .collect();
    assert_eq!(landed, vec![(0, 2, false)], "non-lethal Tough wound must land: {:?}", tray_t3.all_landings());
}

#[test]
fn hazardous_without_kits_emits_unit_landing_and_line() {
    let (mut statics, mut st) = two_unit_melee(3, 3, 1);
    statics[0].melee[0].hazardous = true;
    statics[0].melee[0].ap = 4;
    let mut tray = Tray::supplied(vec![vec![1, 2, 2, 2, 2, 2]]);
    let mut shot = ShootResult::default();
    strike_phase(&statics, &mut st, 0, 1, true, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
    assert_eq!(st.alive[0], 2);
    let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
    assert!(lines.iter().any(|l| l == "Hazardous: Att has no bearer on record — the unit takes 1 wound (Blade)"), "lines: {lines:?}");
    let att_dead: usize = tray.all_landings().iter().filter(|l| l.unit == 0).flat_map(|l| l.models.iter()).filter(|m| m.dead).count();
    assert_eq!(att_dead, 1, "unit-level Hazardous kill must land: {:?}", tray.all_landings());
}

#[test]
fn regenerative_strength_lands_before_strikes_and_emits_lines() {
    let (mut statics, mut st) = two_unit_melee(3, 5, 1);
    statics[0].growth = vec![GrowthRule { name: "Regenerative Strength".into(), ..Default::default() }];
    statics[0].ctx.growth_wounds_not_attacks = true;
    st.growth_markers[0] = 2;
    // 2 token dice -> 2 wounds (landed BEFORE strikes: Def 5 -> 3);
    // 6 Blade attacks -> 2 hits; Def 2 saves -> 2 wounds (Def 3 -> 1).
    let mut tray = Tray::supplied(vec![
        vec![6, 5],             // Regenerative Strength token dice (2 wounds)
        vec![5, 5, 1, 1, 1, 1], // Att Blade hits (2)
        vec![1, 1],             // Def saves (2 fail)
    ]);
    let mut shot = ShootResult::default();
    let (caused, _, _, _) = strike_phase(&statics, &mut st, 0, 1, true, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
    assert_eq!(caused, 4);
    assert_eq!(st.alive[1], 1);
    let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
    let i_rs = lines.iter().position(|l| l == "Regenerative Strength: Att rolls 2 dice, 2 wounds")
        .unwrap_or_else(|| panic!("missing RS line in {lines:?}"));
    let i_pre = lines.iter().position(|l| l == "Def takes 2 wounds (3/5)")
        .unwrap_or_else(|| panic!("missing pre-strike Def wound line in {lines:?}"));
    let i_hit = lines.iter().position(|l| l == "Att strikes with Blade at Def — 2 hits")
        .unwrap_or_else(|| panic!("missing Blade strike line in {lines:?}"));
    let i_post = lines.iter().position(|l| l == "Def takes 2 wounds (1/5)")
        .unwrap_or_else(|| panic!("missing post-strike Def wound line in {lines:?}"));
    assert!(i_rs < i_pre && i_pre < i_hit && i_hit < i_post, "wrong order in {lines:?}");
    let def_landings: Vec<usize> = tray.all_landings().iter()
        .filter(|l| l.unit == 1)
        .map(|l| l.models.iter().filter(|m| m.dead).count())
        .collect();
    assert_eq!(def_landings, vec![2, 2], "token wounds must land separately before strike wounds: {:?}", tray.all_landings());

    // Fatigued skip also says its line on the tray.
    let (mut statics_f, mut st_f) = two_unit_melee(3, 5, 1);
    statics_f[0].growth = vec![GrowthRule { name: "Regenerative Strength".into(), ..Default::default() }];
    statics_f[0].ctx.growth_wounds_not_attacks = true;
    st_f.growth_markers[0] = 2;
    st_f.fatigued[0] = true;
    let mut tray_f = Tray::supplied(vec![vec![1, 1, 1, 1, 1, 1]]);
    let mut shot_f = ShootResult::default();
    strike_phase(&statics_f, &mut st_f, 0, 1, true, 7.0, exact_seams(), &mut tray_f, &mut shot_f, StrikeSet::All, Cover::Recorded(None));
    let lines_f: Vec<String> = tray_f.all_lines().into_iter().map(|l| l.text).collect();
    assert!(lines_f.iter().any(|l| l == "Regenerative Strength: Att is Fatigued - no token dice"), "lines_f: {lines_f:?}");
}

// DS-GMC1 (`EPOCH_92_MELEE_CAUSES`): two table-parity details move SEEDED outcomes, so they are gated by the rules epoch
// on EVERY path (seeded and step), not by the tray kind. Below 92 both trays land the old way; from 92 both land the
// table's way.

/// One Regenerative Strength strike phase on a seeded tray: (wounds the Def lost in all, wounds the token dice landed,
/// the Retaliate lash-back hit count, the Def's and the Att's wounds after - the lash-back lands on the Att).
fn regen_retaliate_seeded(seed: i64, epoch: u32) -> (i64, i64, i64, Vec<i64>, Vec<i64>) {
    let (mut statics, mut st) = two_unit_melee(3, 6, 3);
    statics[0].growth = vec![GrowthRule { name: "Regenerative Strength".into(), ..Default::default() }];
    statics[0].ctx.growth_wounds_not_attacks = true;
    statics[1].ctx.retaliate_hits_per_wound = 1;
    st.growth_markers[0] = 6;
    let mut tray = Tray::seeded(seed);
    let mut shot = ShootResult::default();
    strike_phase(&statics, &mut st, 0, 1, true, 7.0, seams_at(epoch), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
    let lost = 18 - st.wounds[1].iter().sum::<i64>();
    let token: i64 = shot.log.iter().find_map(|l| {
        let rest = l.strip_prefix("Regenerative Strength: Att rolls 6 dice, ")?;
        rest.split(' ').next()?.parse().ok()
    }).unwrap_or(0);
    let hits: i64 = shot.log.iter().find_map(|l| {
        let rest = l.strip_prefix("Retaliate: Def lashes back — ")?;
        rest.split(' ').next()?.parse().ok()
    }).unwrap_or(0);
    (lost, token, hits, st.wounds[1].clone(), st.wounds[0].clone())
}

#[test]
fn a_seeded_tray_keeps_the_token_wounds_in_the_retaliate_pool_below_92() {
    let mut checked = 0;
    for seed in 1..=24 {
        let (lost, _, hits, _, _) = regen_retaliate_seeded(seed, EPOCH_91_JOINED_HERO_FATIGUE);
        assert_eq!(hits, lost, "seed {seed}: at 91 the lash-back counts every wound taken, token wounds included");
        checked += i64::from(lost > 0);
    }
    assert!(checked >= 20, "the fixture must wound in most seeds, got {checked}");
}

#[test]
fn a_seeded_tray_lands_the_token_wounds_before_the_strikes_from_92() {
    let (mut checked, mut moved) = (0, 0);
    for seed in 1..=24 {
        let (lost, token, hits, def_wounds, att_wounds) = regen_retaliate_seeded(seed, EPOCH_92_MELEE_CAUSES);
        assert_eq!(hits, lost - token, "seed {seed}: from 92 the lash-back pool leaves the token wounds out");
        checked += i64::from(token > 0);
        let (_, _, _, old_def, old_att) = regen_retaliate_seeded(seed, EPOCH_91_JOINED_HERO_FATIGUE);
        moved += i64::from((old_def, old_att) != (def_wounds, att_wounds));
    }
    assert!(checked >= 20, "the fixture must roll token wounds in most seeds, got {checked}");
    assert!(moved >= 1, "the epoch must move a seeded outcome (the smaller lash-back wounds the Att less), moved {moved}");
}

#[test]
fn a_supplied_tray_below_92_keeps_the_token_wounds_in_the_pool_too() {
    // The old gate was the tray kind: a supplied (step) tray took the new landing at ANY epoch. The epoch is the gate now.
    let run = |epoch: u32| {
        let (mut statics, mut st) = two_unit_melee(3, 5, 1);
        statics[0].growth = vec![GrowthRule { name: "Regenerative Strength".into(), ..Default::default() }];
        statics[0].ctx.growth_wounds_not_attacks = true;
        st.growth_markers[0] = 2;
        let mut tray = Tray::supplied(vec![vec![6, 5], vec![5, 5, 1, 1, 1, 1], vec![1, 1], vec![1, 1, 1, 1, 1, 1]]);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, true, 7.0, seams_at(epoch), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
        tray.all_lines().into_iter().map(|l| l.text).collect::<Vec<String>>()
    };
    let at_92 = run(EPOCH_92_MELEE_CAUSES);
    assert!(at_92.iter().any(|l| l == "Def takes 2 wounds (3/5)"), "at 92 the token wounds land before the strikes: {at_92:?}");
    let at_91 = run(EPOCH_91_JOINED_HERO_FATIGUE);
    assert!(!at_91.iter().any(|l| l == "Def takes 2 wounds (3/5)"), "at 91 a supplied tray keeps the pooled landing: {at_91:?}");
}

/// The Self-Destruct survival half on a seeded tray: (wounds lost, the Def's wounds after - a dead model leaves the list),
/// for the fixture where its LAST model is the wounded Tough one (1 of 3 left) and the two Att models detonate for 6 hits.
fn self_destruct_seeded(seed: i64, epoch: u32) -> (i64, Vec<i64>) {
    let (mut statics, mut st) = two_unit_melee(2, 4, 3);
    statics[0].ctx.self_destruct_rating = 3;
    st.kits = vec![
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 3 }; 2]),
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 3 }; 4]),
    ];
    st.wounds[1] = vec![3, 3, 3, 1]; // the wounded Tough model sits last: the table's order takes it first
    let mut tray = Tray::seeded(seed);
    let mut shot = ShootResult::default();
    self_destruct_post_melee(&statics, &mut st, 0, 1, seams_at(epoch), &mut tray, &mut shot);
    (10 - st.wounds[1].iter().sum::<i64>(), st.wounds[1].clone())
}

#[test]
fn a_seeded_tray_lands_the_self_destruct_hits_slot_zero_first_below_92() {
    let mut checked = 0;
    for seed in 1..=40 {
        let (lost, wounds) = self_destruct_seeded(seed, EPOCH_91_JOINED_HERO_FATIGUE);
        if (1..=2).contains(&lost) {
            assert_eq!(wounds, vec![3 - lost, 3, 3, 1], "seed {seed}: at 91 slot 0 takes the hits first on a seeded tray");
            checked += 1;
        }
    }
    assert!(checked >= 5, "the fixture must land 1-2 wounds in several seeds, got {checked}");
}

#[test]
fn a_seeded_tray_lands_the_self_destruct_hits_on_the_wounded_model_first_from_92() {
    let mut checked = 0;
    for seed in 1..=40 {
        let (lost, wounds) = self_destruct_seeded(seed, EPOCH_92_MELEE_CAUSES);
        // The wounded model (1 wound left) dies first and leaves the list; a second wound goes to slot 0.
        match lost {
            1 => assert_eq!(wounds, vec![3, 3, 3], "seed {seed}: from 92 the wounded Tough model takes the first wound"),
            2 => assert_eq!(wounds, vec![2, 3, 3], "seed {seed}: from 92 the wounded model dies, then slot 0"),
            _ => continue,
        }
        checked += 1;
    }
    assert!(checked >= 5, "the fixture must land 1-2 wounds in several seeds, got {checked}");
}

#[test]
fn a_supplied_tray_below_92_lands_the_self_destruct_hits_slot_zero_first_too() {
    // Same epoch gate on the step path: 91 keeps the old order on a supplied tray, 92 takes the wounded model first.
    let run = |epoch: u32| {
        let (mut statics, mut st) = two_unit_melee(2, 4, 3);
        statics[0].ctx.self_destruct_rating = 3;
        st.kits = vec![
            Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 3 }; 2]),
            Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 3 }; 4]),
        ];
        st.wounds[1] = vec![3, 3, 3, 1];
        let mut tray = Tray::supplied(vec![vec![6, 5, 5, 5, 5, 1]]); // 6 hits: one fails its save
        let mut shot = ShootResult::default();
        self_destruct_post_melee(&statics, &mut st, 0, 1, seams_at(epoch), &mut tray, &mut shot);
        st.wounds[1].clone()
    };
    assert_eq!(run(EPOCH_92_MELEE_CAUSES), vec![3, 3, 3], "from 92 the wounded model takes the wound and dies");
    assert_eq!(run(EPOCH_91_JOINED_HERO_FATIGUE), vec![2, 3, 3, 1], "at 91 a supplied tray keeps slot 0 first");
}
