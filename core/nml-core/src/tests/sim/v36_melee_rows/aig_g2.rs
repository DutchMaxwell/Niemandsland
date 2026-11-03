//! AIG-G2 tests (rules 3.6, AI gate G2): Unwieldy and Imprecise sit on WEAPONS in the shipped
//! lists, but their readers walked unit rules only, so neither ever applied. From `EPOCH_73_V36`
//! a weapon-borne Unwieldy makes its unit strike last on a charge and a weapon-borne Imprecise
//! costs that weapon's attacks -1 to hit (shooting and melee); epoch 72 replays today's dice.
//! Every unit here is built the way the game builds it: a real `Profile` with real weapons
//! through `UnitStatic::build_for`.
use super::super::*;
use crate::dice::resolve_shooting_with_tray;
use crate::state::Weapon;
use crate::Registries;

const E73: u32 = crate::acts::EPOCH_73_V36;
const E72: u32 = crate::acts::EPOCH_72_PLAYTEST_RULES;

fn profile(name: &str, range: f64, attacks: i64, weapon_rules: Vec<&str>) -> Profile {
    Profile {
        cost: 0,
        unit_id: name.into(),
        name: name.into(),
        quality: 4,
        defense: 4,
        tough: 40,
        wounds_max: vec![40],
        model_count: 1,
        weapons: vec![Weapon {
            name: "Blade".into(),
            range,
            attacks,
            count: 1,
            ap: 0,
            rules: weapon_rules.into_iter().map(str::to_string).collect(),
        }],
        special_rules: vec![],
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

/// One charge: a 1-model charger (unit 0, `attacks` melee attacks, `weapon_rules` on its weapon)
/// into a 1-model defender (unit 1) with a plain melee weapon. Seeded, so two runs differ only
/// in the rule under test.
fn charge(epoch: u32, attacks: i64, weapon_rules: Vec<&str>) -> ShootResult {
    let mut reg = Registries::new(&repo_root());
    let charger = UnitStatic::build_for(&mut reg, &profile("Charger", 0.0, attacks, weapon_rules), epoch);
    let defender = UnitStatic::build_for(&mut reg, &profile("Defender", 0.0, 1, vec![]), epoch);
    let statics = vec![charger, defender];
    let mut st = four_unit_line();
    let any: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![any.clone(), any], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    (st.positions[0], st.wounds[0], Rc::make_mut(&mut st.radii)[0]) = (vec![[0.0, 0.0, 0.0]], vec![40], vec![IN2M]);
    (st.positions[1], st.wounds[1], Rc::make_mut(&mut st.radii)[1]) = (vec![[0.0, 0.0, 0.0]], vec![40], vec![IN2M]);
    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let (mut tray, mut shot) = (Tray::seeded(27), ShootResult::default());
    tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    shot
}

/// Who rolled the first attack dice of the melee (no Impact in these units, so: who struck first).
fn first_striker(shot: &ShootResult) -> String {
    shot.rolls.iter().find(|r| r.kind == "attack").map(|r| r.owner.clone()).unwrap_or_default()
}

fn has_line(shot: &ShootResult, line: &str) -> bool {
    shot.log.iter().any(|l| l == line)
}

/// The charger's first attack roll's faces, and the hits the defender's first save batch faced.
fn charger_faces_and_hits(shot: &ShootResult) -> (Vec<u8>, i64) {
    let faces = shot.rolls.iter().find(|r| r.kind == "attack" && r.owner == "Charger").map(|r| r.faces.clone()).unwrap();
    let hits = shot.rolls.iter().find(|r| r.kind == "defense" && r.owner == "Defender").map(|r| r.count).unwrap_or(0);
    (faces, hits)
}

fn at_least(faces: &[u8], target: u8) -> i64 {
    faces.iter().filter(|&&f| f >= target).count() as i64
}

#[test]
fn a_weapon_borne_unwieldy_makes_the_charger_strike_last_at_epoch_73() {
    let shot = charge(E73, 1, vec!["Unwieldy"]);
    assert_eq!(first_striker(&shot), "Defender", "the strike-back goes first");
    assert!(has_line(&shot, "Unwieldy: Charger strikes last on the charge"), "{:?}", shot.log);
}

#[test]
fn a_weapon_borne_unwieldy_is_inert_at_epoch_72() {
    let shot = charge(E72, 1, vec!["Unwieldy"]);
    assert_eq!(first_striker(&shot), "Charger", "epoch 72 replays today's order");
    assert!(!shot.log.iter().any(|l| l.contains("Unwieldy")), "{:?}", shot.log);
}

#[test]
fn a_charger_without_unwieldy_strikes_first_at_both_epochs() {
    for epoch in [E72, E73] {
        let shot = charge(epoch, 1, vec![]);
        assert_eq!(first_striker(&shot), "Charger");
        assert!(!shot.log.iter().any(|l| l.contains("Unwieldy")), "{:?}", shot.log);
    }
}

#[test]
fn a_weapon_borne_imprecise_costs_the_melee_weapon_one_to_hit_at_epoch_73() {
    let control = charge(E73, 60, vec![]);
    let (faces, control_hits) = charger_faces_and_hits(&control);
    assert_eq!(control_hits, at_least(&faces, 4), "Quality 4+ without the rule");
    let shot = charge(E73, 60, vec!["Imprecise"]);
    let (faces, hits) = charger_faces_and_hits(&shot);
    assert_eq!(hits, at_least(&faces, 5), "Imprecise: -1 to hit turns Quality 4+ into 5+");
    assert_ne!(hits, control_hits, "the fixture must tell the two targets apart");
    assert!(has_line(&shot, "Imprecise: -1 to hit on Charger's strikes"), "{:?}", shot.log);
}

#[test]
fn a_weapon_borne_imprecise_is_inert_at_epoch_72() {
    let shot = charge(E72, 60, vec!["Imprecise"]);
    let (faces, hits) = charger_faces_and_hits(&shot);
    assert_eq!(hits, at_least(&faces, 4), "epoch 72 replays today's dice");
    assert!(!shot.log.iter().any(|l| l.contains("Imprecise")), "{:?}", shot.log);
}

/// The shooting leg: a ranged weapon carrying Imprecise, the profile taken straight off the
/// built unit (`us.shoot`), resolved against a built defender at 12".
fn volley(epoch: u32, weapon_rules: Vec<&str>) -> ShootResult {
    let mut reg = Registries::new(&repo_root());
    let shooter = UnitStatic::build_for(&mut reg, &profile("Shooter", 24.0, 60, weapon_rules), epoch);
    let target = UnitStatic::build_for(&mut reg, &profile("Target", 0.0, 1, vec![]), epoch);
    let mut tray = Tray::seeded(27);
    resolve_shooting_with_tray(&shooter.shoot, &[0], &[60], &shooter.ctx, &target.ctx, 12.0, &mut tray)
}

#[test]
fn a_weapon_borne_imprecise_costs_the_ranged_weapon_one_to_hit_at_epoch_73() {
    let control = volley(E73, vec![]);
    let control_faces = control.rolls.iter().find(|r| r.kind == "attack").map(|r| r.faces.clone()).unwrap();
    let control_hits = control.rolls.iter().find(|r| r.kind == "defense").map(|r| r.count).unwrap_or(0);
    assert_eq!(control_hits, at_least(&control_faces, 4), "Quality 4+ without the rule");
    let shot = volley(E73, vec!["Imprecise"]);
    let faces = shot.rolls.iter().find(|r| r.kind == "attack").map(|r| r.faces.clone()).unwrap();
    let hits = shot.rolls.iter().find(|r| r.kind == "defense").map(|r| r.count).unwrap_or(0);
    assert_eq!(hits, at_least(&faces, 5), "Imprecise: -1 to hit turns Quality 4+ into 5+");
    assert_ne!(hits, control_hits, "the fixture must tell the two targets apart");
    assert!(shot.log.iter().any(|l| l.starts_with("Imprecise: -1 to hit")), "{:?}", shot.log);
}

#[test]
fn a_weapon_borne_imprecise_is_inert_at_epoch_72_when_shooting() {
    let shot = volley(E72, vec!["Imprecise"]);
    let faces = shot.rolls.iter().find(|r| r.kind == "attack").map(|r| r.faces.clone()).unwrap();
    let hits = shot.rolls.iter().find(|r| r.kind == "defense").map(|r| r.count).unwrap_or(0);
    assert_eq!(hits, at_least(&faces, 4));
    assert!(!shot.log.iter().any(|l| l.contains("Imprecise")), "{:?}", shot.log);
}
