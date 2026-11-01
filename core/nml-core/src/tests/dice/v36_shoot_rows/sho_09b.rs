use super::super::*;

// SHO-09b (rules 3.6, lane shoot): the conditional-AP condition that reads the TARGET's
// surroundings — MOST of its models stand within 1" of terrain. The arm reuses the same
// majority sampler as the Stealth-alias terrain gate; no shipped map entry spells the name,
// so it needs no epoch gate (the SHO-09 precedent). RED before the arm exists: the unknown
// spelling answers 0, so the target saves at its plain Defense.

use crate::acts::EPOCH_73_V36;
use crate::io::{Action, Seams};
use crate::rng::GodotRng;
use crate::sim::{resolve_stochastic_tray_on_board, HOLD};
use crate::state::{Profiles, Roster, State};
use crate::terrain::{CellParams, PlainTerrain, Terrain, FOREST};
use crate::unit::UnitStatic;
use std::collections::HashMap;
use std::rc::Rc;

fn spec(condition: &str) -> CondAp {
    CondAp { ap_bonus: 1, condition: condition.into(), name: "Probe Gun".into(), ..Default::default() }
}

/// A Gunner (unit 0) twelve inches from a Target (unit 2) that carries `alive` models.
/// Both carry one conditional-AP entry spelled `condition`.
fn line(condition: Option<&str>, alive: i64) -> (State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.alive = vec![1, 0, alive, 0];
    st.wounds = vec![vec![1], Vec::new(), vec![1; alive as usize], Vec::new()];
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.positions[2] =
        (0..alive).map(|k| [(12.0 + 0.02 * k as f64) * crate::IN2M, 0.0, 0.0]).collect();
    Rc::make_mut(&mut st.radii)[0] = vec![crate::IN2M];
    Rc::make_mut(&mut st.radii)[2] = vec![crate::IN2M; alive as usize];
    let cond: Vec<CondAp> = condition.map(|c| vec![spec(c)]).unwrap_or_default();
    let mut gunner = UnitStatic { name: "Gunner".into(), model_count: 1, ..Default::default() };
    gunner.ctx = Ctx { quality: 4, models: 1, tough: 1, ..Default::default() };
    gunner.shoot = vec![ShootProfile {
        name: "Probe Gun".into(),
        attacks: 12,
        count: 1,
        range: 24,
        cond_ap: cond,
        ..Default::default()
    }];
    let mut target = UnitStatic { name: "Target".into(), model_count: alive, ..Default::default() };
    target.ctx = Ctx { defense: 4, quality: 4, tough: 1, ..Default::default() };
    target.wounds_max = vec![1; alive as usize];
    (st, vec![gunner, UnitStatic::default(), target, UnitStatic::default()])
}

fn act() -> Action {
    Action {
        kind: HOLD,
        unit: "a".into(),
        dest: None,
        shoot: Some("b".into()),
        charge: None,
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    }
}

/// A school board with FOREST in the target's own cell (world x 12..15", z 0..3") — the
/// target's endpoint cell never blocks the centre line, so the volley still sees it.
fn by_terrain() -> Terrain {
    Terrain::build(&PlainTerrain {
        cells: vec![[19.0, 15.0, FOREST as f64]],
        sandbox: vec![],
        pieces: vec![],
        walls: vec![],
        cell_params: CellParams {
            table_size_feet: [6.0, 4.0],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 3.0,
            inches_to_meters: crate::IN2M,
        },
    })
}

/// The Defense target of the volley's save batch: 4 = no conditional AP, 5 = AP(+1).
fn save_target_of(condition: Option<&str>, alive: i64, terrain: &Terrain) -> i64 {
    let (st, statics) = line(condition, alive);
    let mut tray = Tray::seeded(27);
    let mut rng = GodotRng::new(0);
    let (_, shot) = resolve_stochastic_tray_on_board(
        &statics,
        &st,
        &act(),
        terrain,
        Seams { rules_epoch: EPOCH_73_V36, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .expect("the probe activation resolves");
    shot.rolls.iter().find(|r| r.kind == "defense").expect("the volley leaves a save batch").target
}

#[test]
fn near_terrain_pays_only_against_a_target_by_terrain_at_epoch_73() {
    assert_eq!(save_target_of(Some("near_terrain"), 5, &by_terrain()), 5, "5 models by terrain: AP(+1) -> 5+");
    assert_eq!(save_target_of(Some("near_terrain"), 5, &Terrain::default()), 4, "no terrain: no bonus");
    assert_eq!(save_target_of(None, 5, &by_terrain()), 4, "a plain entry never pays");
}

#[test]
fn a_single_model_by_terrain_pays_at_epoch_73() {
    assert_eq!(save_target_of(Some("near_terrain"), 1, &by_terrain()), 5, "the lone model is by terrain");
    assert_eq!(save_target_of(Some("near_terrain"), 1, &Terrain::default()), 4, "the lone model is in the open");
}

#[test]
fn existing_conditions_answer_unchanged_at_epoch_72() {
    let spec = |cond: &str, threshold: i64| CondAp {
        ap_bonus: 2,
        condition: cond.into(),
        threshold,
        over_in: 9.0,
        within_in: 12.0,
        ..Default::default()
    };
    assert_eq!(conditional_ap_bonus(&spec("vs_tough_ge", 3), 3, 4, false, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("vs_tough_ge", 3), 2, 4, false, 0.0, true), 0);
    assert_eq!(conditional_ap_bonus(&spec("vs_armor", 3), 1, 3, false, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("ranged_over", 0), 1, 5, false, 12.0, false), 2);
    assert_eq!(conditional_ap_bonus(&spec("ranged_within", 0), 1, 5, false, 12.0, false), 2);
    assert_eq!(conditional_ap_bonus(&spec("on_charge", 0), 1, 5, true, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("on_charge", 0), 1, 5, false, 0.0, true), 0);
}
