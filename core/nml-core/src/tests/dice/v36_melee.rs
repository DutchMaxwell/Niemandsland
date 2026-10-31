//! Rules 3.6 lane melee tests for the dice module; owned by lane melee.

mod mel_07a {
    //! MEL-07a: from `EPOCH_73_V36` one strike rolls every hit of the attacking unit before any save
    //! (no rule, only the draw order; Parry will sit between the two). Epoch 72 keeps today's order:
    //! each weapon rolls its hits and then its saves before the next weapon rolls. The faces are the
    //! table's for the same seeded strike (test/v36/mel_07a_test.gd): both engines draw the same dice
    //! in the same order.
    use super::super::*;
    use crate::acts::{rule_on, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

    /// A Quality 4 striker with two plain 4-attack weapons strikes back (no charge) at a Defense 4
    /// unit of 10, tray seed 7360, zero-die rolls taken literally (the live tray since epoch 67).
    fn two_weapon_strike(epoch: u32) -> Vec<(&'static str, Vec<u8>)> {
        let att = Ctx { quality: 4, ..Default::default() };
        let weapons = [blade(4), ShootProfile { name: "Spear".into(), ..blade(4) }];
        let mut tray = Tray::seeded(7360);
        tray.set_zero_draws(true);
        let r = resolve_melee_leg(&[striker(&weapons, &[0, 1], &[4, 4], &att)], &defender(4, 10), "Foe",
            false, true, true, true, 0.0, true, true, rule_on(epoch, EPOCH_73_V36), &mut tray);
        r.rolls.iter().map(|x| (x.kind, x.faces.clone())).collect()
    }

    #[test]
    fn each_weapon_rolls_its_hits_then_its_saves_at_epoch_72() {
        assert_eq!(two_weapon_strike(EPOCH_72_PLAYTEST_RULES), vec![
            ("attack", vec![2, 2, 6, 5]), ("defense", vec![4, 3]),
            ("attack", vec![3, 5, 2, 4]), ("defense", vec![4, 2]),
        ]);
    }

    #[test]
    fn every_hit_roll_comes_before_any_save_at_epoch_73() {
        assert_eq!(two_weapon_strike(EPOCH_73_V36), vec![
            ("attack", vec![2, 2, 6, 5]), ("attack", vec![4, 3, 3, 5]),
            ("defense", vec![2, 4]), ("defense", vec![4, 2]),
        ]);
    }
}
