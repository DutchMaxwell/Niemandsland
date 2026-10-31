//! MEL-04e tests (rules 3.6, lane melee): the AI's Impact estimate sees the defender's Brace cut, so
//! a charge into a braced unit is no longer priced as if it were unbraced. Epoch 72 keeps today's
//! value; a Fatigued braced defender cuts nothing; a unit without Brace is the control.
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

/// The estimate's two contexts: a 2-model Impact(3) charger and a 2-model defender that carries
/// Brace(1) on its weapon when `brace`. `fatigued` stamps the defender's own flag.
fn contexts(epoch: u32, brace: bool, fatigued: bool) -> (Ctx, Ctx) {
    let mut reg = Registries::new(&repo_root());
    let charger = UnitStatic::build_for(&mut reg, &profile("Charger", 2, vec!["Impact(3)"], vec![]), epoch);
    let defender = UnitStatic::build_for(
        &mut reg,
        &profile("Defender", 2, vec![], if brace { vec!["Brace(1)"] } else { vec![] }),
        epoch,
    );
    let mut def = defender.ctx;
    def.fatigued = fatigued;
    (charger.ctx, def)
}

fn ev(epoch: u32, brace: bool, fatigued: bool) -> f64 {
    let (att, def) = contexts(epoch, brace, fatigued);
    crate::combat::impact_ev(&att, &def)
}

#[test]
fn the_estimate_sees_two_brace_models_at_epoch_73() {
    assert!(ev(crate::acts::EPOCH_73_V36, true, false) < ev(crate::acts::EPOCH_73_V36, false, false),
        "Impact(3) into two Brace(1) models must price lower than the unbraced defender");
}

#[test]
fn the_estimate_ignores_brace_at_epoch_72() {
    assert_eq!(ev(crate::acts::EPOCH_72_PLAYTEST_RULES, true, false),
        ev(crate::acts::EPOCH_72_PLAYTEST_RULES, false, false),
        "epoch 72 replays today's unbraced value");
}

#[test]
fn a_fatigued_braced_defender_cuts_nothing() {
    assert_eq!(ev(crate::acts::EPOCH_73_V36, true, true), ev(crate::acts::EPOCH_73_V36, false, true),
        "a Fatigued braced unit removes nothing in the estimate either");
}

#[test]
fn a_control_unit_without_brace_is_unchanged() {
    assert_eq!(ev(crate::acts::EPOCH_73_V36, false, false), ev(crate::acts::EPOCH_72_PLAYTEST_RULES, false, false),
        "no Brace weapon, no cut at either epoch");
}
