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
            false, true, true, true, 0.0, true, true, rule_on(epoch, EPOCH_73_V36), false, rule_on(epoch, EPOCH_73_V36), &mut tray);
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

mod mel_07c {
    //! MEL-07c: from `EPOCH_73_V36` the defender's Parry(X) cancels strike hits after the
    //! strike's hit rolls and before any save. Each 6+ cancels the highest-worth hit, so a
    //! Rending six goes before a plain hit. Below 73 no Parry die is drawn.
    use super::super::*;

    fn parry_defender(models: i64) -> Ctx {
        Ctx { defense: 4, models, tough: 1, parry_dice: 1, ..Default::default() }
    }

    fn strike(epoch_gate: bool, def: &Ctx, seed: i64) -> ShootResult {
        let p = blade(5);
        let att = Ctx { quality: 2, ..Default::default() };
        let mut tray = Tray::seeded(seed);
        tray.set_zero_draws(true);
        resolve_melee_leg(&[striker(&[p], &[0], &[5], &att)], def, "Foe", false, true, true,
            true, 0.0, true, true, epoch_gate, false, false, &mut tray)
    }

    #[test]
    fn two_parry_models_cancel_strike_hits_before_the_saves() {
        let def = parry_defender(2);
        let r = strike(true, &def, 7);
        let attack = r.rolls.iter().find(|x| x.kind == "attack").unwrap();
        let hits = faces_to_hits(&attack.faces, 2) as i64;
        let parry = r.rolls.iter().find(|x| x.kind == "parry").expect("a Parry roll is drawn");
        assert_eq!((parry.count, parry.target), (2.min(hits), 6), "{:?}", r.rolls);
        let cancelled = parry.faces.iter().filter(|&&f| f >= 6).count() as i64;
        assert!(cancelled > 0, "the seeded Parry faces cancel a hit: {:?}", parry.faces);
        let saved: i64 = r.rolls.iter().filter(|x| x.kind == "defense").map(|x| x.count).sum();
        assert_eq!(saved, hits - cancelled, "{:?}", r.rolls);
        assert!(r.log.iter().any(|l| l == "Parry: Foe rolls 2 dice and cancels 1 strike hits"), "{:?}", r.log);
    }

    #[test]
    fn parry_cancels_the_rending_six_before_a_plain_hit() {
        let plain = blade(1);
        let rending = ShootProfile { rending: true, ..blade(1) };
        let profiles = [plain, rending];
        let att = Ctx::default();
        let sh = striker(&profiles, &[0, 1], &[1, 1], &att);
        let mut pending = vec![
            (&sh, &profiles[0], vec![4], 1, 0, 0, false, 1),
            (&sh, &profiles[1], vec![6], 1, 0, 0, false, 1),
        ];
        let def = Ctx { defense: 4, models: 1, parry_dice: 1, ..Default::default() };
        let mut tray = Tray::seeded(7);
        let mut out = ShootResult::default();
        crate::dice::parry_strike(&mut pending, &def, "Foe", true, &mut tray, &mut out);
        assert_eq!(pending[0].3, 1, "the plain hit survives");
        assert_eq!(pending[1].3, 0, "the Rending six is worth more and is cancelled");
    }

    #[test]
    fn no_parry_dice_are_drawn_at_epoch_72() {
        let r = strike(false, &Ctx { defense: 4, models: 2, tough: 1, ..Default::default() }, 7);
        assert!(r.rolls.iter().all(|x| x.kind != "parry"), "{:?}", r.rolls);
        assert!(r.log.iter().all(|l| !l.starts_with("Parry:")));
    }
}
