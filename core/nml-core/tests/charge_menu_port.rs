//! G4-C2 (c): the menu confirms its charge picks with the core's own move port from rules epoch 73.
//! Fixture: the #857 act (charger "Change Brothers" and its victim, 10.2" apart, charge band 12") — the charge the TABLE
//! re-gates to a Rush because the formation ends short of the engage ring. The menu's cheap path check offers it; the
//! move port (`charge_reaches_contact`, the table's declaration probe) does not execute it, so the menu must not offer it.
use nml_core::{
    act_statics,
    acts::{read_acts, EPOCH_73_V36},
    menu::{candidates_tuned, Tuning},
    sim::Scratch,
    terrain::Terrain,
};
use serde_json::{json, Value};
use std::io::Cursor;

const FIXTURE: &str = include_str!("fixtures/charge857_fall_short.json");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// Does the menu of the fixture act's charger carry the recorded charge, at the header's `rules_epoch`, with or without
/// the recorded board?
fn menu_offers_the_charge(rules_epoch: u32, board: bool) -> bool {
    let fx: Value = serde_json::from_str(FIXTURE).unwrap();
    let mut header = fx["header"].clone();
    // The recorded ruin walls go: this file pins the port's verdict alone (the walled case lives in charge_path.rs).
    header["terrain"]["walls"] = json!([]);
    header["knobs"]["rules_epoch"] = json!(rules_epoch);
    let text = format!("{}\n{}\n", header, fx["act_line"]);
    let corpus = read_acts(Cursor::new(text), "fixture").unwrap();
    let acts = act_statics(&corpus, REPO);
    let state = &corpus.acts[0].state;
    let charger = state.roster.index[fx["act_line"]["pick"]["action"]["unit"].as_str().unwrap()];
    let victim = fx["act_line"]["pick"]["action"]["charge"].as_str().unwrap();
    let terrain = if board { corpus.terrain.clone() } else { Terrain::absent() };
    let mut sc = Scratch::default();
    let menu = candidates_tuned(state, &terrain, acts[0].as_slice(), charger, &mut sc, Tuning::default());
    menu.iter().any(|c| c.charge.as_deref() == Some(victim))
}

#[test]
fn a_charge_the_move_port_ends_short_on_leaves_the_menu_from_rules_3_6_on() {
    assert!(!menu_offers_the_charge(EPOCH_73_V36, true), "the port ends short of the engage ring: no charge row");
}

#[test]
fn below_rules_3_6_the_menu_keeps_the_charge() {
    assert!(menu_offers_the_charge(EPOCH_73_V36 - 1, true), "the confirmation is a 3.6 rule: epoch 72 is byte-identical");
}

#[test]
fn without_a_board_the_port_has_no_opinion() {
    assert!(menu_offers_the_charge(EPOCH_73_V36, false), "no board, no landing to judge: the pick stands");
}
