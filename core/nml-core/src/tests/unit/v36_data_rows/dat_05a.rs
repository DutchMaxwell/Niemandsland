//! DAT-05a tests (rules 3.6, lane data): the Bravery family's common map
//! entries. The aura expansion grants "Bravery" on top of "Bravery Aura", so
//! a carrier holds BOTH Banner-primitive rules; the morale stamp must stay at
//! +1 (best-of, never a sum).

use super::super::*;
use crate::acts::{EPOCH_74_CLIMB_COST, EPOCH_75_TABLE_FIXES};

/// One single-model carrier whose only printed rules are `rules`, resolved
/// through the REAL gf registry at `epoch`; reads the capture-time morale
/// stamp (`capture_reads_for_epoch`, the fold the sim folds in).
fn morale_carrier(faction: &str, rules: &[&str], epoch: u32) -> i64 {
    morale_host(faction, rules, &[], epoch)
}

/// `morale_carrier` with joined heroes: each entry of `heroes` is one hero's printed rules.
fn morale_host(faction: &str, rules: &[&str], heroes: &[&[&str]], epoch: u32) -> i64 {
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
        faction_folder: faction.into(),
        item_grants: vec![],
        attached_hero_rules: heroes.iter().map(|h| h.iter().map(|r| r.to_string()).collect()).collect(),
        move_bands: MoveBands::default(),
    };
    let mut reg = Registries::new(&repo_root());
    capture_reads_for_epoch(&mut reg, &p, epoch).morale_bonus
}

#[test]
fn a_bravery_aura_and_its_granted_base_stamp_plus_one_not_two() {
    let e = CURRENT_RULES_EPOCH;
    assert_eq!(
        morale_carrier("blessed_sisters", &["Bravery Aura", "Bravery"], e),
        1,
        "aura + granted base are two Banner entries of one family: best-of, not 2"
    );
    assert_eq!(
        morale_carrier("blessed_sisters", &["Bravery Aura"], e),
        1,
        "the aura alone stamps +1"
    );
    assert_eq!(
        morale_carrier("blessed_sisters", &["Bravery"], e),
        1,
        "the granted base alone stamps +1"
    );
    assert_eq!(
        morale_carrier("blessed_sisters", &["Fearless"], e),
        0,
        "control: no Bravery entry, no morale bonus"
    );
}

/// Maintainer ruling (`EPOCH_75_TABLE_FIXES`): Banner and Bravery Aura are two sources and ADD UP; the
/// Bravery family (the aura and the bare base the expansion stamps) is one source of its own.
#[test]
fn banner_and_bravery_aura_add_up_to_plus_two_from_epoch_75() {
    let e = EPOCH_75_TABLE_FIXES;
    assert_eq!(morale_carrier("blessed_sisters", &["Banner", "Bravery Aura"], e), 2, "Banner + Bravery Aura");
    assert_eq!(morale_carrier("blessed_sisters", &["Banner", "Bravery Aura", "Bravery"], e), 2, "aura + base stay one source");
    // The family is read across the unit: a Banner host with a Bravery Aura hero is +2 too.
    assert_eq!(morale_host("blessed_sisters", &["Banner", "Bravery"], &[&["Hero", "Bravery Aura", "Bravery"]], e), 2);
    // CONTROL: another Banner-family name keeps the best-of read with Banner.
    assert_eq!(morale_carrier("blessed_sisters", &["Banner", "Valiant"], e), 1, "Banner + Valiant stays +1");
}

/// A record stamped 74 replays the old best-of: Banner + Bravery Aura is +1.
#[test]
fn epoch_74_keeps_the_best_of_read() {
    let e = EPOCH_74_CLIMB_COST;
    assert_eq!(morale_carrier("blessed_sisters", &["Banner", "Bravery Aura"], e), 1);
    assert_eq!(morale_host("blessed_sisters", &["Banner"], &[&["Hero", "Bravery Aura"]], e), 1);
}
