use super::*;

// DAT-17b — the Regeneration Buff DATA FLIP. From EPOCH_73_V36 the four map
// entries are Utility Buffs whose grant hands ONE picked friendly a single
// Regeneration, so the carrier no longer rolls it itself. Below the gate the
// old-data replay leg keeps folding the 5 onto the carrier.

/// The gf common map's entry read through the REAL registry (aof's
/// ossified_undead is one of the four carriers).
#[test]
fn a_regeneration_buff_grants_a_friendly_regeneration_at_73() {
    let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("regen_buff").expect("regen_buff");
    let us = UnitStatic::build_for(&mut reg, p, crate::acts::EPOCH_73_V36);

    let buff = us
        .utility_buffs
        .iter()
        .find(|b| b.name == "Regeneration Buff")
        .expect("at 73 the entry reads as a Utility Buff grant");
    assert_eq!(buff.grants_rule, "Regeneration", "the entry's grant");
    assert_eq!(buff.target, "friendly", "one picked friendly");
    assert_eq!(buff.max_targets, 1);
    assert_eq!(buff.range_in, 12.0);
    assert!(buff.once, "a one-time grant");
    assert_eq!(
        (us.ctx.regen_target, us.ctx.regen_target_spell),
        (0, 0),
        "the carrier no longer rolls the granted Regeneration itself"
    );
}

/// Below the gate the same real data keeps the 3.5 reading: no utility buff,
/// the carrier folds its own 5+ (the old-data replay leg).
#[test]
fn a_regeneration_buff_stays_the_carriers_own_roll_at_72() {
    let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("regen_buff").expect("regen_buff");
    let us = UnitStatic::build_for(&mut reg, p, crate::acts::EPOCH_72_PLAYTEST_RULES);

    assert!(
        us.utility_buffs.iter().all(|b| b.name != "Regeneration Buff"),
        "below 73 the entry is not a utility-buff grant"
    );
    assert_eq!(
        (us.ctx.regen_target, us.ctx.regen_target_spell),
        (5, 5),
        "the carrier keeps its own 5+ fold below the gate"
    );
}
