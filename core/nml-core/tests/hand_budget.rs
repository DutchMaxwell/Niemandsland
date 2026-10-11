//! HAND-BUDGET — a synthetic RED for the step-9 F3b defect: the HAND prefilter can itself
//! overflow the token candidate budget. `menu::candidates_tuned` emits one RUSH row per
//! objective, so a board with more objectives than `tokens::N_CAND` produces a live menu the
//! pyo3 export (`tokens::build`) refuses with `TooManyCandidates`. The search must cap the hand
//! menu the same way it caps the grid tail. A hand-built board, NOT the marker corpus (whose
//! menus are small): one shooter and 200 distinct on-table objectives.

use nml_core::acts::ActStatics;
use nml_core::menu::{candidates_tuned, Candidate};
use nml_core::plan::{seams_of, tuning_of, LeafValue, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::{Scratch, Unsupported};
use nml_core::state::{Profile, ProfileCache, Profiles, State};
use nml_core::terrain::CellParams;
use nml_core::tokens::N_CAND;
use nml_core::unit::UnitStatic;
use nml_core::{
    state_from_json, Bands, CURRENT_RULES_EPOCH, Knobs, Pick, PlainTerrain, Registries, Terrain,
    IN2M,
};
use serde_json::json;
use std::collections::HashMap;
use std::rc::Rc;

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// More objectives than the token budget, so the hand menu (one RUSH row each) overflows it.
const OBJ_N: usize = 200;

fn profiles() -> Profiles {
    let shooter = json!({
        "unit_id": "shooter", "name": "Shooter", "quality": 4, "defense": 4,
        "tough": 1, "wounds_max": [1], "model_count": 1, "base_radius": 0.016,
        "game_system": "gf", "faction_folder": "alien_hives",
        "special_rules": [], "item_grants": [], "attached_hero_rules": [],
        "move_bands": {"advance": 6.0, "rush": 12.0},
        "weapons": [{"name": "Rifle", "range": 24.0, "attacks": 2, "count": 1, "ap": 0, "rules": []}]
    });
    let list: Vec<Profile> = [shooter]
        .iter()
        .map(|p| serde_json::from_value(p.clone()).unwrap())
        .collect();
    let mut index = HashMap::new();
    index.insert("shooter".to_string(), 0);
    Profiles { list, index }
}

/// 6x4 ft table, 3" school cells, no terrain.
fn terrain() -> Terrain {
    Terrain::build(&PlainTerrain {
        cells: vec![],
        sandbox: vec![],
        walls: vec![],
        pieces: vec![],
        cell_params: CellParams {
            table_size_feet: [6.0, 4.0],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 3.0,
            inches_to_meters: IN2M,
        },
    })
}

/// One shooter at the origin plus `OBJ_N` distinct on-table objectives (x 1..=20 cells,
/// z 1..=10 cells), each an open-terrain point.
fn state() -> State {
    let mut cache = ProfileCache::new(Rc::new(profiles()));
    let mut units = serde_json::Map::new();
    units.insert(
        "shooter".to_string(),
        json!({"player": 1, "alive": 1, "wounds": [1], "radii": [0.016],
            "positions": [[0.0, 0.0, 0.0]]}),
    );
    let objectives: Vec<serde_json::Value> = (0..OBJ_N)
        .map(|i| json!({"pos": [((i % 20) as f64 + 1.0) * 3.0 * IN2M, 0.0, ((i / 20) as f64 + 1.0) * 3.0 * IN2M], "owner": 0}))
        .collect();
    let mut st = state_from_json(
        &json!({"round": 1, "rounds_total": 4, "units": units, "objectives": objectives}).to_string(),
        &mut cache,
        &mut None,
    )
    .unwrap();
    st.bands[0] = Bands { advance: 6.0, rush: 12.0, charge: None };
    st.los_pairs = None;
    st
}

fn statics() -> Vec<UnitStatic> {
    let mut reg = Registries::new(REPO);
    profiles()
        .list
        .iter()
        .map(|p| UnitStatic::build_for(&mut reg, p, CURRENT_RULES_EPOCH))
        .collect()
}

struct Zero;
impl LeafValue for Zero {
    fn value(&self, leaves: &[&State], _side: i64) -> Result<Vec<f64>, Unsupported> {
        Ok(vec![0.0; leaves.len()])
    }
}

fn run(knobs: Knobs) -> Result<Pick, Unsupported> {
    let statics = statics();
    let terrain = terrain();
    let st = state();
    let mut p = Policy::new(&statics, &terrain, seams_of(&knobs));
    p.tuning = tuning_of(&knobs);
    let ast = ActStatics::default();
    let hook = Zero;
    let mut s = Search::new(Rollout::new(p, knobs), &ast);
    s.leaf_value = Some(&hook);
    s.leaf_value_w = 0.0;
    let mut sc = Scratch::default();
    s.run(&st, 1, &mut sc, None)
}

/// F3b RED — the hand menu over the budget is TRUNCATED, not emitted (`tokens::build` refuses
/// `TooManyCandidates` at the pyo3 boundary) and not declined. On the base `Pick::cands` carries
/// all ~200 rows, so the budget assert is RED; after the cap the hand menu is `N_CAND` and, with
/// the grid cap saturating to zero, the trace arithmetic still agrees.
#[test]
fn a_hand_menu_over_the_candidate_budget_is_truncated_not_refused() {
    let statics = statics();
    let terrain = terrain();
    let st = state();
    let k = Knobs { grid_k: 0, ..Knobs::default() };
    let mut sc = Scratch::default();
    let raw = candidates_tuned(&st, &terrain, &statics, 0, &mut sc, tuning_of(&k)).len();
    assert!(raw > N_CAND, "fixture too narrow: {raw} rows, budget {N_CAND}");

    let got = run(k).expect("a wide hand menu must not decline the act");
    assert!(
        got.cands.len() <= N_CAND,
        "hand rows overran the candidate budget ({} > {N_CAND})",
        got.cands.len()
    );
    assert_eq!(got.n_hand, got.cands.len(), "grid off: n_hand must equal the row count");
    assert!(got.grid.is_none(), "grid_k 0 stamped a grid trace");

    let k2 = Knobs { grid_k: 64, grid_units: 4, ..Knobs::default() };
    let p2 = run(k2).expect("the grid arm resolves");
    assert!(
        p2.cands.len() <= N_CAND,
        "hand + grid rows overran the candidate budget ({} > {N_CAND})",
        p2.cands.len()
    );
    let g = p2.grid.as_ref().expect("a widened pick carries a grid trace");
    assert_eq!(p2.cands.len(), p2.n_hand + g.completed, "the cap and the trace disagree");
    let _: &Candidate = &p2.cands[0];
}
