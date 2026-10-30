//! MEL-09: from `EPOCH_73_V36` a fatigued striker (a Shaken strike-back counts as one) still hits
//! on its unmodified 6s, but those sixes fire no special rule: no Rending AP, no Surge bonus hit.
//! Epoch 72 keeps today's reading. The table twin is test/v36/mel_09_test.gd.
use super::super::*;
use crate::acts::{rule_on, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// A Quality 4 striker swings 12 attacks with `weapon` back (no charge) at a Defense 4 unit of
/// 10, tray seed 909: (sixes in the hit roll, every save roll as (count, target), the log).
fn strike(weapon: ShootProfile, fatigued: bool, epoch: u32) -> (i64, Vec<(i64, i64)>, Vec<String>) {
    let att = Ctx { quality: 4, fatigued, ..Default::default() };
    let w = [weapon];
    let r = resolve_melee_leg(&[striker(&w, &[0], &[12], &att)], &defender(4, 10), "Foe",
        false, true, true, true, 0.0, true, true, false, rule_on(epoch, EPOCH_73_V36), &mut Tray::seeded(909));
    let sixes = r.rolls[0].faces.iter().filter(|&&f| f == 6).count() as i64;
    let saves = r.rolls.iter().filter(|x| x.kind == "defense").map(|x| (x.count, x.target)).collect();
    (sixes, saves, r.log)
}

fn rending() -> ShootProfile {
    ShootProfile { rending: true, ..blade(12) }
}

fn surge() -> ShootProfile {
    ShootProfile { surge: true, ..blade(12) }
}

fn muted(log: &[String]) -> bool {
    log.iter().any(|l| l.contains("trigger no special rules"))
}

#[test]
fn fatigued_rending_sixes_still_rend_at_epoch_72() {
    let (sixes, saves, log) = strike(rending(), true, EPOCH_72_PLAYTEST_RULES);
    assert!(sixes > 0, "seed 909 must roll a six to hit");
    assert_eq!(saves, vec![(sixes, save_target(4, RENDING_AP_BONUS))], "every hit is a six, all save at AP(+4)");
    assert!(!muted(&log));
}

#[test]
fn fatigued_rending_sixes_hit_but_do_not_rend_at_epoch_73() {
    let (sixes, saves, log) = strike(rending(), true, EPOCH_73_V36);
    assert!(sixes > 0, "seed 909 must roll a six to hit");
    assert_eq!(saves, vec![(sixes, 4)], "the sixes still hit and save at the plain Defense");
    assert!(log.iter().any(|l| l.starts_with(&format!("Fatigued: Striker — {sixes} unmodified 6"))), "{log:?}");
}

#[test]
fn a_fresh_striker_still_rends_on_sixes_at_epoch_73() {
    let (sixes, saves, log) = strike(rending(), false, EPOCH_73_V36);
    assert!(saves.contains(&(sixes, save_target(4, RENDING_AP_BONUS))), "{saves:?}");
    assert!(!muted(&log));
}

#[test]
fn fatigued_surge_sixes_still_add_hits_at_epoch_72() {
    let (sixes, saves, _) = strike(surge(), true, EPOCH_72_PLAYTEST_RULES);
    assert!(sixes > 0, "seed 909 must roll a six to hit");
    assert_eq!(saves, vec![(2 * sixes, 4)], "each six hits and adds one more hit");
}

#[test]
fn fatigued_surge_sixes_add_no_hits_at_epoch_73() {
    let (sixes, saves, log) = strike(surge(), true, EPOCH_73_V36);
    assert_eq!(saves, vec![(sixes, 4)], "each six is one hit, nothing more");
    assert!(muted(&log), "{log:?}");
}
