//! The Piercing Hunter family (wave 3, epoch 6) — one test per ported name,
//! through the REAL registry (each name's own (system, faction) entry, the
//! folder its book prints). The family's live forms are stated BY NAME by
//! build_for's epoch-6 named arm (`acts::EPOCH_6_TABLE_RULES`, the frozen
//! gate); the generic conditional-AP pass keeps its pre-wave behaviour at
//! every earlier epoch byte-exact. Epoch literals 6/5, never
//! `CURRENT_RULES_EPOCH`: a wave-4 bump must not re-date what these
//! assertions mean. `Piercing Hunter` itself is the inverted ladder (the
//! surge2 precedent): PRESENT at 6, PRESENT at 5 (the generic pass has
//! carried its ranged_over spec since NML-1103 — the port must never re-date
//! it), absent WITHOUT the rule. The two new spellings are present ONLY from
//! 6 — the Gen-3 recording fleet stamps `rules_epoch: 5` and none of wave 3
//! existed in that recorder.

use nml_core::dice::{resolve_melee_with_tray, resolve_volley_with_tray, Shooter, Tray};
use nml_core::state::{MoveBands, Profile, Weapon};
use nml_core::unit::{CondAp, Ctx, ShootProfile, UnitStatic};
use nml_core::Registries;

/// A single-model carrier of one family name, in the faction block whose
/// mechanics entry fields the name, with one ranged and one melee weapon so
/// both stamped arrays are non-empty.
fn carrier(system: &str, faction: &str, rules: &[&str]) -> Profile {
    Profile {
        unit_id: "u".into(),
        name: "u".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![],
        model_count: 1,
        weapons: vec![
            Weapon {
                name: "Rifle".into(),
                range: 24.0,
                attacks: 2,
                count: 1,
                ap: 0,
                rules: vec![],
            },
            Weapon {
                name: "Claws".into(),
                range: 0.0,
                attacks: 1,
                count: 1,
                ap: 0,
                rules: vec![],
            },
        ],
        special_rules: rules.iter().map(|s| s.to_string()).collect(),
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: system.into(),
        faction_folder: faction.into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    }
}

fn build_at(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
    let repo = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
    let mut reg = Registries::new(&repo);
    UnitStatic::build_for(&mut reg, &carrier(system, faction, rules), epoch)
}

/// Every stamped conditional-AP spec whose condition is `cond`, across the
/// ranged and melee arrays.
fn forms_with<'a>(us: &'a UnitStatic, cond: &str) -> Vec<&'a CondAp> {
    us.shoot
        .iter()
        .chain(us.melee.iter())
        .flat_map(|sp: &ShootProfile| sp.cond_ap.iter())
        .filter(|c| c.condition == cond)
        .collect()
}

/// "Piercing Hunter" (gf/blessed_sisters): the ranged_over leg the generic
/// conditional-AP pass has stamped since NML-1103 — PRESENT at 6, PRESENT at
/// 5 (byte-exact, the port never re-dates it), absent WITHOUT the rule. The
/// unit-level spec lands on EVERY stamped profile, so one ranged weapon plus
/// one melee weapon means two specs — one per array.
#[test]
fn piercing_hunter_reads_as_ranged_over_at_every_epoch() {
    for epoch in [6, 5] {
        let us = build_at("gf", "blessed_sisters", &["Piercing Hunter"], epoch);
        let over = forms_with(&us, "ranged_over");
        assert_eq!(
            over.len(),
            2,
            "epoch {epoch}: the ranged_over spec on both stamped profiles"
        );
        assert_eq!(over[0].ap_bonus, 1, "epoch {epoch}: AP(+1)");
        assert!((over[0].over_in - 9.0).abs() < 1e-9, "epoch {epoch}: over 9 in");
    }
    let none = build_at("gf", "blessed_sisters", &[], 6);
    assert!(
        forms_with(&none, "ranged_over").is_empty(),
        "no rule, no ranged_over spec"
    );
}

/// "Havocbound" (gf/havoc_brothers): the entry's own spelling
/// (`condition: ranged_over_or_charge`) is INERT on the shared match — the
/// named epoch-6 arm states its two printed legs BY NAME instead, the charge
/// leg (on_charge, melee charging) and the ranged leg (ranged_over at the
/// entry's own over_in). Both legs exist ONLY from 6; at 5 the entry stays
/// inert exactly as the Gen-3 recorder played it.
#[test]
fn havocbound_stamps_its_two_legs_from_epoch_6() {
    let on = build_at("gf", "havoc_brothers", &["Havocbound"], 6);
    let charge = forms_with(&on, "on_charge");
    assert_eq!(
        charge.len(),
        2,
        "epoch 6: the charge leg on both profiles, stated by name (RED before the fix)"
    );
    assert_eq!(charge[0].ap_bonus, 1, "epoch 6: AP(+1)");
    let over = forms_with(&on, "ranged_over");
    assert_eq!(
        over.len(),
        2,
        "epoch 6: the ranged leg on both profiles (RED before the fix)"
    );
    assert_eq!(over[0].ap_bonus, 1, "epoch 6: AP(+1)");
    assert!((over[0].over_in - 9.0).abs() < 1e-9, "epoch 6: at the entry's own over_in");

    let off = build_at("gf", "havoc_brothers", &["Havocbound"], 5);
    assert!(
        forms_with(&off, "on_charge").is_empty(),
        "epoch 5: no charge leg — pre-port records stay inert"
    );
    assert!(
        forms_with(&off, "ranged_over").is_empty(),
        "epoch 5: no ranged leg — pre-port records stay inert"
    );

    let none = build_at("gf", "havoc_brothers", &[], 6);
    assert!(forms_with(&none, "on_charge").is_empty(), "no rule, no legs");
}

/// "Piercing Shooter" (aof/chivalrous_kingdoms): "gets AP(+1) when shooting"
/// — the any-range leg, stated as the ranged_over spelling at its degenerate
/// bound (over_in -1: any MEASURED distance fires, the unknown-distance
/// sentinel stays shut exactly like the table's own conservative reading).
/// ONLY from 6; the entry's own `condition: ranged` spelling stays inert at
/// every earlier epoch, byte-exact.
#[test]
fn piercing_shooter_stamps_the_any_range_leg_from_epoch_6() {
    let on = build_at("aof", "chivalrous_kingdoms", &["Piercing Shooter"], 6);
    let over = forms_with(&on, "ranged_over");
    assert_eq!(
        over.len(),
        2,
        "epoch 6: the any-range leg on both profiles (RED before the fix)"
    );
    assert_eq!(over[0].ap_bonus, 1, "epoch 6: AP(+1)");
    assert!((over[0].over_in - (-1.0)).abs() < 1e-9, "epoch 6: the degenerate over_in");

    let off = build_at("aof", "chivalrous_kingdoms", &["Piercing Shooter"], 5);
    assert!(
        forms_with(&off, "ranged_over").is_empty(),
        "epoch 5: no leg — pre-port records stay inert"
    );

    let none = build_at("aof", "chivalrous_kingdoms", &[], 6);
    assert!(forms_with(&none, "ranged_over").is_empty(), "no rule, no leg");
}

/// The charge leg END TO END on the tray: a Havocbound bearer's charge at
/// epoch 6 folds AP(+1) into the save target and names the rule on the
/// tray's rules-must-log; at epoch 5 the same charge is inert (the entry's
/// own spelling answers 0 on the shared match, exactly what the Gen-3
/// recorder played).
#[test]
fn a_havocbound_charge_folds_its_ap_and_logs_from_epoch_6() {
    let us = build_at("gf", "havoc_brothers", &["Havocbound"], 6);
    let att = Ctx { quality: 4, models: 1, ..Default::default() };
    let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    let volley = |profiles: &[ShootProfile], charging: bool| {
        resolve_melee_with_tray(
            &[Shooter {
                profiles,
                keep: &[0],
                attacks: &[1],
                att: &att,
                owner: "havoc",
            }],
            &def,
            "target",
            charging,
            true,
            true,
            &mut Tray::seeded(9),
        )
    };
    let with = volley(&us.melee, true);
    assert!(
        with.log.iter().any(|l| l.contains("Havocbound")),
        "epoch 6: the charge leg folds AP(+1) and logs the rule: {:?}",
        with.log
    );

    let legacy = build_at("gf", "havoc_brothers", &["Havocbound"], 5);
    let without = volley(&legacy.melee, true);
    assert!(
        without.log.iter().all(|l| !l.contains("Havocbound")),
        "epoch 5: the inert entry logs nothing: {:?}",
        without.log
    );
}

/// The ranged legs END TO END on the tray: Havocbound past 9" and Piercing
/// Shooter at ANY measured distance (5" — under the Hunter gate) both name
/// their rule at 6 and stay silent at 5.
#[test]
fn the_ranged_legs_fold_their_ap_and_log_from_epoch_6() {
    let att = Ctx { quality: 4, models: 1, ..Default::default() };
    let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    let volley = |profiles: &[ShootProfile], dist: f64| {
        resolve_volley_with_tray(
            &[Shooter {
                profiles,
                keep: &[0],
                attacks: &[2],
                att: &att,
                owner: "shooter",
            }],
            &def,
            "target",
            dist,
            dist,
            true,
            true,
            true,
            true,
            &mut Tray::seeded(9),
        )
    };

    let havoc = build_at("gf", "havoc_brothers", &["Havocbound"], 6);
    let at_12 = volley(&havoc.shoot, 12.0);
    assert!(
        at_12.log.iter().any(|l| l.contains("Havocbound")),
        "epoch 6: the ranged leg folds AP(+1) past 9 in and logs: {:?}",
        at_12.log
    );
    let legacy = build_at("gf", "havoc_brothers", &["Havocbound"], 5);
    assert!(
        volley(&legacy.shoot, 12.0).log.iter().all(|l| !l.contains("Havocbound")),
        "epoch 5: inert at 12 in"
    );

    let shooter = build_at("aof", "chivalrous_kingdoms", &["Piercing Shooter"], 6);
    let at_5 = volley(&shooter.shoot, 5.0);
    assert!(
        at_5.log.iter().any(|l| l.contains("Piercing Shooter")),
        "epoch 6: the any-range leg fires at 5 in — under the Hunter gate — and logs: {:?}",
        at_5.log
    );
    let legacy = build_at("aof", "chivalrous_kingdoms", &["Piercing Shooter"], 5);
    assert!(
        volley(&legacy.shoot, 5.0).log.iter().all(|l| !l.contains("Piercing Shooter")),
        "epoch 5: inert at 5 in"
    );
}
