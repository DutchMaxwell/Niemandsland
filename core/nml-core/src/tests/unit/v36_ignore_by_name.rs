//! Epoch 82 (`EPOCH_82_IGNORE_BY_NAME`, table twin `_solo_ignore_wounds`): a bypass (Bane, Rending, Unstoppable, ...) skips only the
//! roll of the group named Regeneration. A unit whose ignore rule has another name (Self-Repair, Plaguebound, Resistance, ...) still
//! rolls the bypassed wounds. RED at epoch 81 (the folded roll, skipped whole), GREEN at 82.

use super::*;
use crate::acts::{EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF, EPOCH_82_IGNORE_BY_NAME, EPOCH_84_IGNORE_GROUPS};
use crate::dice::{ShootResult, Tray};

/// `volley` with the target's ignore groups stated (slot 0 Regeneration, then the other names): the folded `regen_target` is the best of them.
fn grouped(epoch: u32, groups: [i64; 4], rending: bool) -> ShootResult {
    let att = Ctx { quality: 2, models: 1, v36_rules: true, rules_epoch: epoch, ..Default::default() };
    let best = groups.iter().copied().filter(|&t| t > 0).min().unwrap_or(0);
    let def = Ctx {
        defense: 6, tough: 1, models: 20, regeneration: true, regen_target: best, regen_named: groups[0] > 0, regen_groups: groups,
        v36_rules: true, playtest_rules: true, rules_epoch: epoch, ..Default::default()
    };
    let prof = ShootProfile { name: "Gun".into(), attacks: 24, count: 1, range: 24, rending, ..Default::default() };
    crate::dice::resolve_shooting_with_tray(&[prof], &[0], &[24], &att, &def, 12.0, &mut Tray::seeded(27))
}

/// One 24-attack volley of a Rending weapon (every shot wounds past a Defense 6+ save the target cannot make) at a target whose
/// ignore roll is `regen_target`+ and is (`named`) / is not the rule named Regeneration, at `epoch`.
fn volley(epoch: u32, named: bool, melee: bool, deadly: i64) -> ShootResult {
    let att = Ctx { quality: 2, models: 1, v36_rules: true, rules_epoch: epoch, ..Default::default() };
    let def = Ctx {
        defense: 6, tough: 1, models: 20, regeneration: true, regen_target: 6, regen_named: named, v36_rules: true,
        playtest_rules: true, rules_epoch: epoch, ..Default::default()
    };
    let prof = ShootProfile { name: "Gun".into(), attacks: 24, count: 1, range: 24, rending: true, deadly, ..Default::default() };
    let mut tray = Tray::seeded(27);
    if melee {
        crate::dice::resolve_melee_with_tray(
            &[crate::dice::Shooter { profiles: std::slice::from_ref(&prof), keep: &[0], attacks: &[24], att: &att, owner: "Carrier" }],
            &def, "Target", true, false, false, &mut tray,
        )
    } else {
        crate::dice::resolve_shooting_with_tray(&[prof], &[0], &[24], &att, &def, 12.0, &mut tray)
    }
}

/// The target's ignore dice: the roll at `regen_target`+ that is not an attack or a save.
fn ignore_dice(out: &ShootResult) -> i64 {
    out.rolls.iter().filter(|r| r.target == 6 && r.count > 0 && r.owner != "Carrier" && r.kind == "attack").map(|r| r.count).sum()
}

#[test]
fn a_bypass_still_meets_a_rule_not_named_regeneration_from_epoch_82() {
    for melee in [false, true] {
        let old = volley(EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF, false, melee, 0);
        assert!(old.caused > 0, "melee {melee}: the fixture wounds");
        assert_eq!(ignore_dice(&old), 0, "epoch 81 folds the family into one roll the bypass skips: {:?}", old.rolls);
        assert_eq!(old.wounds, old.caused, "epoch 81: every bypassed wound lands");
        let new = volley(EPOCH_82_IGNORE_BY_NAME, false, melee, 0);
        assert_eq!(ignore_dice(&new), new.caused, "epoch 82: the bypassed wounds roll at the rule's own 6+ (melee {melee}): {:?}", new.rolls);
        assert!(new.wounds < new.caused, "melee {melee}: some wound is ignored on a 6+ ({} of {})", new.wounds, new.caused);
    }
}

/// CONTROL (the check can fail): against the rule really named Regeneration the bypass still skips the roll at 82.
#[test]
fn a_bypass_still_skips_the_roll_of_the_rule_named_regeneration_at_epoch_82() {
    for melee in [false, true] {
        let out = volley(EPOCH_82_IGNORE_BY_NAME, true, melee, 0);
        assert!(out.caused > 0);
        assert_eq!((ignore_dice(&out), out.wounds), (0, out.caused), "melee {melee}: {:?}", out.rolls);
    }
}

/// A Deadly bypass weapon follows the same rule: its per-model groups roll at the rule's own target from 82.
#[test]
fn a_deadly_bypass_weapon_follows_the_same_rule() {
    let old = volley(EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF, false, false, 2);
    let new = volley(EPOCH_82_IGNORE_BY_NAME, false, false, 2);
    assert_eq!(ignore_dice(&old), 0, "{:?}", old.rolls);
    assert!(ignore_dice(&new) > 0, "{:?}", new.rolls);
}

#[test]
fn the_regeneration_group_is_the_rule_its_aura_and_medical_training() {
    use crate::unit::regeneration_group as g;
    assert!(g("Regeneration", "") && g("Regeneration Buff", "") && g("Regeneration Aura", "") && g("Medical Training", ""));
    assert!(g("Enhanced Regeneration", "Regeneration"));
    assert!(!g("Self-Repair", "") && !g("Resistance", "") && !g("Plaguebound", "") && !g("Enhanced Self-Repair", "Self-Repair"));
}

/// Two differently named rules (Plaguebound and Protected, both 6+) roll one after the other on the wounds still standing; below
/// epoch 82 the family is one roll at the best target.
#[test]
fn two_named_groups_roll_one_after_the_other_from_epoch_84() {
    let old = grouped(EPOCH_82_IGNORE_BY_NAME, [0, 6, 6, 0], false);
    let new = grouped(EPOCH_84_IGNORE_GROUPS, [0, 6, 6, 0], false);
    let dice = |o: &ShootResult| o.rolls.iter().filter(|r| r.target == 6 && r.kind == "attack").map(|r| r.count).collect::<Vec<_>>();
    assert_eq!(dice(&old).len(), 1, "epoch 82: one folded roll: {:?}", old.rolls);
    let new_dice = dice(&new);
    assert_eq!(new_dice.len(), 2, "epoch 84: one roll per name: {:?}", new.rolls);
    assert_eq!(new_dice[0], new.caused, "the first group rolls every wound");
    assert!(new_dice[1] < new_dice[0] && new_dice[1] > 0, "the second rolls what the first left: {new_dice:?}");
    assert!(new.wounds <= new_dice[1], "what the second roll leaves lands: {} of {}", new.wounds, new_dice[1]);
}

/// Regeneration beside another rule: a bypass skips only the Regeneration roll and meets the other rule (RED at epoch 82 before the
/// groups: the whole fold was skipped; at 81 it still is).
#[test]
fn a_bypass_skips_the_regeneration_group_and_meets_the_other_name() {
    let old = grouped(EPOCH_82_IGNORE_BY_NAME, [5, 6, 0, 0], true);
    assert_eq!(ignore_dice(&old), 0, "epoch 82 skips the whole fold: {:?}", old.rolls);
    let new = grouped(EPOCH_84_IGNORE_GROUPS, [5, 6, 0, 0], true);
    assert_eq!(new.rolls.iter().filter(|r| r.target == 5).count(), 0, "no Regeneration roll for a bypassed wound: {:?}", new.rolls);
    assert_eq!(ignore_dice(&new), new.caused, "the other rule rolls every bypassed wound: {:?}", new.rolls);
    assert!(new.wounds < new.caused);
}

#[test]
fn the_group_key_and_the_roll_order_are_the_tables() {
    use crate::unit::ignore_group_key as k;
    assert_eq!((k("Enhanced Knightborn", "").as_str(), k("Plaguebound Boost", "").as_str(), k("Cursed Undead Aura", "").as_str()), ("Knightborn", "Plaguebound", "Cursed Undead"));
    assert_eq!((k("Self-Repair Boost", "Self-Repair").as_str(), k("Spell Resistance", "").as_str(), k("Regeneration Buff", "").as_str()), ("Self-Repair", "Spell Resistance", "Regeneration"));
}
