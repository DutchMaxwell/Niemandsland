//! MAUER-SZENARIO — synthetic REDs for the step-9 grid widen's F1 (moved-cell LOS parity) and F2
//! (`moved_shoot` seam) gates. A hand-built board, NOT the marker corpus: a shooter with a 24"
//! rifle at the origin, a victim 20" down +z, and a RUINS wall at z in [9",12") spanning the whole
//! advance band. Every advance cell is in range of the victim, but every MOVED-cell line to the
//! victim crosses the wall — so the grid's moved shot is only ever LOS-blocked.

use nml_core::acts::ActStatics;
use nml_core::menu::Candidate;
use nml_core::plan::{seams_of, tuning_of, LeafValue, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::{Scratch, Unsupported, ADVANCE};
use nml_core::state::{Profile, ProfileCache, Profiles, State};
use nml_core::terrain::{CellParams, RUINS};
use nml_core::unit::UnitStatic;
use nml_core::{
    state_from_json, Bands, CURRENT_RULES_EPOCH, Knobs, Pick, PlainTerrain, Registries, Terrain,
    IN2M,
};
use serde_json::json;
use std::collections::HashMap;
use std::rc::Rc;

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// The victim sits 20" down +z; the shooter at the origin.
const VICTIM_Z: f64 = 20.0 * IN2M;

fn profiles() -> Profiles {
    let shooter = json!({
        "unit_id": "shooter", "name": "Shooter", "quality": 4, "defense": 4,
        "tough": 1, "wounds_max": [1], "model_count": 1, "base_radius": 0.016,
        "game_system": "gf", "faction_folder": "alien_hives",
        "special_rules": [], "item_grants": [], "attached_hero_rules": [],
        "move_bands": {"advance": 6.0, "rush": 12.0},
        "weapons": [{"name": "Rifle", "range": 24.0, "attacks": 2, "count": 1, "ap": 0, "rules": []}]
    });
    let victim = json!({
        "unit_id": "victim", "name": "Victim", "quality": 4, "defense": 4,
        "tough": 1, "wounds_max": [1], "model_count": 1, "base_radius": 0.016,
        "game_system": "gf", "faction_folder": "machine_cults",
        "special_rules": [], "item_grants": [], "attached_hero_rules": [],
        "move_bands": {"advance": 6.0, "rush": 12.0},
        "weapons": [{"name": "Claws", "range": 0, "attacks": 1, "count": 1, "ap": 0, "rules": []}]
    });
    let list: Vec<Profile> = [shooter, victim]
        .iter()
        .map(|p| serde_json::from_value(p.clone()).unwrap())
        .collect();
    let mut index = HashMap::new();
    index.insert("shooter".to_string(), 0);
    index.insert("victim".to_string(), 1);
    Profiles { list, index }
}

/// 6x4 ft table, 3" school cells. `grid_size` = 30, so `half_grid` = 15: the origin is cell (15,15),
/// z=9"..12" is cell row 18. The RUINS wall spans x in [-9",12") (cells 12..=18), covering the whole
/// advance band (|x| <= 6").
fn terrain() -> Terrain {
    let cells: Vec<[f64; 3]> = (12..=18).map(|cx| [cx as f64, 18.0, RUINS as f64]).collect();
    Terrain::build(&PlainTerrain {
        cells,
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

fn state() -> State {
    let mut cache = ProfileCache::new(Rc::new(profiles()));
    let mut units = serde_json::Map::new();
    units.insert(
        "shooter".to_string(),
        json!({"player": 1, "alive": 1, "wounds": [1], "radii": [0.016],
            "positions": [[0.0, 0.0, 0.0]]}),
    );
    units.insert(
        "victim".to_string(),
        json!({"player": 2, "alive": 1, "wounds": [1], "radii": [0.016],
            "positions": [[0.0, 0.0, VICTIM_Z]]}),
    );
    let mut st = state_from_json(
        &json!({"round": 1, "rounds_total": 4, "units": units}).to_string(),
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

/// The widened grid rows (the hand rows sit first, `n_hand` of them).
fn grid_adv(p: &Pick) -> impl Iterator<Item = &Candidate> {
    p.cands[p.n_hand..].iter().filter(|c| c.kind == ADVANCE)
}

/// In range of the victim from this candidate's destination cell.
fn in_range(c: &Candidate) -> bool {
    c.dest.is_some_and(|d| {
        (d[0] * d[0] + (d[2] - VICTIM_Z) * (d[2] - VICTIM_Z)).sqrt() / IN2M <= 24.0
    })
}

/// F1 RED — the grid's moved-cell LOS probe must follow the hand's rule: with `shoot_los` OFF a
/// blocked moved shot is KEPT (like the hand twin, which never re-probes from the moved point);
/// with `shoot_los` ON the blocked row is DROPPED. On the base the probe is unconditional, so the
/// OFF case loses its row -> RED.
#[test]
fn grid_los_probe_follows_the_hand_rule() {
    let off = Knobs {
        grid_k: 64, grid_units: 1, menu_wide: true, moved_shoot: true, ..Knobs::default()
    };
    let got = run(off).expect("shoot_los off resolves");
    let shot = grid_adv(&got).filter(|c| c.shoot.is_some()).count();
    assert!(shot > 0, "shoot_los off: the blocked grid ADVANCE+shoot row was dropped (RED)");

    let on = Knobs { menu_los: true, ..off };
    let got = run(on).expect("shoot_los on resolves");
    let shot = grid_adv(&got).filter(|c| c.shoot.is_some()).count();
    assert_eq!(shot, 0, "shoot_los on: the blocked grid ADVANCE+shoot row survived");
}

/// F2 RED — with `menu_wide` off (`seams.moved_shoot` off) the grid must still emit the ADVANCE row
/// as a PLAIN advance (no shoot), exactly like `menu::advance_shoots` is off. On the base the row
/// carries a shoot, `resolve` declines the moved shot, and the row is DROPPED -> RED.
#[test]
fn grid_advance_survives_without_the_moved_shoot_seam() {
    let k = Knobs {
        grid_k: 64, grid_units: 1, menu_wide: false, moved_shoot: false, ..Knobs::default()
    };
    let got = run(k).expect("moved_shoot off resolves");
    assert!(grid_adv(&got).all(|c| c.shoot.is_none()),
        "moved_shoot off: a grid ADVANCE row still carries a shoot");
    assert!(grid_adv(&got).filter(|c| in_range(c)).count() > 0,
        "moved_shoot off: the in-range grid ADVANCE row was dropped (RED)");
}
