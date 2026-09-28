//! The Surprise Attack port (wave-5, epoch 7) — through the REAL registry and
//! the REAL resolve path: a single-model gf/alien_hives carrier of
//! "Surprise Attack(2)" activates (HOLD) with an enemy 5 cm away, in line of
//! sight. The burst rolls the rule's own rating at `trigger_target` 2 and each
//! success is one AP(1) hit. RED before the fix: the resolve runs, but nothing
//! rolls and no hit lands. The second test pins the Infiltrate-alias arm
//! (#761's table behaviour): the carrier's arrival ring is the Infiltrate 3",
//! not 0. The negatives pin the gates: below epoch 7 the alias arm stays off
//! (F1), the aofr entry's OWN 1" ring wins (D1, #761), a victim outside 6" is
//! never picked, and a round-2 activation never fires.

use std::io::Cursor;
use std::rc::Rc;

use nml_core::acts::read_acts;
use nml_core::io::{Action, Seams};
use nml_core::rng::GodotRng;
use nml_core::sim::{HOLD, resolve_stochastic_tray_on_board};
use nml_core::dice::Tray;

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

const CORPUS: &str = include_str!("fixtures/surprise_attack.jsonl");
const CORPUS_EPOCH6: &str = include_str!("fixtures/surprise_attack_epoch6.jsonl");
const CORPUS_AOFR: &str = include_str!("fixtures/surprise_attack_aofr.jsonl");
const CORPUS_FAR: &str = include_str!("fixtures/surprise_attack_far.jsonl");
const CORPUS_ROUND2: &str = include_str!("fixtures/surprise_attack_round2.jsonl");

fn hold() -> Action {
    Action {
        teleport: None,
        kind: HOLD,
        unit: "mover".into(),
        dest: None,
        shoot: None,
        charge: None,
        patient: false,
        split: None,
        traced: None,
    }
}

#[test]
fn surprise_attack_burst_fires_on_first_activation_at_epoch_7() {
    let corpus = read_acts(Cursor::new(CORPUS), "inline").unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    assert_eq!(corpus.acts.len(), 1, "one act");
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let act = &corpus.acts[0];
    assert!(Rc::ptr_eq(&act.state.profiles, &corpus.profiles));
    let seams = Seams { rules_epoch: 7, ..Default::default() };
    let mut rng = GodotRng::new(1);
    let mut tray = Tray::seeded(27);
    let (next, shot) = resolve_stochastic_tray_on_board(
        &statics, &act.state, &hold(), &corpus.terrain, seams, &mut rng, &mut tray,
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
    assert_eq!(
        ring, 3.0,
        "a Surprise Attack carrier is an Infiltrate-family arriver (#761), ring = {ring}"
    );
}

/// F1: the alias arm is gated on the FROZEN `EPOCH_7_TABLE_RULES` like every
/// other wave port — a record below 7 carrying "Surprise Attack" keeps ring
/// 0.0 and replays byte-exact.
#[test]
fn surprise_attack_alias_arm_is_epoch_gated() {
    let corpus =
        read_acts(Cursor::new(CORPUS_EPOCH6), "inline").unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let ring = statics[0].infiltrate_min_enemy_dist_in;
    assert_eq!(ring, 0.0, "below epoch 7 the alias arm stays off, ring = {ring}");
    assert!(
        statics[0].surprise_attack.is_none(),
        "below epoch 7 the burst stamp stays off too"
    );
}

/// D1 (#761): the table reads the alias entry's OWN `min_enemy_dist_in` via
/// `best_primitive_param` — aofr's Surprise Attack carries a 1" ring, so the
/// carrier's ring is 1.0, not the Infiltrate 3".
#[test]
fn aofr_surprise_attack_carries_its_own_ring() {
    let corpus =
        read_acts(Cursor::new(CORPUS_AOFR), "inline").unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let ring = statics[0].infiltrate_min_enemy_dist_in;
    assert_eq!(ring, 1.0, "the aofr entry's own 1\" ring wins (#761), ring = {ring}");
}

/// The 6" range gate is real: a victim outside 6" is not pickable — no roll,
/// no rules-must-log line, no hits.
#[test]
fn burst_ignores_a_victim_outside_the_rule_range() {
    let corpus =
        read_acts(Cursor::new(CORPUS_FAR), "inline").unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let seams = Seams { rules_epoch: 7, ..Default::default() };
    let mut rng = GodotRng::new(1);
    let mut tray = Tray::seeded(27);
    let (next, shot) = resolve_stochastic_tray_on_board(
        &statics, &corpus.acts[0].state, &hold(), &corpus.terrain, seams, &mut rng, &mut tray,
    )
    .expect("hold resolves");
    assert!(
        !shot.rolls.iter().any(|r| r.owner == "Mover" && r.target == 2 && r.count == 2),
        "no burst roll outside 6\""
    );
    assert!(
        !shot.log.iter().any(|l| l.contains("Surprise Attack")),
        "no rules-must-log line outside 6\""
    );
    assert_eq!(next.wounds[1][0], 2, "the untouched victim keeps both wounds");
}

/// The FIRST-ACTIVATION latch below the gate: a round-2 activation never
/// fires the burst (the old `round != 1` reading, unchanged below
/// `EPOCH_67_MARKERS_BURSTS`).
#[test]
fn burst_never_fires_on_a_later_round_activation() {
    let corpus = read_acts(Cursor::new(CORPUS_ROUND2), "inline")
        .unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let seams = Seams { rules_epoch: 7, ..Default::default() };
    let mut rng = GodotRng::new(1);
    let mut tray = Tray::seeded(27);
    let (next, shot) = resolve_stochastic_tray_on_board(
        &statics, &corpus.acts[0].state, &hold(), &corpus.terrain, seams, &mut rng, &mut tray,
    )
    .expect("hold resolves");
    assert!(
        !shot.rolls.iter().any(|r| r.owner == "Mover" && r.target == 2 && r.count == 2),
        "no burst roll on a round-2 activation"
    );
    assert!(
        !shot.log.iter().any(|l| l.contains("Surprise Attack")),
        "no rules-must-log line on a round-2 activation"
    );
    assert_eq!(next.wounds[1][0], 2, "the untouched victim keeps both wounds");
}

/// D19 (a), `EPOCH_67_MARKERS_BURSTS`: the SAME round-2 fixture is this
/// bearer's actual FIRST activation (`surprise_attack_used` absent from the
/// ledger, folds false) — an Infiltrate/Ambush arrival in round 2+ must fire
/// the burst, which the old `round != 1` gate could never reach. RED before
/// the fix: identical to `burst_never_fires_on_a_later_round_activation`
/// above — no burst, no log line, at ANY epoch.
#[test]
fn burst_fires_on_a_round2_first_activation_from_epoch_67() {
    let corpus = read_acts(Cursor::new(CORPUS_ROUND2), "inline")
        .unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let seams = Seams { rules_epoch: 67, ..Default::default() };
    let mut rng = GodotRng::new(1);
    let mut tray = Tray::seeded(27);
    let (next, shot) = resolve_stochastic_tray_on_board(
        &statics, &corpus.acts[0].state, &hold(), &corpus.terrain, seams, &mut rng, &mut tray,
    )
    .expect("hold resolves");
    let burst = shot
        .rolls
        .iter()
        .find(|r| r.owner == "Mover" && r.target == 2 && r.count == 2)
        .expect("a first activation in round 2 must still fire the burst from epoch 67");
    let hits = burst.faces.iter().filter(|&&f| f >= 2).count() as i64;
    assert!(shot.log.iter().any(|l| l.contains("Surprise Attack")));
    assert_eq!(next.wounds[1][0], 2 - hits);
    assert!(next.surprise_attack_used[0], "the latch burns on this, the bearer's first, activation");
}

/// D19 (a): a bearer whose latch is ALREADY spent (a prior activation, any
/// round) never fires again — the once-per-game half of the fix, proven
/// independently of the round-2 timing half above.
#[test]
fn a_spent_bearer_never_fires_again_from_epoch_67() {
    let corpus = read_acts(Cursor::new(CORPUS_ROUND2), "inline")
        .unwrap_or_else(|e| panic!("corpus parse failed: {e}"));
    let statics = nml_core::build_act_statics(&corpus, REPO);
    let mut spent_state = corpus.acts[0].state.clone();
    spent_state.surprise_attack_used[0] = true;
    let seams = Seams { rules_epoch: 67, ..Default::default() };
    let mut rng = GodotRng::new(1);
    let mut tray = Tray::seeded(27);
    let (next, shot) = resolve_stochastic_tray_on_board(
        &statics, &spent_state, &hold(), &corpus.terrain, seams, &mut rng, &mut tray,
    )
    .expect("hold resolves");
    assert!(!shot.rolls.iter().any(|r| r.owner == "Mover" && r.target == 2 && r.count == 2));
    assert!(!shot.log.iter().any(|l| l.contains("Surprise Attack")));
    assert_eq!(next.wounds[1][0], 2, "the untouched victim keeps both wounds");
}
