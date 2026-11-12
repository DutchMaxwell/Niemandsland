//! DAT-05a follow-up (`EPOCH_75_TABLE_FIXES`, lane data): the Bravery Aura share on a morale test
//! that no shot or melee caused, and the AI estimate's Banner-family read. The table keeps the
//! aura's share on any cause (main.gd's cause branch strips only the rest of the Banner share) and
//! prices the whole family share in `AiEv.ctx_for`; records stamped 74 or below keep the old reads.

use super::super::*;
use crate::acts::{EPOCH_74_CLIMB_COST, EPOCH_75_TABLE_FIXES};
use crate::dice::{ShootResult, Tray};
use crate::io::Seams;
use crate::sim::tray_morale_for;
use crate::unit::ShootProfile;

/// One Quality 4+ single-model unit of the real gf registry carrying `rules`, built at `epoch`.
fn carrier(rules: &[&str], epoch: u32) -> (UnitStatic, i64) {
    let p = Profile {
        cost: 0,
        unit_id: "carrier".into(),
        name: "Carrier".into(),
        quality: 4,
        defense: 3,
        tough: 1,
        wounds_max: vec![1],
        model_count: 1,
        weapons: vec![],
        special_rules: rules.iter().map(|r| r.to_string()).collect(),
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: "blessed_sisters".into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    };
    let mut reg = Registries::new(&repo_root());
    let stamp = capture_reads_for_epoch(&mut reg, &p, epoch).morale_bonus;
    (UnitStatic::build_for(&mut reg, &p, epoch), stamp)
}

/// The morale-test target the carrier (unit 2 of the four-unit line) rolls against `cause`.
fn target(rules: &[&str], cause: Option<&str>, epoch: u32) -> (i64, Vec<String>) {
    let (us, stamp) = carrier(rules, epoch);
    let mut st = crate::sim::tests::four_unit_line();
    st.morale_bonus[2] = stamp;
    let mut shot = ShootResult::default();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    tray_morale_for(&mut st, &vec![us; 4], 2, false, true, cause, seams, &mut Tray::seeded(1), &mut shot, None, None);
    let die = shot.rolls.iter().find(|r| r.count == 1).expect("the morale die is drawn");
    (die.target, shot.log)
}

/// RED: from 75 a spell-forced test keeps the Bravery Aura's +1 (Q4 passes on 3+); a Banner next to
/// it still drops its own +1, and a plain Banner still gets nothing.
#[test]
fn a_bravery_aura_keeps_its_plus_one_on_a_spell_caused_test_from_epoch_75() {
    let e = EPOCH_75_TABLE_FIXES;
    let (t, log) = target(&["Bravery Aura"], Some("Mind Control"), e);
    assert_eq!(t, 3, "Bravery Aura has no shooting/melee qualifier: {log:#?}");
    assert!(log.iter().any(|l| l.contains("Bravery Aura") && l.contains("Mind Control")), "rules-must-log: {log:#?}");
    assert_eq!(target(&["Banner", "Bravery Aura"], Some("Mind Control"), e).0, 3, "only the Banner +1 drops");
    assert_eq!(target(&["Banner"], Some("Mind Control"), e).0, 4, "CONTROL: a plain Banner drops");
    assert_eq!(target(&["Banner", "Bravery Aura"], None, e).0, 2, "CONTROL: a shooting test keeps both");
}

/// A record stamped 74 replays the old read: the whole Banner share drops on a spell-forced test.
#[test]
fn epoch_74_drops_the_bravery_aura_share_on_a_spell_caused_test() {
    assert_eq!(target(&["Bravery Aura"], Some("Mind Control"), EPOCH_74_CLIMB_COST).0, 4);
}

/// RED: from 75 the AI estimate's `morale_bonus` is the Banner-family share (`AiEv.ctx_for`), not
/// Banner-only; 74 keeps the Banner-only number.
#[test]
fn the_estimate_reads_the_banner_family_share_from_epoch_75() {
    let ctx = |rules: &[&str], e: u32| carrier(rules, e).0.ctx.morale_bonus;
    assert_eq!(ctx(&["Banner", "Bravery Aura"], EPOCH_75_TABLE_FIXES), 2);
    assert_eq!(ctx(&["Bravery Aura"], EPOCH_75_TABLE_FIXES), 1);
    assert_eq!(ctx(&["Valiant"], EPOCH_75_TABLE_FIXES), 1);
    assert_eq!(ctx(&["Banner", "Bravery Aura"], EPOCH_74_CLIMB_COST), 1);
    assert_eq!(ctx(&["Bravery Aura"], EPOCH_74_CLIMB_COST), 0);
}

/// RED: from 75 `charge_score` drops the Valiant part inside the 6" charge band (`AiEv.charge_score`);
/// an unknown (negative) distance and 74 keep the whole bonus.
#[test]
fn the_charge_score_drops_the_valiant_share_inside_the_band_from_epoch_75() {
    let blade = vec![ShootProfile { name: "Blade".into(), attacks: 4, count: 1, range: 0, ..Default::default() }];
    let score = |e: u32, gap: f64| {
        let us = Ctx { quality: 4, defense: 4, tough: 3, models: 2, morale_bonus: 1, valiant_bonus: 1, rules_epoch: e, ..Default::default() };
        let them = Ctx { quality: 4, defense: 4, tough: 3, models: 2, rules_epoch: e, ..Default::default() };
        crate::menu::charge_score(&blade, &[4], &us, &blade, &[4], &them, gap, e, false)
    };
    let e = EPOCH_75_TABLE_FIXES;
    assert!(score(e, 3.0) < score(e, 10.0), "inside the band the Valiant +1 is gone: {} vs {}", score(e, 3.0), score(e, 10.0));
    assert_eq!(score(e, -1.0), score(e, 10.0), "unknown distance keeps it");
    assert_eq!(score(EPOCH_74_CLIMB_COST, 3.0), score(EPOCH_74_CLIMB_COST, 10.0), "74 is unchanged");
}
