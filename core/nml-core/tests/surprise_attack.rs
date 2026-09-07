//! The Surprise Attack port (wave-5, epoch 7) — through the REAL registry and
//! the REAL resolve path: a single-model gf/alien_hives carrier of
//! "Surprise Attack(2)" activates (HOLD) with an enemy 5 cm away, in line of
//! sight. The burst rolls the rule's own rating at `trigger_target` 2 and each
//! success is one AP(1) hit. RED before the fix: the resolve runs, but nothing
//! rolls and no hit lands. The second test pins the Infiltrate-alias arm
//! (#761's table behaviour): the carrier's arrival ring is the Infiltrate 3",
//! not 0.

use std::io::Cursor;
use std::rc::Rc;

use nml_core::acts::read_acts;
use nml_core::io::{Action, Seams};
use nml_core::rng::GodotRng;
use nml_core::sim::{HOLD, resolve_stochastic_tray_on_board};
use nml_core::dice::Tray;

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

const CORPUS: &str = include_str!("fixtures/surprise_attack.jsonl");

#[test]
fn surprise_attack_burst_fires_on_first_activation_at_epoch_7() {
    let corpus = read_acts(Cursor::new(CORPUS), "inline").unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    assert_eq!(corpus.acts.len(), 1, "one act");
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let act = &corpus.acts[0];
    assert!(Rc::ptr_eq(&act.state.profiles, &corpus.profiles));
    let action = Action {
        kind: HOLD,
        unit: "mover".into(),
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
    let (next, shot) = resolve_stochastic_tray_on_board(
        &statics, &act.state, &action, &corpus.terrain, seams, &mut rng, &mut tray,
    )
    .expect("hold resolves");
    let burst = shot
        .rolls
        .iter()
        .find(|r| r.owner == "Mover" && r.target == 2 && r.count == 2)
        .expect("the Surprise Attack burst is on the tray");
    let hits = burst.faces.iter().filter(|&&f| f >= 2).count() as i64;
    assert!(
        shot.log.iter().any(|l| l.contains("Surprise Attack")),
        "rules-must-log: the roll names the rule"
    );
    assert_eq!(
        next.wounds[1][0],
        2 - hits,
        "each 2+ is one AP(1) hit on the picked enemy"
    );
}

#[test]
fn surprise_attack_carrier_counts_as_infiltrate_for_the_arrival_ring() {
    let corpus = read_acts(Cursor::new(CORPUS), "inline").unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let ring = statics[0].infiltrate_min_enemy_dist_in;
    assert!(
        ring > 0.0,
        "a Surprise Attack carrier is an Infiltrate-family arriver (#761), ring = {ring}"
    );
}
