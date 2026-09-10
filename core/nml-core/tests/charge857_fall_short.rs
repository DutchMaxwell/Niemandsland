//! #857 — a charge the TABLE resolves as "fell short" (no engage ring, no dice)
//! must land on the table's approach vector. The fixture is the worst measured
//! act of the epoch-8 reference (`blood_brothers_2000_vs_change_disciples_2000_s31`,
//! act 46, "Change Brothers", charge band 12"): the table's recorded landing is
//! (19.44, 9.52)" while main 87d50d54's port landed (27.7, -0.3)" — 12.84" away
//! on a different vector, same dice either way (the act is both_silent). The
//! header + the act's pre-act state + the pick are committed verbatim in
//! `fixtures/charge857_fall_short.json` (50 548 bytes), so this runs without the
//! corpus; the tray is seeded with the game's `dice_seed` and burned to the act
//! like every replay gate does.
use nml_core::{
    act_statics, acts::{read_acts, Sighting, EPOCH_8_PLANNER_MENU},
    dice::Tray,
    io::{Action, Seams},
    rng::GodotRng,
    sim::resolve_stochastic_tray_on_board,
    state::State,
};
use serde_json::Value;
use std::io::Cursor;

const FIXTURE: &str = include_str!("fixtures/charge857_fall_short.json");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// Replays the fixture act at `epoch` and returns (next state, charger key,
/// number of rolls the tray consumed). Knobs mirror `dice_gate --movement
/// table`: the header's own vintage plus the instrument's overrides.
fn replay(epoch: u32) -> (State, String, usize) {
    let fx: Value = serde_json::from_str(FIXTURE).unwrap();
    let mut text = String::new();
    text.push_str(&fx["header"].to_string());
    text.push('\n');
    text.push_str(&fx["act_line"].to_string());
    text.push('\n');
    let corpus = read_acts(Cursor::new(text), "fixture").unwrap();
    let acts = act_statics(&corpus, REPO);
    let act = &corpus.acts[0];
    let action: Action = serde_json::from_value(fx["act_line"]["pick"]["action"].clone()).unwrap();
    let seams = Seams {
        spacing: corpus.knobs.seam_spacing,
        hero_attach: true,
        charge_landing: true,
        sighting: corpus.knobs.sighting == Sighting::Model,
        movement: true,
        cond_ap_dice: true,
        rules_epoch: epoch,
        ..Seams::default()
    };
    let mut tray = Tray::seeded(fx["dice_seed"].as_i64().unwrap());
    let burn = fx["burn"].as_u64().unwrap() as usize;
    if burn > 0 {
        tray.roll(burn);
    }
    let mut rng = GodotRng::new(0);
    let (next, shot) = resolve_stochastic_tray_on_board(
        &acts[0], &act.state, &action, &corpus.terrain, seams, &mut rng, &mut tray,
    )
    .unwrap_or_else(|e| panic!("act declined: {e:?}"));
    (next, action.unit, shot.rolls.len())
}

/// The charger's next-act centroid, inches — the recorded landings' own unit
/// (the research's `tab_c`/`port_c` charger rows).
fn centroid_in(state: &State, unit: &str) -> [f64; 2] {
    let si = state.roster.index[unit];
    let ps = &state.positions[si];
    let n = ps.len() as f64;
    [
        ps.iter().map(|p| p[0]).sum::<f64>() / n / nml_core::IN2M,
        ps.iter().map(|p| p[2]).sum::<f64>() / n / nml_core::IN2M,
    ]
}

fn fixture() -> Value {
    serde_json::from_str(FIXTURE).unwrap()
}

#[test]
fn the_tables_fell_short_charge_lands_on_the_tables_vector() {
    let (next, unit, rolls) = replay(EPOCH_8_PLANNER_MENU);
    assert!(
        rolls == 0,
        "#857 fixture act is both_silent — the port must consume no dice: {rolls} rolls"
    );
    let fx = fixture();
    let want = fx["expected_landing_in"].as_array().unwrap();
    let (want_x, want_z) = (want[0].as_f64().unwrap(), want[1].as_f64().unwrap());
    let got = centroid_in(&next, &unit);
    let gap = f64::hypot(got[0] - want_x, got[1] - want_z);
    assert!(
        gap <= fx["tolerance_in"].as_f64().unwrap(),
        "error: #857 RED — recorded landing ({want_x:.2}, {want_z:.2})\" — port landed ({:.2}, {:.2})\" = {gap:.2}\" away",
        got[0], got[1]
    );
}

/// The freeze pin: the fix rides `EPOCH_8_PLANNER_MENU`, so an epoch-7 record
/// must replay the landing byte-identically to the pre-fix port. The pin is the
/// pre-fix epoch-7 landing measured by this same test before the fix.
#[test]
fn epoch_7_replays_the_charge_landing_byte_identically() {
    let (next, unit, _) = replay(7);
    let got = centroid_in(&next, &unit);
    let fx = fixture();
    let pin = fx["epoch7_landing_in"].as_array();
    let Some(pin) = pin else {
        panic!(
            "error: #857 PIN — epoch-7 pin not written yet; the pre-fix landing measured here: ({:.4}, {:.4})\"",
            got[0], got[1]
        );
    };
    let (want_x, want_z) = (pin[0].as_f64().unwrap(), pin[1].as_f64().unwrap());
    let gap = f64::hypot(got[0] - want_x, got[1] - want_z);
    assert!(
        gap <= 0.005,
        "epoch-7 landing moved — the gate must stay behind EPOCH_8_PLANNER_MENU: \
         pinned ({want_x:.4}, {want_z:.4})\" — got ({:.4}, {:.4})\"",
        got[0], got[1]
    );
}
