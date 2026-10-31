//! DAT-05a tests (rules 3.6, lane data): the Bravery family's common map
//! entries. The aura expansion grants "Bravery" on top of "Bravery Aura", so
//! a carrier holds BOTH Banner-primitive rules; the morale stamp must stay at
//! +1 (best-of, never a sum).

use super::super::*;

/// One single-model carrier whose only printed rules are `rules`, resolved
/// through the REAL gf registry at `epoch`; reads the capture-time morale
/// stamp (`capture_reads_for_epoch`, the fold the sim folds in).
fn morale_carrier(faction: &str, rules: &[&str], epoch: u32) -> i64 {
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
        attached_hero_rules: vec![],
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
