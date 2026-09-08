//! The Crossing Attack port (wave-4 follow-up, epoch 7) — one test, through
//! the REAL registry and the REAL resolve path (`resolve_stochastic_tray_on_board`):
//! a single-model gf/machine_cults carrier of "Crossing Attack(2)" ADVANCEs
//! straight through an enemy model's base; the tray rolls the rule's own
//! rating at `wound_target` 6 and lands the wounds DIRECTLY (no save). The
//! seed and the geometry are deterministic, so the exact wound count is
//! computable from the recorded roll. RED before the fix: the resolve runs,
//! but nothing rolls and no wound lands.

use std::io::Cursor;
use std::rc::Rc;

use nml_core::acts::read_acts;
use nml_core::io::{Action, Seams};
use nml_core::rng::GodotRng;
use nml_core::sim::{ADVANCE, resolve_stochastic_tray_on_board};
use nml_core::dice::Tray;

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// Two-unit act: "mover" (player 1, the Crossing Attack(2) carrier) starts at
/// the origin, "victim" (player 2) sits 5 cm down the x axis — inside the
/// 6-inch advance band, well inside the swept corridor of a 1.6 cm base.
const CORPUS: &str = include_str!("fixtures/crossing_attack.jsonl");

#[test]
fn crossing_attack_rolls_through_crossed_enemies_at_epoch_7() {
    let corpus = read_acts(Cursor::new(CORPUS), "inline").unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    assert_eq!(corpus.acts.len(), 1, "one act");
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let act = &corpus.acts[0];
    // The profiles table the act replays on IS the header table (no dynamic
    // read), so the shared statics closure is the right one.
    assert!(Rc::ptr_eq(&act.state.profiles, &corpus.profiles));
    let action = Action {
        kind: ADVANCE,
        unit: "mover".into(),
        dest: Some([1.0, 0.0, 0.0]),
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
    .expect("advance resolves");
    let mover_moved = (next.positions[0][0][0] - act.state.positions[0][0][0]).abs() > 0.01;
    assert!(mover_moved, "the advance moved the carrier");
    let crossing = shot
        .rolls
        .iter()
        .find(|r| r.owner == "Mover" && r.target == 6)
        .expect("the Crossing Attack roll is on the tray");
    let wounds = crossing.faces.iter().filter(|&&f| f >= 6).count() as i64;
    assert!(
        wounds >= 1,
        "the fixture must actually roll a 6 of {} dice: {:#?}",
        crossing.faces.len(),
        crossing.faces
    );
    assert!(
        shot.log.iter().any(|l| l.contains("Crossing Attack")),
        "rules-must-log: the roll names the rule"
    );
    assert!(
        next.wounds[1][0] < 2,
        "a 6 was rolled, so a direct wound IS landed — a roll-but-never-land impl falls: {:#?}",
        next.wounds
    );
    assert_eq!(
        next.wounds[1][0],
        2 - wounds,
        "each 6+ is one direct wound on the crossed enemy"
    );
}
