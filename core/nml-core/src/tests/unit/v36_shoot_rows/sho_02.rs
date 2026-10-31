//! SHO-02 (rules 3.6, lane shoot): the "Indirect when Shooting Aura" keeps its moved penalty
//! stamp below `EPOCH_73_V36` and stamps 0 from it — the aura is a unit-wide grant, so it follows
//! the same 3.6 removal as the weapon-level Indirect facet.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

const AURA_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"wormhole_daemons_of_change",
    "special_rules":["Indirect when Shooting Aura"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

fn aura_static(epoch: u32) -> UnitStatic {
    let header = read_act_header(AURA_HEADER).expect("aura header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("carrier").expect("carrier");
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// OLD leg (the flipped existing test): at 72 the aura still stamps the -1.
#[test]
fn the_indirect_aura_stamps_the_moved_penalty_at_epoch_72() {
    let us = aura_static(EPOCH_72_PLAYTEST_RULES);
    assert!(us.shoot[0].indirect, "the granted base stamps the indirect flag");
    assert!(us.shoot[0].indirect_alias, "the wave-3 alias marker rides the flag");
    assert_eq!(us.shoot[0].indirect_moved_hit_penalty, 1, "the entry's moved_hit_penalty");
}

/// NEW leg: from 73 the aura's grant carries no moved penalty, while the Indirect facet stays.
#[test]
fn the_indirect_aura_stamps_no_moved_penalty_at_epoch_73() {
    let us = aura_static(EPOCH_73_V36);
    assert!(us.shoot[0].indirect, "the granted base still stamps the indirect flag");
    assert!(us.shoot[0].indirect_alias, "the wave-3 alias marker still rides the flag");
    assert_eq!(us.shoot[0].indirect_moved_hit_penalty, 0, "rules 3.6: no moved penalty");
}
