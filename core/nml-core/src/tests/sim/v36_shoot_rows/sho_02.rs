//! SHO-02 (rules 3.6, lane shoot): the AI's expected hits never priced the Indirect moved -1 —
//! the penalty lived at the dice seam only (dice.rs / main.gd's volley paths). Rules 3.6 removes
//! it from that seam; the EV stays exactly what it was, epoch-blind. This pins that the GREEN
//! change does not invent an EV penalty at 72 or 73.
use super::super::*;

#[test]
fn the_ev_has_no_moved_indirect_penalty_at_either_leg() {
    let mortar = ShootProfile {
        name: "Mortar".into(),
        attacks: 4,
        count: 1,
        range: 24,
        indirect: true,
        indirect_moved_hit_penalty: 1,
        ..Default::default()
    };
    let def = Ctx { defense: 4, models: 5, tough: 1, ..Default::default() };
    let moved = Ctx { quality: 4, moved_this_round: true, ..Default::default() };
    let held = Ctx { quality: 4, moved_this_round: false, ..Default::default() };
    let ev = |att: &Ctx| crate::combat::profile_ev(&mortar, 4, att, &def, 12.0, false);
    assert_eq!(
        ev(&moved),
        ev(&held),
        "the EV imagination has no moved penalty to drop at 73"
    );
}
