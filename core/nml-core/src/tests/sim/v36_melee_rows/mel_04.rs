//! MEL-04 tests (rules 3.6, lane melee): a defender's Brace(X) weapons take X Impact dice off the
//! charger for EVERY living braced model (host and joined hero alike), floored at 0, from
//! `EPOCH_73_V36`; epoch 72 keeps today's dice and a Fatigued braced unit removes nothing.
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

/// One charge melee: a 1-model Impact(`impact`) charger (unit 0) into a `def_models`-model
/// defender (unit 1), optionally joined by a 1-model Brace hero (unit 2). Returns the Impact
/// dice rolled and the battle-log lines the charger's tray produced.
fn charge(
    epoch: u32,
    impact: i64,
    def_models: i64,
    brace: bool,
    hero_brace: bool,
    defender_fatigued: bool,
) -> (i64, Vec<String>) {
    let mut reg = Registries::new(&repo_root());
    let impact_rule = format!("Impact({impact})");
    let charger = UnitStatic::build_for(&mut reg, &profile("Charger", 1, vec![impact_rule.as_str()], vec![]), epoch);
    let defender = UnitStatic::build_for(
        &mut reg,
        &profile("Defender", def_models, vec![], if brace { vec!["Brace(1)"] } else { vec![] }),
        epoch,
    );
    let hero = UnitStatic::build_for(
        &mut reg,
        &profile("Hero", 1, vec![], if hero_brace { vec!["Brace(1)"] } else { vec![] }),
        epoch,
    );
    let statics = vec![charger, defender, hero];
    let mut st = four_unit_line();
    let any: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into(), "bh".into()], index: HashMap::new(), profile: vec![0, 1, 2] });
    st.profiles = Rc::new(Profiles { list: vec![any.clone(), any.clone(), any], index: HashMap::new() });
    st.player = vec![0, 1, 1];
    st.alive = vec![1, def_models, hero_brace as i64];
    st.attached = Rc::new(vec![vec![], if hero_brace { vec![2] } else { vec![] }, vec![]]);
    st.attached_to = Rc::new(vec![None, None, if hero_brace { Some(1) } else { None }]);
    st.fatigued[1] = defender_fatigued;
    let n = def_models as usize;
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    (st.wounds[0], Rc::make_mut(&mut st.radii)[0]) = (vec![1], vec![IN2M]);
    (st.positions[1], st.wounds[1], Rc::make_mut(&mut st.radii)[1]) = (vec![[0.0, 0.0, 0.0]; n], vec![1; n], vec![IN2M; n]);
    (st.positions[2], st.wounds[2], Rc::make_mut(&mut st.radii)[2]) = (vec![[0.0, 0.0, 0.0]], vec![1], vec![IN2M]);
    let seams = Seams { rules_epoch: epoch, tray_exact: hero_brace, ..Default::default() };
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
fn brace_takes_two_impact_dice_at_epoch_73() {
    let (dice, _) = charge(crate::acts::EPOCH_73_V36, 3, 2, true, false, false);
    assert_eq!(dice, 1, "Impact(3) into two Brace(1) models: 3 - 2 = 1 die");
}

#[test]
fn brace_is_inert_at_epoch_72() {
    let (dice, _) = charge(crate::acts::EPOCH_72_PLAYTEST_RULES, 3, 2, true, false, false);
    assert_eq!(dice, 3, "epoch 72 replays today's dice: nothing is taken off");
}

#[test]
fn a_fatigued_braced_unit_takes_nothing_at_epoch_73() {
    let (dice, _) = charge(crate::acts::EPOCH_73_V36, 3, 2, true, false, true);
    assert_eq!(dice, 3, "a Fatigued braced unit removes nothing");
}

#[test]
fn a_joined_heros_brace_counts_at_epoch_73() {
    let (dice, _) = charge(crate::acts::EPOCH_73_V36, 3, 2, false, true, false);
    assert_eq!(dice, 2, "the joined hero's one Brace model takes one of three Impact dice");
}

#[test]
fn a_control_unit_without_brace_rolls_three_at_both_epochs() {
    let (old, _) = charge(crate::acts::EPOCH_72_PLAYTEST_RULES, 3, 2, false, false, false);
    let (new, _) = charge(crate::acts::EPOCH_73_V36, 3, 2, false, false, false);
    assert_eq!((old, new), (3, 3), "no Brace weapon, no cut");
}

#[test]
fn the_log_names_brace_and_its_fatigue_exemption() {
    let (_, lines) = charge(crate::acts::EPOCH_73_V36, 3, 2, true, false, false);
    assert!(lines.iter().any(|l| l == "Brace: Defender takes 2 Impact dice off Charger"), "{lines:?}");
    let (_, tired) = charge(crate::acts::EPOCH_73_V36, 3, 2, true, false, true);
    assert!(tired.iter().any(|l| l == "Brace: no effect, Defender is Fatigued"), "{tired:?}");
}
