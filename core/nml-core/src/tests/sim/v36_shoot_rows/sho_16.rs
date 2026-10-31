//! SHO-16 tests (rules 3.6, lane shoot): Cumbersome — a unit that moved this activation
//! fires no volley, and says so. Below EPOCH_73_V36 it shoots after an Advance as ever.
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::rules::Registries;
use crate::state::{Profiles, Roster, Weapon};

/// The checkout this crate lives in — mirrors the dice tests' helper.
fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// A 20-attack gunner "a" carrying `rules` (player 0) and a target "b" 20" up +x
/// (player 1). The gunner's static is built off the SHIPPED gf map at `epoch`.
fn gunner_line(rules: &[&str], epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "ah".into(), "b".into(), "bh".into()],
        index: ["a", "ah", "b", "bh"].iter().enumerate().map(|(i, k)| (k.to_string(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    let base = st.profiles.list[0].clone();
    let mut gunner = base.clone();
    gunner.name = "Gunner".into();
    gunner.game_system = "gf".into();
    gunner.wounds_max = vec![1];
    gunner.special_rules = rules.iter().map(|r| r.to_string()).collect();
    gunner.weapons = vec![Weapon { name: "Rifle".into(), range: 24.0, attacks: 20, count: 1, ap: 0, rules: vec![] }];
    st.profiles = Rc::new(Profiles {
        list: vec![gunner.clone(), base.clone(), base.clone(), base],
        index: HashMap::new(),
    });
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![], vec![[20.0 * IN2M, 0.0, 0.0]], vec![]];
    st.wounds = vec![vec![1], vec![], vec![1], vec![]];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], vec![]]);
    st.alive = vec![1, 0, 1, 0];
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, None]);
    let mut reg = Registries::new(&repo_root());
    let foe = UnitStatic {
        name: "b".into(),
        model_count: 1,
        wounds_max: vec![1],
        ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
        ..Default::default()
    };
    let statics = vec![
        UnitStatic::build_for(&mut reg, &gunner, epoch),
        UnitStatic { name: "ah".into(), ..Default::default() },
        foe,
        UnitStatic { name: "bh".into(), ..Default::default() },
    ];
    (st, statics)
}

/// Unit "a" advances `step_in` inches toward "b" (0 = stands) and shoots it.
fn advance_and_shoot(st: &State, statics: &[UnitStatic], epoch: u32, step_in: f64) -> ShootResult {
    let dest = if step_in > 0.0 { Some([step_in * IN2M, 0.0, 0.0]) } else { None };
    let action = Action {
        kind: ADVANCE,
        unit: "a".into(),
        dest,
        shoot: Some("b".into()),
        charge: None,
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    };
    let seams = Seams { rules_epoch: epoch, moved_shoot: true, ..Seams::default() };
    let mut rng = crate::rng::GodotRng::new(0);
    let mut tray = Tray::seeded(11);
    resolve_stochastic_tray_on_board(statics, st, &action, &small_board(), seams, &mut rng, &mut tray)
        .expect("the activation resolves")
        .1
}

/// The EPOCH_72 leg: rules 3.5 has no Cumbersome, so the unit shoots after its Advance.
#[test]
fn cumbersome_unit_shoots_after_an_advance_at_epoch_72() {
    let (st, statics) = gunner_line(&["Cumbersome"], EPOCH_72_PLAYTEST_RULES);
    let shot = advance_and_shoot(&st, &statics, EPOCH_72_PLAYTEST_RULES, 6.0);
    assert!(!shot.rolls.is_empty(), "rules 3.5: the volley is rolled after the Advance");
    assert!(shot.log.iter().all(|l| !l.contains("Cumbersome")), "rules 3.5 names no Cumbersome: {:?}", shot.log);
}

/// The EPOCH_73 leg: the unit moved, so no volley is rolled.
#[test]
fn cumbersome_unit_fires_no_volley_after_an_advance_at_epoch_73() {
    let (st, statics) = gunner_line(&["Cumbersome"], EPOCH_73_V36);
    let shot = advance_and_shoot(&st, &statics, EPOCH_73_V36, 6.0);
    assert!(shot.rolls.is_empty(), "rules 3.6: a Cumbersome unit that moved fires nothing, rolled {}", shot.rolls.len());
}

/// Rules-must-log: the skipped shot names the rule that took it away.
#[test]
fn cumbersome_logs_the_blocked_shot_at_epoch_73() {
    let (st, statics) = gunner_line(&["Cumbersome"], EPOCH_73_V36);
    let shot = advance_and_shoot(&st, &statics, EPOCH_73_V36, 6.0);
    let hits = shot.log.iter().filter(|l| l.contains("Cumbersome") && l.contains("Gunner")).count();
    assert_eq!(hits, 1, "one line naming the rule and the unit: {:?}", shot.log);
}

/// Control: a Cumbersome unit that stands still still shoots (Hold + shoot).
#[test]
fn cumbersome_unit_that_stands_still_shoots_at_epoch_73() {
    let (st, statics) = gunner_line(&["Cumbersome"], EPOCH_73_V36);
    let shot = advance_and_shoot(&st, &statics, EPOCH_73_V36, 0.0);
    assert!(!shot.rolls.is_empty(), "rules 3.6: standing still keeps the shot");
    assert!(shot.log.iter().all(|l| !l.contains("Cumbersome")), "no block to name: {:?}", shot.log);
}

/// Control: any other unit keeps its shot after an Advance at epoch 73.
#[test]
fn an_ordinary_unit_shoots_after_an_advance_at_epoch_73() {
    let (st, statics) = gunner_line(&[], EPOCH_73_V36);
    let shot = advance_and_shoot(&st, &statics, EPOCH_73_V36, 6.0);
    assert!(!shot.rolls.is_empty(), "rules 3.6: only Cumbersome loses the shot");
}

/// The map half: both shipped maps carry Cumbersome in `common`, so every book
/// that fields it resolves a primitive (and stops printing "apply manually").
#[test]
fn both_shipped_maps_carry_cumbersome_in_common() {
    let mut reg = Registries::new(&repo_root());
    for system in ["gf", "aof"] {
        assert!(reg.rules_for(system).has_primitive("", "Cumbersome"), "{system} map lacks Cumbersome");
    }
}
