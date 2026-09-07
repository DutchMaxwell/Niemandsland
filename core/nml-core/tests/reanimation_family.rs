//! The Reanimation port (wave-4 follow-up, epoch 7) — through the REAL
//! registry and the REAL resolve path: a gf/robot_legions carrier (the base
//! rule arrives via the "Reanimation Aura" upgrade; the import/epoch-6 fold
//! puts the base name on the profile) activates at 1 of 3 wounds and rolls
//! its missing wounds at the entry's own restore_target (5) BEFORE the
//! action. Deterministic: the tray is seeded, so the exact heal count is
//! computable from the recorded roll. RED before the fix: the activation
//! resolves, nothing rolls, the wound stays missing.

use std::io::Cursor;

use nml_core::acts::read_acts;
use nml_core::dice::Tray;
use nml_core::io::{Action, Seams};
use nml_core::rng::GodotRng;
use nml_core::sim::resolve_stochastic_tray_on_board;

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn corpus(epoch: u32) -> String {
    let hdr = r#"{"kind":"header","knobs":{"rules_epoch":__E__},"profiles":{"rean":{"unit_id":"rean","name":"Rean","quality":4,"defense":4,"tough":1,"wounds_max":[3],"model_count":1,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":["Reanimation"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;
    let act = r#"{"round":1,"player":1,"pool":["rean"],"state":{"round":1,"rounds_total":4,"scoring":"end","objectives":[],"units":{"rean":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],"positions":[[0.0,0.0,0.0]]}}}}"#;
    hdr.replace("__E__", &epoch.to_string()) + "\n" + act + "\n"
}

fn run(epoch: u32) -> (nml_core::State, nml_core::dice::ShootResult) {
    let corpus = read_acts(Cursor::new(corpus(epoch)), "inline")
        .unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let act = &corpus.acts[0];
    let action = Action {
        kind: nml_core::sim::HOLD,
        unit: "rean".into(),
        dest: None,
        shoot: None,
        charge: None,
        patient: false,
        split: None,
        traced: None,
    };
    let seams = Seams { rules_epoch: 7, ..Default::default() };
    let mut rng = GodotRng::new(1);
    let mut tray = Tray::seeded(27);
    resolve_stochastic_tray_on_board(
        &statics, &act.state, &action, &corpus.terrain, seams, &mut rng, &mut tray,
    )
    .expect("HOLD resolves")
}

#[test]
fn reanimation_rolls_its_missing_wounds_at_activation_at_epoch_7() {
    let (next, shot) = run(7);
    let roll = shot
        .rolls
        .iter()
        .find(|r| r.owner == "Rean" && r.target == 5)
        .expect("the Reanimation roll is on the tray (RED before the fix)");
    let healed = roll.faces.iter().filter(|&&f| f >= 5).count() as i64;
    assert!(
        shot.log.iter().any(|l| l.contains("Reanimation")),
        "rules-must-log: the roll names the rule"
    );
    assert_eq!(next.wounds[0][0], 1 + healed, "each 5+ restores one wound");
}

#[test]
fn an_epoch_six_record_sees_no_reanimation_roll() {
    let (_, shot) = run(6);
    assert!(
        !shot.rolls.iter().any(|r| r.target == 5),
        "epoch 6: granted, not read (byte-exact)"
    );
    assert!(!shot.log.iter().any(|l| l.contains("Reanimation")));
}
