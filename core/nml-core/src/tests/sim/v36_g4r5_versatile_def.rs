//! Rules 3.6 row G4R5 R12 F-VERSATILE-DEF (replay row aof_1000_net_010 act 32): the Versatile Attack pick is made by an
//! EV chooser that reads the target's Defense. The table hands it the Defense AFTER the over-9" Guarded/Sturdy fold
//! (`shot_base`); the core handed it the Defense BEFORE the fold (the fold came later, in the dice), so against a
//! Defense-4 Sturdy target over 9" a Quality-5 Bane shooter picked "+1 to hit" where the table picks "AP(+1)".
//! From `EPOCH_73_V36` the chooser sees the folded Defense, in both halves (the volley and the charge); below 73 the old
//! input replays. Units are built the way the game builds them (real profiles through `UnitStatic::build_for`).
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::read_act_header;
use crate::rules::Registries;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// A City Guard (Quality 5, Versatile Attack, Bane rifle and Bane fists) and two Defense-4 targets: Hammer Elites (Sturdy,
/// the Guarded fold over 9") and plain Elites (no rule).
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "guard":{"unit_id":"guard","name":"City Guard","quality":5,"defense":4,"tough":1,"wounds_max":[1],
    "model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"aof","faction_folder":"human_empire",
    "special_rules":["Versatile Attack"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":12,"count":1,"ap":0,"rules":["Bane"]},
      {"name":"Fists","range":0,"attacks":12,"count":1,"ap":0,"rules":["Bane"]}]},
  "sturdy":{"unit_id":"sturdy","name":"Hammer Elites","quality":4,"defense":4,"tough":1,"wounds_max":[400],
    "model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"aof","faction_folder":"human_empire",
    "special_rules":["Sturdy"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Club","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "plain":{"unit_id":"plain","name":"Plain Elites","quality":4,"defense":4,"tough":1,"wounds_max":[400],
    "model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"aof","faction_folder":"human_empire",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Club","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

/// Unit 0 = the City Guard, unit 2 = the target `key`, `gap_in` apart edge to edge (both on 1" bases), built at `epoch`.
fn line(key: &str, gap_in: f64, epoch: u32) -> (State, Vec<UnitStatic>) {
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = Registries::new(&repo_root());
    let mut build = |k: &str| UnitStatic::build_for(&mut reg, header.profiles.get(k).expect(k), epoch);
    let (guard, target) = (build("guard"), build(key));
    assert!(guard.shoot[0].versatile_attack, "the Rifle carries Versatile Attack: {:?}", guard.shoot[0].name);
    assert!(guard.melee[0].versatile_attack, "the Fists carry Versatile Attack");
    assert_eq!(target.ctx.guarded, key == "sturdy", "{key}: Sturdy is the Guarded fold, nothing else is");
    let (mut st, mut statics) = buff_line();
    statics[0] = UnitStatic { model_count: 1, wounds_max: vec![1], ..guard };
    statics[2] = UnitStatic { model_count: 1, wounds_max: vec![400], ..target };
    (st.alive[0], st.alive[2]) = (1, 1);
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.positions[2] = vec![[(gap_in + 2.0) * IN2M, 0.0, 0.0]];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M], vec![IN2M], vec![]]);
    (st.wounds[0], st.wounds[2]) = (vec![1], vec![400]);
    (st, statics)
}

/// The activation's Versatile pick line ("<rule>: City Guard picks <mode> for this activation") through one HOLD volley
/// (`volley`) or one charge from `gap_in` away, at a target `gap_in` away.
fn pick(volley: bool, key: &str, gap_in: f64, epoch: u32) -> String {
    let (mut st, statics) = line(key, gap_in, epoch);
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let shot = if volley {
        let terrain = crate::terrain::Terrain::default();
        resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &terrain, seams,
            &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(3)).unwrap().1
    } else {
        // The charge lands in base contact; `charge_from_in` is the distance it started from.
        st.positions[2] = vec![[2.0 * IN2M, 0.0, 0.0]];
        let (mut tray, mut shot) = (Tray::seeded(3), ShootResult::default());
        tray_charge(&statics, &mut st, 0, 2, seams, &mut tray, &mut shot, gap_in, Cover::Recorded(None));
        shot
    };
    shot.log.iter().find(|l| l.contains("picks")).cloned().unwrap_or_else(|| format!("no pick line: {:?}", shot.log))
}

fn folded_pick_is_ap(volley: bool) {
    let line = pick(volley, "sturdy", 12.0, EPOCH_73_V36);
    assert!(line.contains("City Guard picks AP(+1)"), "volley={volley}: {line}");
    assert!(line.starts_with("Versatile Attack:"), "volley={volley}: the line names the book rule: {line}");
}

/// RED on main, the volley half: Defense 4 Sturdy from over 9" folds to 3, where the Quality-5 Bane City Guard's two modes
/// tie and the tie goes to AP(+1) (the table's pick). The core's chooser saw the unfolded 4 and picked "+1 to hit".
#[test]
fn the_volley_pick_sees_the_defense_after_the_over_9_inch_sturdy_fold_at_epoch_73() {
    folded_pick_is_ap(true);
}

/// RED on main, the charge half: the same fold for a charge from over the gate.
#[test]
fn the_charge_pick_sees_the_defense_after_the_over_gate_sturdy_fold_at_epoch_73() {
    folded_pick_is_ap(false);
}

/// CONTROL (passes before and after): inside the gate the attack is no eligible attack (Versatile needs a shot from over
/// 9" or a charge from over 6"), so there is no pick to fold a Defense into.
#[test]
fn within_the_gate_the_attack_is_no_eligible_attack_and_there_is_no_pick() {
    for volley in [true, false] {
        let line = pick(volley, "sturdy", 5.0, EPOCH_73_V36);
        assert!(line.starts_with("no pick line"), "volley={volley}: {line}");
    }
}

/// CONTROL (passes before and after): a target without Sturdy has nothing to fold, from any distance.
#[test]
fn a_target_without_sturdy_keeps_its_defense_over_9_inches() {
    for volley in [true, false] {
        let line = pick(volley, "plain", 12.0, EPOCH_73_V36);
        assert!(line.contains("City Guard picks +1 to hit"), "volley={volley}: {line}");
    }
}

/// Below 73 the old input replays: the chooser sees the unfolded Defense 4 and picks "+1 to hit".
#[test]
fn below_epoch_73_the_pick_still_sees_the_unfolded_defense() {
    for volley in [true, false] {
        let line = pick(volley, "sturdy", 12.0, EPOCH_72_PLAYTEST_RULES);
        assert!(line.contains("City Guard picks +1 to hit"), "volley={volley}: {line}");
    }
}
