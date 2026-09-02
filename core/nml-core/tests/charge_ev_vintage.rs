//! The CORPUS-VINTAGE reading of `Knobs::engage_fold` (NML-1158b, found by
//! `policy_gate.py`): a header WITHOUT the `engage_fold` key was recorded before
//! the attached-hero fold existed (NML-1129/1132), so the twin must replay it
//! with the fold's ENGAGE and WEAPON halves OFF — exactly what
//! `BattleSim.engage_fold_vintage` pins for the GDScript replay and what the
//! Python gates' `vintage_knobs()` resolve. The twin used to default the absent
//! key to ON and folded the charger's attached hero's melee weapon into a
//! CHARGE candidate's expected wounds the table never counted.
//!
//! `tests/fixtures/acts_charge_ev_vintage.jsonl` is the header (no `engage_fold`,
//! `hero_attach` true) plus ONE act of `qbg_ref`
//! `blessed_sisters_1000_vs_blood_brothers_1000_s27` (act 22, round 3 player 1):
//! prefilter row idx 5 is a CHARGE by a 2-model host carrying a joined hero
//! whose only weapon ("Dual Shock Whip", Blast(3)) the host does not have.
//! The TABLE scored that row 0.5540962949413654 with the host's Mace alone.

use nml_core::plan::{PlanBend, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, load_acts, ActCorpus, Seams};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_charge_ev_vintage.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const EPS: f64 = 1e-9;
/// The charging host's build-order index in the recorded prefilter.
const CHARGE_IDX: i64 = 5;

fn seams_of(c: &ActCorpus, no_engage_fold: bool) -> Seams {
    Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement, move_rigid: c.knobs.move_rigid, no_dangerous: false, no_engage_fold, los_model: c.knobs.los_model }
}

/// Every prefilter row's 1-ply score under `seams`, keyed by build idx.
fn scored_under(c: &ActCorpus, seams: Seams) -> Vec<(i64, f64)> {
    let statics = build_act_statics(c, REPO);
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let act = &c.acts[0];
    let mut search = Search::new(roll, &act.statics);
    search.bend = PlanBend::default();
    let mut sc = Scratch::default();
    let got = search.run(&act.state, act.player, &mut sc, None).unwrap_or_else(|u| panic!("declined: {u:?}"));
    got.scored.iter().map(|r| (r.0, r.3)).collect()
}

#[test]
fn an_absent_engage_fold_key_reads_off_and_the_charge_row_scores_like_the_table() {
    let c = load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"));
    assert_eq!(c.acts.len(), 1);
    assert!(c.knobs.hero_attach, "the fixture's pool/move/spend fold is on");
    assert!(!c.knobs.engage_fold, "an absent engage_fold key is the pre-fold vintage: OFF");
    let act = &c.acts[0];
    let got = scored_under(&c, seams_of(&c, !c.knobs.engage_fold));
    assert_eq!(got.len(), act.scored.len(), "prefilter row count");
    let mut worst = 0.0f64;
    for (g, w) in got.iter().zip(&act.scored) {
        assert_eq!(g.0, w.idx, "prefilter order");
        worst = worst.max((g.1 - w.score).abs());
    }
    let row = got.iter().find(|r| r.0 == CHARGE_IDX).unwrap();
    let want = act.scored.iter().find(|r| r.idx == CHARGE_IDX).unwrap();
    println!(
        "VINTAGE charge row idx {CHARGE_IDX}: twin {:.17} vs table {:.17}; worst row |diff| {worst:.3e} over {} rows",
        row.1, want.score, got.len()
    );
    assert_eq!(want.kind, 3, "row {CHARGE_IDX} is the recorded CHARGE");
    assert!(worst <= EPS, "a prefilter row parted from the table by {worst:.3e}");
}

/// RED: force the fold ON for this pre-fold corpus (the old default) and the
/// charge row must move — the hero's whip joins the charger's strike phase.
#[test]
fn red_the_old_fold_on_default_moves_the_charge_row() {
    let c = load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"));
    let act = &c.acts[0];
    let got = scored_under(&c, seams_of(&c, false));
    let row = got.iter().find(|r| r.0 == CHARGE_IDX).unwrap();
    let want = act.scored.iter().find(|r| r.idx == CHARGE_IDX).unwrap();
    let diff = (row.1 - want.score).abs();
    println!("RED fold forced ON: charge row idx {CHARGE_IDX} twin {:.17} vs table {:.17}, |diff| {diff:.3e}", row.1, want.score);
    assert!(diff > EPS, "folding the hero's weapon into a pre-fold corpus changed nothing");
}
