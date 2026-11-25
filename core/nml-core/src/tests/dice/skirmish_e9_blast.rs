//! The skirmish Blast(X) spread, `blast_split`, on the Firefight / AoF: Skirmish book examples (p.13). The cap is per
//! ORIGINAL hit. With no neighbours the split equals today's shooting-leg multiply, which stays the guard.
use super::*;
use crate::dice::blast_split;

fn blast_gun(x: i64, attacks: i64) -> ShootProfile {
    ShootProfile { name: "Gun".into(), attacks, count: 1, range: 24, blast: x, ..Default::default() }
}

/// Book example 1: 2 hits with Blast(3) on a 2-model unit -> 4 hits; the live shooting leg agrees.
#[test]
fn two_blast_3_hits_on_two_models_make_four() {
    assert_eq!(blast_split(2, 3, 2, &[]), vec![4]);
    let att = Ctx { quality: 4, ..Default::default() };
    let def = Ctx { quality: 4, defense: 4, tough: 3, models: 2, ..Default::default() };
    let mut tray = Tray::supplied(vec![vec![4, 5], vec![1, 1, 1, 1]]);
    let out = resolve_shooting_with_tray(&[blast_gun(3, 2)], &[0], &[2], &att, &def, 12.0, &mut tray);
    assert_eq!(out.rolls[1].count, 4, "2 hits x min(3, 2 models) = 4 saves to roll");
}

/// Book example 2: one Blast(6) hit on a 2-model unit with three single models near -> 2, 1, 1, 1; one hit is lost.
#[test]
fn a_blast_6_hit_spreads_two_one_one_one_and_loses_one() {
    assert_eq!(blast_split(1, 6, 2, &[1, 1, 1]), vec![2, 1, 1, 1]);
}

/// One Blast(5) hit on a 3-model unit with another 3-model unit near: 3 / 2, the odd hit on the target by default.
#[test]
fn an_odd_blast_hit_lands_on_the_target_by_default() {
    let split = blast_split(1, 5, 3, &[3]);
    assert_eq!(split, vec![3, 2]);
    assert_eq!(split.iter().sum::<i64>(), 5);
}

/// "As evenly as possible": Blast(4) on two 3-model units is 2 / 2, and Blast(6) on three is 2 / 2 / 2 - never the
/// target filled first (3 / 1, 3 / 3 / 0).
#[test]
fn the_spread_is_even_not_target_first() {
    assert_eq!(blast_split(1, 4, 3, &[3]), vec![2, 2]);
    assert_eq!(blast_split(1, 6, 3, &[3, 3]), vec![2, 2, 2]);
}

/// The cap is per original hit: three hits repeat the one-hit split three times.
#[test]
fn every_original_hit_splits_on_its_own() {
    assert_eq!(blast_split(3, 6, 2, &[1, 1, 1]), vec![6, 3, 3, 3]);
}

/// No neighbours is the shooting leg's multiply `hits * x.clamp(1, models)`; Blast(1) or less keeps the hits as they are.
#[test]
fn without_neighbours_the_split_is_todays_multiply() {
    for hits in 0..4 {
        for x in 0..8 {
            for models in 1..6 {
                assert_eq!(blast_split(hits, x, models, &[]), vec![hits * x.clamp(1, models)], "{hits} {x} {models}");
            }
        }
    }
    assert_eq!(blast_split(2, 1, 3, &[3]), vec![2, 0]);
}
