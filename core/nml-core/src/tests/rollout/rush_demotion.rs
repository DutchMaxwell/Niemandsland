use super::*;
use crate::sim::{ADVANCE, RUSH};

// ------------------------------------------------ #812 core half ---
//
// THE DEFECT (issue #812): the rollout policy menu offered a RUSH to the
// nearest objective even when the executable rush distance — after the p.11
// difficult cap (`mv::step`'s `reach = band.min(DIFFICULT_MOVE_CAP_IN)` when
// the route enters difficult ground) — is at or under the advance band. Rush
// forbids shooting (GF v3.5.1 p.7), so the shooter gave up its volley for zero
// extra inches, and self-play trained on the dominated move.
//
// THE FIXTURE. Player 1's shooter `p1_0_a` (Rifle, 24") stands AT the board
// centre with its base inside a FOREST patch (difficult ground, terrain.rs
// `is_difficult`); the nearest objective sits 8" east — inside the 12" rush
// band but outside the 6" advance band, so only the p.11 cap makes the rush
// dominated. Player 2's target `p2_0_x` stands 8" west: within the rifle's
// range + 6", exactly the issue's shape. Player 2's second unit parks 30 m
// off so it is never on the menu.
//
// TODAY (RED): the menu carries the RUSH candidate — the rollout can score it.
// AFTER (GREEN): the RUSH is demoted in place to an ADVANCE to the same
// objective carrying the shot (the W1 moved-shoot seam on), and an epoch-6
// record keeps today's menu byte-exact.

const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "p2_0_x":{"unit_id":"p2_0_x","name":"X","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "p2_1_y":{"unit_id":"p2_1_y","name":"Y","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

/// The same shooter, but a QUICK SHOT carrier (#782 rule — read by NAME
/// through the registry: the rule line plus the faction's own primitive
/// entry, exactly `UnitStatic::build_for`'s read). The table exempts these
/// (`solo_controller.gd:2239` `not quick_shot`): "may shoot after using Rush
/// actions" keeps the volley, so the rush is not dominated.
const QUICK_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"goblin_reclaimers","special_rules":["Quick Shot"],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "p2_0_x":{"unit_id":"p2_0_x","name":"X","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "p2_1_y":{"unit_id":"p2_1_y","name":"Y","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","objectives":[
  {"pos":[0.2032,0.0,0.0],"owner":1}],
  "units":{
  "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],
    "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
    "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
    "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
    "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
  "p2_0_x":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
    "positions":[[-0.2032,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
    "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
    "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
    "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
  "p2_1_y":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
    "positions":[[30.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
    "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
    "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
    "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

/// The shooter's rollout menu from player 1's seat, on a 6x4 board whose
/// FOREST patch covers x 0..9", z 0..3" around the board centre — the base of
/// the unit standing at [0,0,0] and the whole 8" line to the objective.
fn menu(epoch: u32) -> Vec<Candidate> {
    menu_h(HEADER, PLAIN, epoch)
}

/// The same menu over an arbitrary (header, board) fixture pair.
fn menu_h(header: &str, plain: &str, epoch: u32) -> Vec<Candidate> {
    let header = read_act_header(header).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let mut roster = None;
    let st = io::state_from_json(plain, &mut cache, &mut roster).expect("state");
    let statics = statics_of(&st, epoch);
    let terrain = Terrain::build(&crate::terrain::PlainTerrain {
        cells: vec![
            [15.0, 15.0, crate::terrain::FOREST as f64],
            [16.0, 15.0, crate::terrain::FOREST as f64],
            [17.0, 15.0, crate::terrain::FOREST as f64],
        ],
        sandbox: Vec::<crate::terrain::Obb>::new(),
        pieces: vec![],
        walls: vec![],
        cell_params: crate::terrain::CellParams {
            table_size_feet: [6.0, 4.0],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 3.0,
            inches_to_meters: crate::IN2M,
        },
    });
    let seams = Seams { rules_epoch: epoch, moved_shoot: true, ..Seams::default() };
    let policy = Policy::new(&statics, &terrain, seams);
    let mut sc = Scratch::default();
    let i = idx(&st, "p1_0_a");
    policy.policy_candidates(&st, i, &mut sc)
}

/// THE RED. The rush to the objective 8" east is capped to the 6" advance band
/// by the forest, so it never outranks advance + shoot: the menu must not
/// offer it, and the demoted advance to the same objective carries the shot.
#[test]
fn a_rush_capped_to_the_advance_band_is_demoted_to_an_advance_that_shoots() {
    let m = menu(CURRENT_RULES_EPOCH);
    assert!(
        !m.iter().any(|c| c.kind == RUSH),
        "no rush candidate may survive the p.11 cap at the advance band"
    );
    let demoted = m
        .iter()
        .find(|c| c.kind == ADVANCE && c.dest == Some([8.0 * crate::IN2M, 0.0, 0.0]))
        .expect("the demoted advance to the objective exists");
    assert_eq!(
        demoted.shoot.as_deref(),
        Some("p2_0_x"),
        "the demoted advance carries the shot the rush would have forfeited"
    );
}

/// The epoch gate. A record stamped below `EPOCH_7_TABLE_RULES` replays the
/// menu it was recorded under — rush candidate intact, byte-identical.
#[test]
fn an_epoch_6_record_keeps_the_rush_candidate() {
    let m = menu(6);
    assert!(
        m.iter().any(|c| c.kind == RUSH),
        "epoch 6 knows no demotion: today's menu, byte for byte"
    );
}

/// THE Quick Shot exemption (#782 rule, table `solo_controller.gd:2239`):
/// a carrier's rush keeps the volley ("may shoot after using Rush actions"),
/// so even a rush capped to the advance band stays on the menu.
#[test]
fn a_quick_shot_carrier_with_a_capped_rush_keeps_the_rush() {
    let m = menu_h(QUICK_HEADER, PLAIN, CURRENT_RULES_EPOCH);
    assert!(
        m.iter().any(|c| c.kind == RUSH),
        "the Quick Shot carrier's rush keeps the volley — no demotion"
    );
}

/// THE table's own shape (`solo_controller.gd:2243-2244`): with the target
/// out of range after the capped move (36\" — 6\" cap > 24\" rifle), the rush
/// forfeits no shot — the RUSH stays, exactly like the table keeps it.
#[test]
fn a_capped_rush_without_a_target_in_range_keeps_the_rush() {
    let far = PLAIN.replace("[[-0.2032,0.0,0.0]]", "[[-0.9144,0.0,0.0]]");
    let m = menu_h(HEADER, &far, CURRENT_RULES_EPOCH);
    assert!(
        m.iter().any(|c| c.kind == RUSH),
        "a capped rush with no shot keeps RUSH, like the table"
    );
}
