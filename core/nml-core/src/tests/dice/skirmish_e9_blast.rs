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

/// The volley's spread wiring: one Blast(4) hit on a 3-model unit with a 3-model neighbour keeps 2 hits on the target (2
/// saves rolled) and spills 2; with no neighbours passed it is today's multiply (3 saves) and spills nothing.
#[test]
fn the_volley_keeps_the_targets_share_and_spills_the_rest() {
    let att = Ctx { quality: 4, ..Default::default() };
    let def = Ctx { quality: 4, defense: 4, tough: 3, models: 3, ..Default::default() };
    let guns = [blast_gun(4, 1)];
    let sh = [Shooter { profiles: &guns, keep: &[0], attacks: &[1], att: &att, owner: "Gunner" }];
    let volley = |spread: &[i64]| {
        let mut tray = Tray::supplied(vec![vec![5], vec![1, 1, 1]]);
        resolve_volley_with_pick_label(&sh, &def, "Squad", 12.0, 12.0, true, true, true, true, true, true,
            &|_| (false, "trooper".into(), 0), &|_, _| None, None, None, spread, &mut tray)
    };
    let spread = volley(&[3]);
    assert_eq!(spread.rolls[1].count, 2, "the target's share: {:?}", spread.rolls);
    assert_eq!(spread.blast_spill, vec![crate::dice::BlastSpill { shooter: 0, profile: 0, hits: vec![2] }]);
    assert!(spread.log.iter().any(|l| l == "Blast(4): 1 hit -> 2 on Squad, 2 on units within reach, 0 lost"), "{:?}", spread.log);
    let plain = volley(&[]);
    assert_eq!(plain.rolls[1].count, 3, "no neighbours: 1 x min(4, 3)");
    assert!(plain.blast_spill.is_empty());
}

/// The neighbour leg's fixed-hits weapon rolls no attack die and no face-read extra: 3 fixed hits roll exactly 3 saves
/// and wound on every failed one; the same tray with a normal weapon spends its first face on the attack roll.
#[test]
fn a_fixed_hits_weapon_rolls_only_the_saves() {
    let att = Ctx { quality: 4, ..Default::default() };
    let def = Ctx { quality: 4, defense: 4, models: 3, ..Default::default() };
    let fixed = [ShootProfile { name: "Gun".into(), attacks: 1, count: 1, range: 24, rending: true, fixed_hits: Some(3), ..Default::default() }];
    let sh = [Shooter { profiles: &fixed, keep: &[0], attacks: &[1], att: &att, owner: "Gunner" }];
    let mut tray = Tray::supplied(vec![vec![1, 6, 2]]);
    let r = resolve_volley_with_pick_label(&sh, &def, "Squad", 12.0, 12.0, true, true, true, true, true, true,
        &|_| (false, "trooper".into(), 0), &|_, _| None, None, None, &[], &mut tray);
    assert_eq!(r.rolls.len(), 1, "no attack roll: {:?}", r.rolls);
    assert_eq!((r.rolls[0].kind, r.rolls[0].count, r.rolls[0].target), ("defense", 3, 4), "{:?}", r.rolls);
    assert_eq!(r.wounds, 2, "two saves fail (1, 2); Rending reads no attack faces");
}

/// Ruling D-29-R1 (plan step 29a): from `PENDING_EPOCH_BLAST_EVEN` the WHOLE attack's hits split evenly - 2 hits of Blast(3)
/// over two units with room are 3 + 3, not 4 + 2 (each original hit's remainder on the target); one epoch below, as before.
#[test]
fn d29_r1_the_whole_attack_splits_evenly_from_its_epoch() {
    use crate::acts::PENDING_EPOCH_BLAST_EVEN as E;
    use crate::dice::blast_split_at;
    assert_eq!(blast_split_at(2, 3, 5, &[5], E), vec![3, 3]);
    assert_eq!(blast_split_at(2, 3, 5, &[5], E - 1), vec![4, 2], "a record below the epoch replays as recorded");
    assert_eq!(blast_split_at(2, 4, 5, &[5, 5], E), vec![3, 3, 2], "the remainder one each, target first");
    assert_eq!(blast_split_at(2, 4, 1, &[5], E), vec![2, 6], "a full unit's share goes to the rest");
    assert_eq!(blast_split_at(3, 6, 2, &[1, 1, 1], E), vec![6, 3, 3, 3], "the book example: room caps every unit");
    for hits in 0..=1 {
        for x in 1..=6 {
            for (t, n) in [(1, vec![]), (3, vec![3]), (2, vec![1, 1, 1]), (5, vec![2, 4])] {
                assert_eq!(blast_split_at(hits, x, t, &n, E), blast_split(hits, x, t, &n), "one hit is unchanged: {hits} {x} {t} {n:?}");
            }
        }
    }
    for x in 1..=6 {
        for models in 1..=6 {
            assert_eq!(blast_split_at(3, x, models, &[], E), vec![3 * x.clamp(1, models)], "no neighbours: the plain multiply");
        }
    }
}

/// The shooting volley reads the attacker's epoch: two Blast(3) hits on a 5-model unit beside a 5-model neighbour keep 3
/// on the target from `PENDING_EPOCH_BLAST_EVEN`, 4 one epoch below.
#[test]
fn d29_r1_the_volley_splits_by_the_record_epoch() {
    let def = Ctx { quality: 4, defense: 4, models: 5, ..Default::default() };
    let guns = [blast_gun(3, 2)];
    let kept = |epoch: u32| {
        let att = Ctx { quality: 4, rules_epoch: epoch, ..Default::default() };
        let sh = [Shooter { profiles: &guns, keep: &[0], attacks: &[2], att: &att, owner: "Gunner" }];
        let mut tray = Tray::supplied(vec![vec![5, 5], vec![1; 6]]);
        let r = resolve_volley_with_pick_label(&sh, &def, "Squad", 12.0, 12.0, true, true, true, true, true, true,
            &|_| (false, "trooper".into(), 0), &|_, _| None, None, None, &[5], &mut tray);
        (r.rolls[1].count, r.blast_spill[0].hits.clone())
    };
    assert_eq!(kept(crate::acts::PENDING_EPOCH_BLAST_EVEN), (3, vec![3]));
    assert_eq!(kept(crate::acts::PENDING_EPOCH_BLAST_EVEN - 1), (4, vec![2]));
}
