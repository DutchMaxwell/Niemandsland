//! Rules 3.6 lane ux tests for the deployment module; owned by lane ux.

// ---- UX-12 (`EPOCH_73_V36`): the Scout band — how far ahead of its own zone a Scout unit sets
// up — is 9" from the rules 3.6 epoch on and stays 12" below it. One scout alone on an empty
// board with the only objective at the table centre: it runs as far forward as its band allows.

use super::empty_board;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::deployment::{deploy_side, settle_units_at, ModelShape, Rect, SideDeploy, UnitSpec};

/// Side 1's 12"-deep zone along the -Z table edge; its forward edge is y = -0.3048.
fn scout_zone() -> Rect {
    Rect::new(-0.9144, -0.6096, 1.8288, 0.3048)
}

/// The line 9" ahead of the zone's forward edge.
const NINE_INCH_LINE: f64 = -0.3048 + 9.0 * 0.0254;

/// One single-model scout on a 32 mm round base.
fn scout_specs() -> Vec<UnitSpec> {
    vec![UnitSpec {
        key: "scouts".into(),
        model_count: 1,
        base_r_m: 0.016,
        footprint: vec![(0.0, 0.0)],
        scout: true,
        model_shapes: vec![ModelShape { is_oval: false, w_mm: 32, d_mm: 32, tough: 1, n: 1 }],
        ..Default::default()
    }]
}

/// The lone scout's deployment at `epoch`.
fn scout_deploy_at(epoch: u32) -> SideDeploy {
    let sd = deploy_side(&scout_specs(), &scout_zone(), &[(0.0, 0.0)], &empty_board(), 7, epoch);
    assert_eq!(sd.placements.len(), 1, "the scout deploys: {sd:?}");
    sd
}

/// The lone scout's spot after it deploys at `epoch`.
fn scout_spot_at(epoch: u32) -> (f64, f64) {
    scout_deploy_at(epoch).placements[0].spot
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

/// The settle pass keeps a scout inside its zone of record: the same epoch's band it deployed in.
#[test]
fn settle_records_the_scouts_band_at_epoch_72_and_epoch_73() {
    for (epoch, band_in) in [(EPOCH_72_PLAYTEST_RULES, 12.0), (EPOCH_73_V36, 9.0)] {
        let st = settle_units_at(&scout_specs(), &scout_deploy_at(epoch), &scout_zone(), epoch);
        let zone_of = st[0].1.zone; // a Rect narrows to f32: compare at 1e-6
        assert!(
            (zone_of.end().1 - (-0.3048 + band_in * 0.0254)).abs() < 1e-6,
            "epoch {epoch}: the scout's zone of record reaches {band_in}\" ahead, got {zone_of:?}"
        );
        assert!((zone_of.pos.1 - -0.6096).abs() < 1e-6, "epoch {epoch}: the rear edge stays, got {zone_of:?}");
    }
}
