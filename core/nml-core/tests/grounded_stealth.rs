//! The Grounded Stealth port (D-STEALTH, decided 15.09.) — the Stealth
//! family's terrain-conditional alias reads the BOOK wording on the core:
//! a Grounded Stealth unit gets its -1 to be hit only when it actually
//! stands in/at terrain — per model within the entry's own
//! `terrain_within_in` (1") of ANY terrain (`terrain::base_in_terrain` with
//! the base radius widened by the proximity, class `terrain::is_any` — the
//! same per-model read Grounded Speed's verdict answers) — NOT the table's
//! majority-in-cover-CELL approximation, and not the unconditional alias
//! fold the core carried until now. The gate joins the shooting def build
//! (`ctx_live(ctx_of(..))`, sim.rs) and the melee def build; a record below
//! the bump keeps the old unconditional read byte-exact.
//!
//! The LIVE legs ride `CURRENT_RULES_EPOCH` (the position_parity_ladder
//! precedent), so the epoch bump itself flips this suite from RED to GREEN:
//! at the pre-bump epoch the alias still folds unconditionally and the
//! in-the-open leg fails. The below-bump leg is pinned by the FROZEN
//! constant of the epoch immediately below the bump (never a bare literal —
//! the #972 lesson); re-point it on rebase per the wave protocol.

use nml_core::acts::EPOCH_56_GROUNDED_PROTECTION;
use nml_core::dice::Tray;
use nml_core::io::{Action, Seams};
use nml_core::rng::GodotRng;
use nml_core::sim::{HOLD, resolve_stochastic_tray_on_board};
use nml_core::state::{ProfileCache, Profiles, State};
use nml_core::terrain::{CellParams, PlainTerrain, RUINS, Terrain};
use nml_core::unit::UnitStatic;
use nml_core::{CURRENT_RULES_EPOCH, IN2M, Registries};
use serde_json::json;
use std::rc::Rc;

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// One shooter (plain, one ranged weapon) against one Grounded Stealth
/// carrier — the carrier in the faction block whose mechanics entry fields
/// the name (gf machine_cults; aofs hidden_syndicates fields its twin).
fn profiles() -> Profiles {
    let victim = json!({
        "unit_id": "victim", "name": "Victim", "quality": 4, "defense": 4,
        "tough": 1, "wounds_max": [1], "model_count": 1, "base_radius": 0.016,
        "game_system": "gf", "faction_folder": "machine_cults",
        "special_rules": ["Grounded Stealth"],
        "item_grants": [], "attached_hero_rules": [],
        "move_bands": {"advance": 6.0, "rush": 12.0},
        "weapons": [{"name": "Claws", "range": 0, "attacks": 1, "count": 1, "ap": 0, "rules": []}]
    });
    let shooter = json!({
        "unit_id": "shooter", "name": "Shooter", "quality": 4, "defense": 4,
        "tough": 1, "wounds_max": [1], "model_count": 1, "base_radius": 0.016,
        "game_system": "gf", "faction_folder": "alien_hives",
        "special_rules": [], "item_grants": [], "attached_hero_rules": [],
        "move_bands": {"advance": 6.0, "rush": 12.0},
        "weapons": [{"name": "Rifle", "range": 24.0, "attacks": 2, "count": 1, "ap": 0, "rules": []}]
    });
    let list: Vec<nml_core::state::Profile> = [shooter, victim]
        .iter()
        .map(|p| serde_json::from_value(p.clone()).unwrap())
        .collect();
    let mut index = std::collections::HashMap::new();
    index.insert("shooter".to_string(), 0);
    index.insert("victim".to_string(), 1);
    Profiles { list, index }
}

/// The board: one RUINS cell on the table-centre cell (school cell (15, 15)
/// spans -1.5"..1.5" around the origin), so a model AT the origin stands in
/// terrain and a model 10" down the z axis is clear by 8.5".
fn terrain() -> Terrain {
    Terrain::build(&PlainTerrain {
        cells: vec![[15.0, 15.0, RUINS as f64]],
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

fn state_with_victim_at(x_in: f64) -> State {
    let mut cache = ProfileCache::new(Rc::new(profiles()));
    let mut units = serde_json::Map::new();
    units.insert(
        "shooter".to_string(),
        json!({"player": 1, "alive": 1, "wounds": [1], "radii": [0.016],
            "positions": [[0.0, 0.0, -12.0 * IN2M]]}),
    );
    units.insert(
        "victim".to_string(),
        json!({"player": 2, "alive": 1, "wounds": [1], "radii": [0.016],
            "positions": [[x_in * IN2M, 0.0, 0.0]]}),
    );
    nml_core::io::state_from_json(
        &json!({"round": 1, "rounds_total": 4, "units": units}).to_string(),
        &mut cache,
        &mut None,
    )
    .unwrap()
}

fn statics_at(epoch: u32) -> Vec<UnitStatic> {
    let mut reg = Registries::new(REPO);
    profiles()
        .list
        .iter()
        .map(|p| UnitStatic::build_for(&mut reg, p, epoch))
        .collect()
}

fn shoot_victim() -> Action {
    Action {
        teleport: None,
        kind: HOLD,
        unit: "shooter".into(),
        dest: None,
        shoot: Some("victim".into()),
        charge: None,
        patient: false,
        split: None,
        traced: None,
    }
}

fn resolve_at(epoch: u32, victim_x_in: f64) -> nml_core::dice::ShootResult {
    let state = state_with_victim_at(victim_x_in);
    let statics = statics_at(epoch);
    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let mut rng = GodotRng::new(1);
    let mut tray = Tray::seeded(27);
    resolve_stochastic_tray_on_board(
        &statics, &state, &shoot_victim(), &terrain(), seams, &mut rng, &mut tray,
    )
    .expect("hold + shoot resolves")
    .1
}

/// THE port: at the live epoch a Grounded Stealth carrier standing within 1"
/// of terrain keeps its -1 to be hit, and the SAME carrier in the open gets
/// NO -1 (the core read the alias unconditionally until now — the open leg
/// is RED before the fix; the terrain leg stays green through the port).
#[test]
fn grounded_stealth_gates_its_minus_one_on_the_terrain_at_the_live_epoch() {
    let in_terrain = resolve_at(CURRENT_RULES_EPOCH, 0.0);
    assert_eq!(
        in_terrain.rolls[0].target, 5,
        "within 1\" of terrain: Grounded Stealth's -1 to be hit (quality 4 -> 5+)"
    );
    let in_the_open = resolve_at(CURRENT_RULES_EPOCH, 10.0);
    assert_eq!(
        in_the_open.rolls[0].target, 4,
        "in the open: no -1 to hit (RED before the fix: the core read the alias unconditionally)"
    );
}

/// The old leg: below the bump the record predates the wave — the alias
/// folds unconditionally wherever the target stands, byte-exact. Pinned by
/// the FROZEN constant of the epoch immediately below the bump.
#[test]
fn below_the_bump_the_alias_folds_unconditionally_byte_exact() {
    let open = resolve_at(EPOCH_56_GROUNDED_PROTECTION, 10.0);
    assert_eq!(
        open.rolls[0].target, 5,
        "below the bump: the old unconditional alias read replays byte-exact"
    );
}