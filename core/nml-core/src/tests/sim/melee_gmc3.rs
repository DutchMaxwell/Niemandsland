//! DS-GMC3 melee cause group ("strike-order and weapon specials"):
//! 1. Counter as a unit rule (`TU`) + Counter strike-first battle-log lines (`TU`, `TW`)
//! 2. Destructive (3.6.0 `above_half_strength`) & target-state conditional AP in melee (`CW`, `TW`)
//! 3. Piercing Hunter (`ranged_over_or_charge`: `Havocbound` / `Piercing Warrior`) on a weapon (`CW`) + `cond_ap` melee battle-log line (`CU`, `CW`)

use super::*;
use crate::acts::{CURRENT_RULES_EPOCH, PENDING_EPOCH_MELEE_GMC3};
use crate::rules::Registries;
use crate::state::{Profile, Weapon};

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

fn make_profile(
    id: &str,
    name: &str,
    faction: &str,
    models: i64,
    unit_rules: &[&str],
    weapon_rules: &[&str],
) -> Profile {
    Profile {
        cost: 100,
        unit_id: id.into(),
        name: name.into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1; models as usize],
        model_count: models,
        weapons: vec![Weapon {
            name: "Blade".into(),
            range: 0.0,
            attacks: 2,
            ap: 0,
            count: models,
            rules: weapon_rules.iter().map(|s| (*s).into()).collect(),
        }],
        special_rules: unit_rules.iter().map(|s| (*s).into()).collect(),
        caster_value: 0,
        base_radius: 0.016,
        base_shape: "round".into(),
        base_w_mm: 32.0,
        base_d_mm: 32.0,
        game_system: "gf".into(),
        faction_folder: faction.into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    }
}

fn run_melee_charge(
    att_p: Profile,
    def_p: Profile,
    epoch: u32,
    charge_from_in: f64,
    def_fatigued: bool,
    def_alive_override: Option<i64>,
) -> (ShootResult, Vec<String>, Vec<UnitStatic>) {
    let mut reg = Registries::new(&repo_root());
    let att_s = UnitStatic::build_for(&mut reg, &att_p, epoch);
    let def_s = UnitStatic::build_for(&mut reg, &def_p, epoch);
    let att_n = att_p.model_count as usize;
    let def_n = def_alive_override.unwrap_or(def_p.model_count) as usize;
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["att".into(), "def".into()],
        index: HashMap::new(),
        profile: vec![0, 1],
    });
    st.profiles = Rc::new(Profiles {
        list: vec![att_p, def_p],
        index: HashMap::new(),
    });
    st.player = vec![2, 1];
    st.alive = vec![att_n as i64, def_n as i64];
    st.fatigued = vec![false, def_fatigued];
    st.shaken = vec![false, false];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions = vec![
        (0..att_n).map(|i| [0.0, 0.0, i as f64 * 1.3 * IN2M]).collect(),
        (0..def_n).map(|i| [1.3 * IN2M, 0.0, i as f64 * 1.3 * IN2M]).collect(),
    ];
    st.wounds = vec![vec![1; att_n], vec![1; def_n]];
    Rc::make_mut(&mut st.radii).clear();
    Rc::make_mut(&mut st.radii).push(vec![0.016; att_n]);
    Rc::make_mut(&mut st.radii).push(vec![0.016; def_n]);
    let statics = vec![att_s, def_s];
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Default::default() };
    let mut seed_st = st.clone();
    let mut seed_tray = Tray::seeded(7);
    let mut seed_shot = ShootResult::default();
    tray_charge(&statics, &mut seed_st, 0, 1, seams, &mut seed_tray, &mut seed_shot, charge_from_in, Cover::Recorded(None));
    let faces: Vec<Vec<u8>> = seed_shot.rolls.iter().map(|r| r.faces.clone()).collect();
    let mut tray = Tray::supplied(faces);
    let mut shot = ShootResult::default();
    tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, charge_from_in, Cover::Recorded(None));
    let lines = tray.all_lines().into_iter().map(|l| l.text).collect();
    (shot, lines, statics)
}

// ---- Part 1: Counter as a unit rule (TU) + Counter battle-log line (TU/TW) ----

#[test]
fn counter_as_unit_rule_strikes_first_and_logs_at_pending_epoch_only() {
    let att_p = make_profile("att", "Att", "robot_legions", 5, &[], &[]);
    let def_p = make_profile("def", "Def", "robot_legions", 8, &["Counter"], &[]);

    // At PENDING_EPOCH_MELEE_GMC3: unit-level Counter folds onto melee profiles, strikes first, and logs.
    let (shot_on, lines_on, statics_on) = run_melee_charge(
        att_p.clone(), def_p.clone(), PENDING_EPOCH_MELEE_GMC3, 5.74, false, None,
    );
    assert!(statics_on[1].melee[0].counter, "unit rule Counter must fold onto melee profiles");
    assert_eq!(statics_on[1].melee[0].counter_strikes_first, Some(true));
    assert_eq!(
        (shot_on.rolls[0].kind, shot_on.rolls[0].owner.as_str()),
        ("attack", "Def"),
        "Counter TU defender must strike first"
    );
    assert!(
        lines_on.iter().any(|l| l == "Counter: Def strikes first, after the Impact dice ({cite})"),
        "Counter TU must emit battle-log line, got: {lines_on:?}"
    );

    // At CURRENT_RULES_EPOCH (90): recorded games keep pre-fix behavior byte-exact.
    let (shot_off, _lines_off, statics_off) = run_melee_charge(
        att_p.clone(), def_p, CURRENT_RULES_EPOCH, 5.74, false, None,
    );
    assert!(!statics_off[1].melee[0].counter, "epoch <= 90 stays unchanged for recorded games");
    assert_eq!(
        (shot_off.rolls[0].kind, shot_off.rolls[0].owner.as_str()),
        ("attack", "Att"),
        "epoch <= 90 keeps charger striking first"
    );

    // Exact rule name matching: an unrelated prefix name must not match.
    let aura_p = make_profile("def", "Def", "robot_legions", 8, &["Counter-Attack Aura"], &[]);
    let (_, _, statics_aura) = run_melee_charge(
        att_p, aura_p, PENDING_EPOCH_MELEE_GMC3, 5.74, false, None,
    );
    assert!(!statics_aura[1].melee[0].counter, "unexpanded aura name must not match plain Counter");
}

#[test]
fn counter_weapon_emits_battle_log_lines_for_strike_first_and_fatigued() {
    let att_p = make_profile("att", "Att", "robot_legions", 5, &[], &[]);
    let def_p = make_profile("def", "Def", "robot_legions", 8, &[], &["Counter"]);

    // Fresh defender: strikes first and emits the table's battle-log line at CURRENT_RULES_EPOCH.
    let (shot, lines, _) = run_melee_charge(
        att_p.clone(), def_p.clone(), CURRENT_RULES_EPOCH, 5.74, false, None,
    );
    assert_eq!((shot.rolls[0].kind, shot.rolls[0].owner.as_str()), ("attack", "Def"));
    assert!(
        lines.iter().any(|l| l == "Counter: Def strikes first, after the Impact dice ({cite})"),
        "Counter TW must emit strike-first battle-log line, got: {lines:?}"
    );

    // Fatigued defender: does not strike first, emits Fatigued battle-log line.
    let (shot_f, lines_f, _) = run_melee_charge(
        att_p, def_p, CURRENT_RULES_EPOCH, 5.74, true, None,
    );
    assert_eq!((shot_f.rolls[0].kind, shot_f.rolls[0].owner.as_str()), ("attack", "Att"));
    assert!(
        lines_f.iter().any(|l| l == "Counter: Def is Fatigued - no strike-first"),
        "Fatigued Counter defender must emit battle-log line, got: {lines_f:?}"
    );
    assert!(
        !lines_f.iter().any(|l| l.contains("strikes first, after")),
        "Fatigued defender must not log strike-first: {lines_f:?}"
    );
}

// ---- Part 2: Destructive (3.6.0 above_half_strength) & melee cond_ap battle-log line ----

fn first_defense_target(shot: &ShootResult, owner: &str) -> Option<i64> {
    shot.rolls
        .iter()
        .find(|r| r.kind == "defense" && r.owner == owner)
        .map(|r| r.target)
}

#[test]
fn destructive_v36_cw_and_tw_apply_above_half_strength_ap_and_log_at_pending_epoch_only() {
    // CW: Att carries 3.6.0 Destructive (gf/elven_jesters, above_half_strength -> AP+1).
    let att_cw = make_profile("att", "Att", "elven_jesters", 5, &[], &["Destructive"]);
    let def_plain = make_profile("def", "Def", "elven_jesters", 8, &[], &[]);

    let (shot_on, lines_on, _) = run_melee_charge(
        att_cw.clone(), def_plain.clone(), PENDING_EPOCH_MELEE_GMC3, 5.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_on, "Def"), Some(5), "Destructive CW above half -> AP(+1), saves on 5+");
    assert!(
        lines_on.iter().any(|l| l == "Destructive: AP(+1) against Def (target is above half strength)"),
        "Destructive CW must emit battle-log line, got: {lines_on:?}"
    );

    // At half strength (4/8 models alive): inactive on both AP and log.
    let (shot_half, lines_half, _) = run_melee_charge(
        att_cw.clone(), def_plain.clone(), PENDING_EPOCH_MELEE_GMC3, 5.74, false, Some(4),
    );
    assert_eq!(first_defense_target(&shot_half, "Def"), Some(4), "Destructive CW at half strength -> AP(0)");
    assert!(
        !lines_half.iter().any(|l| l.contains("Destructive:")),
        "Destructive CW at half strength must not log: {lines_half:?}"
    );

    // Epoch 90: recorded games keep pre-fix AP(0) byte-exact.
    let (shot_90, _, _) = run_melee_charge(
        att_cw, def_plain, CURRENT_RULES_EPOCH, 5.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_90, "Def"), Some(4), "epoch <= 90 stays AP(0) for recorded games");

    // TW: Def carries 3.6.0 Destructive, Att is 5/5 alive (above half strength) on strike-back.
    let att_plain = make_profile("att", "Att", "elven_jesters", 5, &[], &[]);
    let def_tw = make_profile("def", "Def", "elven_jesters", 8, &[], &["Destructive"]);
    let (shot_tw, lines_tw, _) = run_melee_charge(
        att_plain.clone(), def_tw.clone(), PENDING_EPOCH_MELEE_GMC3, 5.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_tw, "Att"), Some(5), "Destructive TW above half -> AP(+1), Att saves on 5+");
    assert!(
        lines_tw.iter().any(|l| l == "Destructive: AP(+1) against Att (target is above half strength)"),
        "Destructive TW must emit battle-log line, got: {lines_tw:?}"
    );

    let (shot_tw90, _, _) = run_melee_charge(
        att_plain, def_tw, CURRENT_RULES_EPOCH, 5.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_tw90, "Att"), Some(4), "epoch <= 90 TW stays AP(0)");
}

#[test]
fn havocbound_unit_rule_emits_cond_ap_battle_log_line_in_melee() {
    let att_cu = make_profile("att", "Att", "havoc_brothers", 5, &["Havocbound"], &[]);
    let def_plain = make_profile("def", "Def", "havoc_brothers", 6, &[], &[]);
    let (shot, lines, _) = run_melee_charge(
        att_cu, def_plain, CURRENT_RULES_EPOCH, 7.74, false, None,
    );
    assert_eq!(first_defense_target(&shot, "Def"), Some(5), "Havocbound CU >6\" -> AP(+1)");
    assert!(
        lines.iter().any(|l| l == "Havocbound: AP(+1) against Def"),
        "Havocbound CU must emit battle-log line in melee, got: {lines:?}"
    );
}

// ---- Part 3: Piercing Hunter (ranged_over_or_charge) on a weapon (CW) ----

#[test]
fn piercing_hunter_ranged_over_or_charge_on_weapon_applies_and_logs_at_pending_epoch_only() {
    let def_plain = make_profile("def", "Def", "havoc_brothers", 6, &[], &[]);

    // Havocbound on CW, charge > 6" at PENDING_EPOCH_MELEE_GMC3 -> AP(+1) + log line.
    let att_cw = make_profile("att", "Att", "havoc_brothers", 5, &[], &["Havocbound"]);
    let (shot_on, lines_on, _) = run_melee_charge(
        att_cw.clone(), def_plain.clone(), PENDING_EPOCH_MELEE_GMC3, 7.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_on, "Def"), Some(5), "Havocbound CW >6\" -> AP(+1), saves on 5+");
    assert!(
        lines_on.iter().any(|l| l == "Havocbound: AP(+1) against Def"),
        "Havocbound CW must emit battle-log line, got: {lines_on:?}"
    );

    // Charge <= 6": stays inert at 3.6 (>6" gate).
    let (shot_short, lines_short, _) = run_melee_charge(
        att_cw.clone(), def_plain.clone(), PENDING_EPOCH_MELEE_GMC3, 4.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_short, "Def"), Some(4), "Havocbound CW <=6\" -> AP(0)");
    assert!(!lines_short.iter().any(|l| l.contains("Havocbound:")));

    // Epoch 90: recorded games keep pre-fix AP(0) byte-exact.
    let (shot_90, _, _) = run_melee_charge(
        att_cw, def_plain.clone(), CURRENT_RULES_EPOCH, 7.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_90, "Def"), Some(4), "epoch <= 90 CW stays AP(0)");

    // Piercing Warrior on CW -> same shared ranged_over_or_charge weapon expansion.
    let att_pw = make_profile("att", "Att", "havoc_brothers", 5, &[], &["Piercing Warrior"]);
    let (shot_pw, lines_pw, _) = run_melee_charge(
        att_pw, def_plain.clone(), PENDING_EPOCH_MELEE_GMC3, 7.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_pw, "Def"), Some(5), "Piercing Warrior CW >6\" -> AP(+1)");
    assert!(
        lines_pw.iter().any(|l| l == "Piercing Warrior: AP(+1) against Def"),
        "Piercing Warrior CW must emit battle-log line, got: {lines_pw:?}"
    );

    // Dedup: Havocbound on both CU and CW must not double-count AP(+1) -> AP(+2).
    let att_both = make_profile("att", "Att", "havoc_brothers", 5, &["Havocbound"], &["Havocbound"]);
    let (shot_both, lines_both, _) = run_melee_charge(
        att_both, def_plain, PENDING_EPOCH_MELEE_GMC3, 7.74, false, None,
    );
    assert_eq!(first_defense_target(&shot_both, "Def"), Some(5), "CU+CW Havocbound must not double-stack AP");
    assert_eq!(
        lines_both.iter().filter(|l| l.as_str() == "Havocbound: AP(+1) against Def").count(),
        1,
        "CU+CW Havocbound must log once, got: {lines_both:?}"
    );
}
