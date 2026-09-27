//! D16: Mind Control and Fatigue Debuff use the target's morale rules at epoch 65.

use std::io::Cursor;

use nml_core::acts::{read_acts, EPOCH_64_DEPLOY_LARGE_RESPOT, EPOCH_65_MELEE_TRUTH};
use nml_core::dice::Tray;
use nml_core::io::{Action, Seams};
use nml_core::rng::GodotRng;
use nml_core::sim::{resolve_stochastic_tray_on_board, HOLD};

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const LINE: &str = include_str!("fixtures/surprise_attack.jsonl");

fn run(rule: &str, faction: &str, target_rule: &str, shaken: bool, bonus: i64, epoch: u32, seed: i64)
    -> (nml_core::state::State, nml_core::dice::ShootResult) {
    let source = LINE
        .replace("alien_hives", faction)
        .replace("Surprise Attack(2)", rule)
        .replace("\"faction_folder\":\"machine_cults\",\"special_rules\":[]",
                 &format!("\"faction_folder\":\"machine_cults\",\"special_rules\":[{target_rule}]"));
    let corpus = read_acts(Cursor::new(source), "inline").unwrap();
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let mut state = corpus.acts[0].state.clone();
    state.shaken[1] = shaken;
    state.morale_bonus[1] = bonus;
    let action = Action { kind: HOLD, unit: "mover".into(), dest: None, shoot: None, charge: None,
        teleport: None, patient: false, split: None, traced: None };
    let mut tray = Tray::seeded(seed);
    let mut rng = GodotRng::new(1);
    resolve_stochastic_tray_on_board(&statics, &state, &action, &corpus.terrain,
        Seams { rules_epoch: epoch, ..Default::default() }, &mut rng, &mut tray).unwrap()
}

#[test]
fn shaken_target_auto_fails_mind_control_without_a_die() {
    let (next, shot) = run("Mind Control", "jackals", "", true, 0, EPOCH_65_MELEE_TRUTH, 3);
    assert!(shot.rolls.iter().all(|r| r.owner != "Mover"), "Shaken draws no morale die");
    assert!(next.positions[1][0][0] > 0.05, "failed test moves the target");
    let (_, old) = run("Mind Control", "jackals", "", true, 0, EPOCH_64_DEPLOY_LARGE_RESPOT, 3);
    assert!(old.rolls.iter().any(|r| r.owner == "Mover"), "old records keep the bare roll");
}

#[test]
fn failed_mind_control_shakes_the_target_before_moving_it() {
    let (next, shot) = run("Mind Control", "jackals", "", false, 0, EPOCH_65_MELEE_TRUTH, 3);
    assert_eq!(shot.rolls[0].target, 4);
    assert!(shot.rolls[0].faces[0] < 4);
    assert!(next.shaken[1]);
    assert!(next.positions[1][0][0] > 0.05);
    let (old, _) = run("Mind Control", "jackals", "", false, 0, EPOCH_64_DEPLOY_LARGE_RESPOT, 3);
    assert!(!old.shaken[1]);
}

#[test]
fn fearless_target_gets_a_recovery_die_and_bonus_changes_the_target() {
    let (_, shot) = run("Mind Control", "jackals", "\"Fearless\"", false, 0, EPOCH_65_MELEE_TRUTH, 3);
    assert_eq!(shot.rolls.iter().filter(|r| r.owner == "Mover").count(), 2);
    assert_eq!(shot.rolls[1].target, 4);
    let (_, bonus) = run("Mind Control", "jackals", "", false, 1, EPOCH_65_MELEE_TRUTH, 3);
    assert_eq!(bonus.rolls[0].target, 3, "Banner lowers the shared morale target");
}

#[test]
fn fatigue_debuff_also_shakes_then_fatigues() {
    let (next, shot) = run("Fatigue Debuff", "wormhole_daemons_of_war", "", false, 0, EPOCH_65_MELEE_TRUTH, 3);
    assert_eq!(shot.rolls[0].target, 4);
    assert!(next.shaken[1]);
    assert!(next.fatigued[1]);
}
