//! Rules 3.6 lane ux tests for the deployment module; owned by lane ux.

// ---- UX-12 (`EPOCH_73_V36`): the Scout band — how far ahead of its own zone a Scout unit sets
// up — is 9" from the rules 3.6 epoch on and stays 12" below it. One scout alone on an empty
// board with the only objective at the table centre: it runs as far forward as its band allows.

use super::empty_board;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::deployment::{deploy_side, Rect, UnitSpec};

/// Side 1's 12"-deep zone along the -Z table edge; its forward edge is y = -0.3048.
fn scout_zone() -> Rect {
    Rect::new(-0.9144, -0.6096, 1.8288, 0.3048)
}

/// The line 9" ahead of the zone's forward edge.
const NINE_INCH_LINE: f64 = -0.3048 + 9.0 * 0.0254;

/// The lone scout's spot after it deploys at `epoch`.
fn scout_spot_at(epoch: u32) -> (f64, f64) {
    let specs = vec![UnitSpec {
        key: "scouts".into(),
        model_count: 1,
        base_r_m: 0.016,
        footprint: vec![(0.0, 0.0)],
        scout: true,
        ..Default::default()
    }];
    let sd = deploy_side(&specs, &scout_zone(), &[(0.0, 0.0)], &empty_board(), 7, epoch);
    assert_eq!(sd.placements.len(), 1, "the scout deploys: {sd:?}");
    sd.placements[0].spot
}

#[test]
fn scout_stays_within_nine_inches_of_its_zone_at_epoch_73() {
    let spot = scout_spot_at(EPOCH_73_V36);
    assert!(spot.1 <= NINE_INCH_LINE + 1e-9, "a 3.6 scout stands at most 9\" ahead of its zone, got {spot:?}");
}

#[test]
fn scout_may_pass_nine_inches_inside_its_twelve_inch_band_at_epoch_72() {
    let spot = scout_spot_at(EPOCH_72_PLAYTEST_RULES);
    assert!(spot.1 > NINE_INCH_LINE, "below 3.6 the 12\" band reaches past the 9\" line, got {spot:?}");
    assert!(spot.1 <= 1e-9, "but never past the 12\" band's edge (the table centre), got {spot:?}");
}
