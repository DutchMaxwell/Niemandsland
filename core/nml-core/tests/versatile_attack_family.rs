//! The Versatile Attack family (wave 3, epoch 6) — one test per ported name,
//! through the REAL registry (each name's own (system, faction) entry, the
//! folder its book prints). The family rides the LIVE versatile mechanism:
//! the generic `stamp()` pass has carried every Versatile-Attack-primitive
//! entry (`Watchborn`, `Vinci Tech` included) since the first core stage, so
//! the buff itself is PRESENT at 6 AND at 5 (the inverted ladder — the port
//! must never re-date it). What wave 3 adds is the census's own-token
//! evidence (the named epoch-6 arm, `acts::EPOCH_6_TABLE_RULES` frozen) plus
//! the rules-must-log lines on the volley fold, and the Boost's BOTH-arms
//! form: "Vinci Tech Boost" always gets AP(+1) AND +1 to hit instead of the
//! EV-best pick. Epoch literals 6/5, never `CURRENT_RULES_EPOCH`: a wave-4
//! bump must not re-date what these assertions mean.
//!
//! Numbers are deterministic: quality 4 vs defense 4 at ap 0 makes
//! `versatile_best_mode` pick the AP arm (ev_ap 5/12 >= ev_hit 1/3), so the
//! pre-port pick reads attack target 4+ / save 5+; the both-arms form reads
//! attack 3+ / save 5+. Seed 27's first two faces are [1, 5] — one hit at
//! 4+, so the save batch always exists.

use nml_core::dice::{resolve_volley_with_tray, Shooter, Tray};
use nml_core::state::{MoveBands, Profile, Weapon};
use nml_core::unit::{Ctx, UnitStatic};
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

/// One volley at 12" (over 9"), quality 4 into defense 4, ap 0: the pick
/// arms are AP(+1) only — attack target 4+, save 5+.
fn volley(us: &UnitStatic, owner: &str) -> nml_core::dice::ShootResult {
    let att = Ctx { quality: 4, models: 1, ..Default::default() };
    let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    resolve_volley_with_tray(
        &[Shooter {
            profiles: &us.shoot,
            keep: &[0],
            attacks: &[2],
            att: &att,
            owner,
        }],
        &def,
        "target",
        12.0,
        12.0,
        true,
        true,
        true,
        true,
        &mut Tray::seeded(27),
    )
}

/// "Watchborn" (gf/watch_brothers): the buff is PRESENT at 6 AND at 5 (the
/// generic primitive pass — never re-dated); the named rules-must-log line
/// exists ONLY from 6 (the new part, gated); absent WITHOUT the rule.
#[test]
fn watchborn_buff_at_both_epochs_and_its_log_from_6() {
    let on = build_at("gf", "watch_brothers", &["Watchborn"], 6);
    let v6 = volley(&on, "watch");
    assert_eq!(v6.rolls[0].target, 4, "epoch 6: the pick keeps the hit arm shut");
    assert_eq!(v6.rolls[1].target, 5, "epoch 6: AP(+1) over 9\" (the generic buff)");
    assert!(
        v6.log.iter().any(|l| l.starts_with("Watchborn:")),
        "epoch 6: the volley names the rule (RED before the fix): {:?}",
        v6.log
    );

    let legacy = build_at("gf", "watch_brothers", &["Watchborn"], 5);
    let v5 = volley(&legacy, "watch");
    assert_eq!(v5.rolls[0].target, 4, "epoch 5: byte-exact pick");
    assert_eq!(v5.rolls[1].target, 5, "epoch 5: the generic buff still fires");
    assert!(
        v5.log.iter().all(|l| !l.starts_with("Watchborn:")),
        "epoch 5: silent — the named form does not exist in the Gen-3 recorder: {:?}",
        v5.log
    );

    let none = build_at("gf", "watch_brothers", &[], 6);
    let v0 = volley(&none, "watch");
    assert_eq!(v0.rolls[1].target, 4, "no rule, no AP");
    assert!(
        v0.log.iter().all(|l| !l.starts_with("Watchborn:")),
        "no rule, no log: {:?}",
        v0.log
    );
}

/// "Vinci Tech" (aof/duchies_of_vinci): the same ladder — buff at both
/// epochs off the generic pass, its own log line only from 6.
#[test]
fn vinci_tech_buff_at_both_epochs_and_its_log_from_6() {
    let on = build_at("aof", "duchies_of_vinci", &["Vinci Tech"], 6);
    let v6 = volley(&on, "vinci");
    assert_eq!(v6.rolls[1].target, 5, "epoch 6: AP(+1) over 9\" (the generic buff)");
    assert!(
        v6.log.iter().any(|l| l.starts_with("Vinci Tech:")),
        "epoch 6: the volley names the rule (RED before the fix): {:?}",
        v6.log
    );

    let legacy = build_at("aof", "duchies_of_vinci", &["Vinci Tech"], 5);
    let v5 = volley(&legacy, "vinci");
    assert_eq!(v5.rolls[1].target, 5, "epoch 5: the generic buff still fires");
    assert!(
        v5.log.iter().all(|l| !l.starts_with("Vinci Tech:")),
        "epoch 5: silent — the named form does not exist in the Gen-3 recorder: {:?}",
        v5.log
    );

    let none = build_at("aof", "duchies_of_vinci", &[], 6);
    assert_eq!(
        volley(&none, "vinci").rolls[1].target,
        4,
        "no rule, no AP"
    );
}

/// "Vinci Tech Boost" (aof/duchies_of_vinci), with its Vinci Tech coupling:
/// from epoch 6 the bearer gets BOTH arms (attack 3+ AND save 5+) instead of
/// the pick, and names itself on the tray's log. At 5 the pick stays
/// byte-exact. The Boost WITHOUT Vinci Tech never engages — the rule's own
/// printed condition ("If this model has Vinci Tech") — while the generic
/// primitive buff keeps its pre-existing reading.
#[test]
fn vinci_tech_boost_gets_both_arms_from_epoch_6() {
    let on = build_at(
        "aof",
        "duchies_of_vinci",
        &["Vinci Tech", "Vinci Tech Boost"],
        6,
    );
    let v6 = volley(&on, "vinci");
    assert_eq!(
        v6.rolls[0].target, 3,
        "epoch 6: the hit arm fires TOO (both, not pick) (RED before the fix)"
    );
    assert_eq!(v6.rolls[1].target, 5, "epoch 6: the AP arm fires as well");
    assert!(
        v6.log.iter().any(|l| l.starts_with("Vinci Tech Boost:")),
        "epoch 6: the volley names the boost (RED before the fix): {:?}",
        v6.log
    );

    let legacy = build_at(
        "aof",
        "duchies_of_vinci",
        &["Vinci Tech", "Vinci Tech Boost"],
        5,
    );
    let v5 = volley(&legacy, "vinci");
    assert_eq!(v5.rolls[0].target, 4, "epoch 5: byte-exact pick, no hit arm");
    assert_eq!(v5.rolls[1].target, 5, "epoch 5: the generic pick's AP arm");
    assert!(
        v5.log.iter().all(|l| !l.starts_with("Vinci Tech")),
        "epoch 5: silent — the named form does not exist in the Gen-3 recorder: {:?}",
        v5.log
    );

    // The Boost alone never engages: the printed condition needs Vinci Tech.
    // The generic primitive buff (pre-existing, ungated) still picks AP.
    let lone = build_at("aof", "duchies_of_vinci", &["Vinci Tech Boost"], 6);
    let vl = volley(&lone, "vinci");
    assert_eq!(
        vl.rolls[0].target, 4,
        "boost without Vinci Tech: no hit arm"
    );
    assert_eq!(
        vl.rolls[1].target, 5,
        "boost without Vinci Tech: the generic pick's AP arm (pre-existing)"
    );
    assert!(
        vl.log.iter().all(|l| !l.starts_with("Vinci Tech Boost:")),
        "boost without Vinci Tech: the rule does not fire, no log: {:?}",
        vl.log
    );
}
