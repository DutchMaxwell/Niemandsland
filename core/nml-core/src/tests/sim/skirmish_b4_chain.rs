//! The coherency chain per skirmish book: Firefight 9 in (3.6 book p.7), AoF: Skirmish 6 in, read through
//! `Book::chain_in_at` from `EPOCH_98_FIREFIGHT_CHAIN` on. One straight line of 32 mm bases, centres 2 in apart.
use crate::acts::EPOCH_98_FIREFIGHT_CHAIN as E;
use crate::mv::gate::{coherent_placement, GateFlags};

/// 32 mm round base, radius in inches.
const R_IN: f64 = 0.63;

fn line(n: usize) -> Vec<[f32; 2]> {
    (0..n).map(|i| [10.0 + 2.0 * i as f32, 20.0]).collect()
}

fn coherent(sys: &str, n: usize, epoch: u32) -> bool {
    let flags = GateFlags { coherent_chain_in: crate::rules::book(sys).chain_in_at(epoch), ..Default::default() };
    coherent_placement(&line(n), &vec![R_IN; n], flags)
}

/// Five models spread 6.74 in edge to edge, six spread 8.74 in: inside Firefight's 9 in from the epoch on.
#[test]
fn firefight_five_and_six_model_lines_are_coherent_from_the_epoch() {
    assert!(coherent("gff", 5, E), "6.74 in spread is inside the 9 in chain");
    assert!(coherent("gff", 6, E), "8.74 in spread is inside the 9 in chain");
    assert!(!coherent("gff", 5, E - 1), "one epoch below, 6.74 in breaks the recorded 6 in chain");
}

/// AoF: Skirmish keeps 6 in on both sides of the epoch, so the Firefight change cannot drag it along.
#[test]
fn skirmish_fantasy_keeps_the_six_inch_chain() {
    for epoch in [E - 1, E] {
        assert!(!coherent("aofs", 5, epoch), "6.74 in spread breaks the 6 in chain at {epoch}");
        assert!(coherent("aofs", 4, epoch), "4.74 in spread is inside 6 in at {epoch}");
    }
}
