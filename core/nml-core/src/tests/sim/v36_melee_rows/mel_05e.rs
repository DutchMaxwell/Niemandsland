//! MEL-05e tests (rules 3.6, lane melee): the AI's Impact estimate no longer prices a Counter cut at
//! `EPOCH_73_V36` — Counter takes no Impact dice away, so a Counter defender prices like a plain one.
//! Epoch 72 keeps the cut.
use super::super::*;
use crate::state::Weapon;
use crate::Registries;

fn profile(name: &str, models: i64, specials: Vec<&str>, weapon_rules: Vec<&str>) -> Profile {
    Profile {
        cost: 0,
        unit_id: name.into(),
        name: name.into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1; models as usize],
        model_count: models,
        weapons: vec![Weapon {
            name: "Blade".into(),
            range: 0.0,
            attacks: 1,
            count: models,
            ap: 0,
            rules: weapon_rules.into_iter().map(str::to_string).collect(),
        }],
        special_rules: specials.into_iter().map(str::to_string).collect(),
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: "robot_legions".into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    }
}

/// A 2-model Impact(3) charger and a 5-model defender carrying the unit-wide Counter rule when asked.
fn contexts(epoch: u32, counter: bool) -> (Ctx, Ctx) {
    let mut reg = Registries::new(&repo_root());
    let charger = UnitStatic::build_for(&mut reg, &profile("Charger", 2, vec!["Impact(3)"], vec![]), epoch);
    let defender = UnitStatic::build_for(
        &mut reg,
        &profile("Defender", 5, if counter { vec!["Counter"] } else { vec![] }, vec![]),
        epoch,
    );
    (charger.ctx, defender.ctx)
}

fn ev(epoch: u32, counter: bool) -> f64 {
    let (att, def) = contexts(epoch, counter);
    crate::combat::impact_ev(&att, &def)
}

#[test]
fn the_estimate_ignores_counter_at_epoch_73() {
    assert_eq!(ev(crate::acts::EPOCH_73_V36, true), ev(crate::acts::EPOCH_73_V36, false),
        "rules 3.6: Counter takes no Impact dice away");
}

#[test]
fn the_estimate_still_sees_counter_at_epoch_72() {
    assert!(ev(crate::acts::EPOCH_72_PLAYTEST_RULES, true) < ev(crate::acts::EPOCH_72_PLAYTEST_RULES, false),
        "epoch 72 keeps the Counter Impact cut");
}
