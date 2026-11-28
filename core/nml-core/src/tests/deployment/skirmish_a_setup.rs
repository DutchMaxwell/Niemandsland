//! Step 8b (the 3.6 books p.6: "places one unit fully within 12 in of their table edge", every system): the deployment
//! zone admits a base only when the whole base is inside. Proves GFF-A1-01 / AOFS-A1-01.
use super::*;
use crate::acts::EPOCH_105_ZONE_BASE_EDGE as E;

/// 48x48 `front_line`, player 1 zone z in [-24, -12] in board-centred inches = 0..12 in from player 1's edge.
fn front_line_p1() -> Vec<Zone> {
    let catalog: serde_json::Value =
        serde_json::from_str(include_str!("../../../../../assets/solo/deployments.json")).expect("catalogue");
    catalog_zones_for_board(&catalog, "front_line", [48.0, 48.0]).expect("48x48 front_line")[0].clone()
}

/// GFF-A1-01 / AOFS-A1-01: a 32 mm base (r 0.63 in) whose centre is 11.37 in from the edge is fully inside; at 11.5 in its
/// far edge is at 12.13 in, so from the epoch it is refused, while one epoch below the centre test still admits it.
#[test]
fn a1_01_the_whole_base_must_be_within_12_in() {
    assert_eq!(E, 105);
    assert!(crate::acts::rule_on(crate::acts::CURRENT_RULES_EPOCH, E), "a fresh game stamps it on");
    let z = front_line_p1();
    let at = |from_edge_in: f64| (0.0, (-24.0 + from_edge_in) * crate::IN2M); // world metres, x centred
    let r = 0.63 * crate::IN2M;
    assert!(zones_contain_base(&z, at(11.37), r), "base edge at 12.0 in: inside");
    assert!(!zones_contain_base(&z, at(11.5), r), "base edge at 12.13 in: outside");
    assert!(crate::deployment::zone_admits_base(&z, at(11.5), r, crate::acts::EPOCH_104_TWO_BEARERS), "old leg: a record at 104 - the centre test admits it");
    assert!(!crate::deployment::zone_admits_base(&z, at(11.5), r, E), "from the epoch: refused");
    assert!(crate::deployment::zone_admits_base(&z, at(11.37), r, E), "from the epoch: the 11.37 in base still fits");
    assert!(zones_contain_base(&z, at(11.5), 0.0), "a zero radius is the centre alone");
}
