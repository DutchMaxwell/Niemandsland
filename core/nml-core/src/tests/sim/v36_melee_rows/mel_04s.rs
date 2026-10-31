//! MEL-04s tests (rules 3.6, lane melee): a Shaken braced unit takes no Impact dice off a charger,
//! alongside the Fatigued exemption; a fresh braced unit still cuts and epoch 72 keeps today's dice.
use super::super::*;
use crate::combat::IMPACT_HIT_TARGET;
use crate::state::Weapon;
use crate::Registries;

fn profile(name: &str, models: i64, rules: Vec<&str>, weapon_rules: Vec<&str>) -> Profile {
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
        special_rules: rules.into_iter().map(str::to_string).collect(),
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

/// One charge melee: a 1-model Impact(3) charger (unit 0) into a 2-model Brace(1) defender
/// (unit 1). Returns the Impact dice rolled and the battle-log lines produced.
fn charge(epoch: u32, defender_fatigued: bool, defender_shaken: bool) -> (i64, Vec<String>) {
    let mut reg = Registries::new(&repo_root());
    let charger = UnitStatic::build_for(&mut reg, &profile("Charger", 1, vec!["Impact(3)"], vec![]), epoch);
    let defender = UnitStatic::build_for(&mut reg, &profile("Defender", 2, vec![], vec!["Brace(1)"]), epoch);
    let statics = vec![charger, defender];
    let mut st = four_unit_line();
    let any: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![any.clone(), any], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 2];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.fatigued[1] = defender_fatigued;
    st.shaken[1] = defender_shaken;
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    (st.wounds[0], Rc::make_mut(&mut st.radii)[0]) = (vec![1], vec![IN2M]);
    (st.positions[1], st.wounds[1], Rc::make_mut(&mut st.radii)[1]) = (vec![[0.0, 0.0, 0.0]; 2], vec![1; 2], vec![IN2M; 2]);
    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let (mut tray, mut shot) = (Tray::seeded(27), ShootResult::default());
    tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    let impact_dice = shot
        .rolls
        .iter()
        .find(|r| r.kind == "attack" && r.owner == "Charger" && r.target == IMPACT_HIT_TARGET)
        .map(|r| r.count)
        .unwrap_or(-1);
    (impact_dice, shot.log)
}

#[test]
fn a_shaken_braced_unit_takes_nothing_at_epoch_73() {
    let (dice, _) = charge(crate::acts::EPOCH_73_V36, false, true);
    assert_eq!(dice, 3, "a Shaken braced unit removes nothing");
}

#[test]
fn a_fatigued_braced_unit_still_takes_nothing_at_epoch_73() {
    let (dice, _) = charge(crate::acts::EPOCH_73_V36, true, false);
    assert_eq!(dice, 3, "a Fatigued braced unit removes nothing");
}

#[test]
fn a_fresh_braced_unit_takes_two_at_epoch_73() {
    let (dice, _) = charge(crate::acts::EPOCH_73_V36, false, false);
    assert_eq!(dice, 1, "Impact(3) into two Brace(1) models: 3 - 2 = 1 die");
}

#[test]
fn brace_is_inert_at_epoch_72() {
    let (dice, _) = charge(crate::acts::EPOCH_72_PLAYTEST_RULES, false, false);
    assert_eq!(dice, 3, "epoch 72 replays today's dice: nothing is taken off");
}

#[test]
fn the_log_names_the_shaken_exemption() {
    let (_, lines) = charge(crate::acts::EPOCH_73_V36, false, true);
    assert!(lines.iter().any(|l| l == "Brace: no effect, Defender is Shaken"), "{lines:?}");
}
