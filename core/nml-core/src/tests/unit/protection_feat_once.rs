use super::*;

/// #2613 — Protection Feat is once per game. A Protection Feat unit (real aof/saurians entry: Regeneration
/// primitive, 5+, `uses_per_game` 1) takes two volleys in one game; from `EPOCH_75_TABLE_FIXES` the second one
/// draws no Feat dice, at 74 both roll. The asserts read the roll record, never the faces.
fn pf_unit(epoch: u32) -> (UnitStatic, crate::state::Profile) {
    let profile = crate::state::Profile {
        cost: 0,
        unit_id: "pf".into(), name: "Warriors".into(), quality: 3, defense: 3, tough: 1,
        wounds_max: vec![1], model_count: 1, weapons: vec![],
        special_rules: vec!["Protection Feat".into()], caster_value: 0, base_radius: 0.0,
        base_shape: String::new(), base_w_mm: 0.0, base_d_mm: 0.0,
        game_system: "aof".into(), faction_folder: "saurians".into(),
        item_grants: vec![], attached_hero_rules: vec![], move_bands: Default::default(),
    };
    let mut reg = Registries::new(&repo_root());
    (UnitStatic::build_for(&mut reg, &profile, epoch), profile)
}

fn pf_state(profile: crate::state::Profile) -> crate::state::State {
    let plain = r#"{"round":0,"rounds_total":1,"units":{"pf":{"player":1,"alive":1,"activated":false,"shaken":false,"fatigued":false,"in_cover":false,"aircraft":false,"dormant":false,"dormant_models":0,"dormant_wounds":[],"casts":0,"morale_bonus":0,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":1.0,"positions":[[0.0,0.0,0.0]],"wounds":[1],"radii":[0.0254],"mods":{},"mods_base":{},"attached":[],"attached_to":""}}}"#;
    let mut index = std::collections::HashMap::new();
    index.insert("pf".to_string(), 0);
    let mut pc = crate::state::ProfileCache::new(std::rc::Rc::new(crate::state::Profiles {
        list: vec![profile], index,
    }));
    let mut rc = None;
    crate::io::state_from_json(plain, &mut pc, &mut rc).unwrap()
}

/// One 24-die volley at the unit; the exchange then spends the latch like the volley seams do.
fn volley(us: &UnitStatic, st: &mut crate::state::State, epoch: u32) -> crate::dice::ShootResult {
    let att = Ctx { quality: 2, models: 1, ..Default::default() };
    let def = crate::sim::ctx_live(
        crate::sim::ctx_of(us, st, 0), std::slice::from_ref(us), st, 0, false, epoch,
    );
    let mut tray = crate::dice::Tray::seeded(27);
    let shooter = UnitStatic::build_for(
        &mut Registries::new(&repo_root()),
        &crate::state::Profile {
            cost: 0, unit_id: "sh".into(), name: "Shooter".into(), quality: 2, defense: 4, tough: 1,
            wounds_max: vec![1], model_count: 1, caster_value: 0, base_radius: 0.0,
            base_shape: String::new(), base_w_mm: 0.0, base_d_mm: 0.0,
            game_system: "gf".into(), faction_folder: "knight_brothers".into(),
            special_rules: vec![], item_grants: vec![], attached_hero_rules: vec![], move_bands: Default::default(),
            weapons: vec![crate::state::Weapon { name: "Rifle".into(), range: 24.0, attacks: 24, count: 1, ap: 0, rules: vec![] }],
        },
        epoch,
    );
    let out = crate::dice::resolve_shooting_with_tray(&shooter.shoot, &[0], &[24], &att, &def, 12.0, &mut tray);
    crate::sim::spend_protection_feat(std::slice::from_ref(us), st, 0, out.caused > 0, epoch);
    out
}

fn feat_rolls(out: &crate::dice::ShootResult) -> usize {
    out.rolls.iter().filter(|r| r.target == 5).count()
}

#[test]
fn the_second_volley_rolls_no_feat_dice_from_epoch_75() {
    let e = crate::acts::EPOCH_75_TABLE_FIXES;
    let (us, profile) = pf_unit(e);
    let mut st = pf_state(profile);
    let first = volley(&us, &mut st, e);
    assert!(first.caused > 0, "fixture seed no longer wounds");
    assert_eq!(feat_rolls(&first), 1, "the first volley rolls the Feat: {:?}", first.rolls);
    let second = volley(&us, &mut st, e);
    assert_eq!(feat_rolls(&second), 0, "the Feat is spent, no second roll: {:?}", second.rolls);
    assert_eq!(second.wounds, second.caused, "every wound lands once the Feat is spent");
}

#[test]
fn at_epoch_74_the_feat_rolls_both_times() {
    let e = crate::acts::EPOCH_75_TABLE_FIXES - 1;
    let (us, profile) = pf_unit(e);
    let mut st = pf_state(profile);
    assert_eq!(feat_rolls(&volley(&us, &mut st, e)), 1);
    assert_eq!(feat_rolls(&volley(&us, &mut st, e)), 1, "epoch 74 replays the unlimited roll");
}

/// One volley of a Deadly(3) launcher (resolved first) and a 24-die rifle at the unit, the per-model Deadly landing on.
fn two_weapon_volley(us: &UnitStatic, st: &crate::state::State, epoch: u32) -> crate::dice::ShootResult {
    let def = crate::sim::ctx_live(crate::sim::ctx_of(us, st, 0), std::slice::from_ref(us), st, 0, false, epoch);
    let weapon = |name: &str, attacks: i64, rules: Vec<String>| crate::state::Weapon { name: name.into(), range: 24.0, attacks, count: 1, ap: 0, rules };
    let shooter = UnitStatic::build_for(
        &mut Registries::new(&repo_root()),
        &crate::state::Profile {
            cost: 0, unit_id: "sh".into(), name: "Shooter".into(), quality: 2, defense: 4, tough: 1,
            wounds_max: vec![1], model_count: 1, caster_value: 0, base_radius: 0.0,
            base_shape: String::new(), base_w_mm: 0.0, base_d_mm: 0.0,
            game_system: "gf".into(), faction_folder: "knight_brothers".into(),
            special_rules: vec![], item_grants: vec![], attached_hero_rules: vec![], move_bands: Default::default(),
            weapons: vec![weapon("Launcher", 6, vec!["Deadly(3)".into()]), weapon("Rifle", 24, vec![])],
        },
        epoch,
    );
    let att = Ctx { quality: 2, models: 1, rules_epoch: epoch, ..Default::default() };
    let strikers = [crate::dice::Shooter { profiles: &shooter.shoot, keep: &[0, 1], attacks: &[6, 24], att: &att, owner: "Shooter" }];
    let mut tray = crate::dice::Tray::seeded(27);
    crate::dice::resolve_volley_leg(&strikers, &def, "Warriors", 12.0, 12.0, false, false, false, false, true, false, &|_| false, &|_, _| None, &mut tray)
}

/// PENDING_EPOCH_PROTECTION_FEAT_ONCE (coverage ledger shoot m2 COV-D1; 3.6 army books: once per game, when the unit takes wounds):
/// inside ONE volley the Deadly launcher's wounds roll the Feat and spend it, so the rifle's wounds after it roll no Feat dice.
/// At 95 every group of the volley rolled at the Feat's 5+.
#[test]
fn one_volley_rolls_the_feat_once_from_96() {
    let e = crate::acts::PENDING_EPOCH_PROTECTION_FEAT_ONCE;
    let (us, profile) = pf_unit(e);
    let st = pf_state(profile.clone());
    let new = two_weapon_volley(&us, &st, e);
    assert!(new.deadly_tally > 0 && new.caused > new.deadly_tally, "fixture: both weapons wound: {:?}", new.rolls);
    assert_eq!(feat_rolls(&new), 1, "96: the first group spends the Feat: {:?}", new.rolls);
    let (us95, profile95) = pf_unit(e - 1);
    let old = two_weapon_volley(&us95, &pf_state(profile95), e - 1);
    assert!(feat_rolls(&old) >= 2, "95 replays a Feat roll per group: {:?}", old.rolls);
}
