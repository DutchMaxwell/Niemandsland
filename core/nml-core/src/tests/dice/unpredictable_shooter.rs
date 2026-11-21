use super::*;

    // ------------------------ block B12: Unpredictable's SHOOTING leg ---

    /// Unpredictable's SHOOTING leg (main.gd:3096-3110): ONE die for the whole
    /// volley before any weapon fires, 1-3 is AP(+1) on every profile of the
    /// volley (the save target rises), 4-6 is +1 to hit (the hit target
    /// falls). Both halves, off one known seed each, with the second face
    /// chosen to connect so both save batches are actually observed.
    #[test]
    fn an_unpredictable_shooters_volley_draws_the_extra_die_and_its_face_picks_the_half() {
        let p = [rifle(1)];
        let att = Ctx {
            unpredictable_shooting: true,
            unpredictable_ap_bonus: 1,
            unpredictable_hit_bonus: 1,
            unpredictable_low_roll_max: 3,
            ..shooter(4)
        };
        let low = (1i64..)
            .find(|&s| Tray::seeded(s).roll(2)[0] <= 3 && Tray::seeded(s).roll(2)[1] >= 4)
            .unwrap();
        let high = (1i64..)
            .find(|&s| Tray::seeded(s).roll(2)[0] >= 4 && Tray::seeded(s).roll(2)[1] >= 3)
            .unwrap();

        let mut tray = Tray::seeded(low);
        let one = [Shooter { profiles: &p, keep: &[0], attacks: &[1], att: &att, owner: "gunner" }];
        let out = resolve_volley_with_tray(&one, &defender(4, 5), "Target", 12.0, 12.0, true, true, true, true, &mut tray);
        assert_eq!(out.rolls[0].kind, "attack");
        assert_eq!(out.rolls[0].count, 1, "ONE die for the whole volley");
        assert_eq!(out.rolls[0].target, BEST_HIT_TARGET);
        assert_eq!(out.rolls[0].faces, Tray::seeded(low).roll(1), "the rule die draws FIRST");
        assert_eq!(out.rolls[0].owner, "gunner", "the shooter signs the rule die");
        assert_eq!(out.rolls[1].target, 4, "the AP half leaves the hit target alone");
        assert_eq!(out.rolls[1].faces, Tray::seeded(low).roll(2)[1..2], "hit dice come after it");
        assert_eq!(out.rolls[2].kind, "defense");
        assert_eq!(out.rolls[2].target, 5, "AP(+1) folded into the volley's profiles");

        let mut tray = Tray::seeded(high);
        let out = resolve_shooting_with_tray(&p, &[0], &[1], &att, &defender(4, 5), 12.0, &mut tray);
        assert_eq!(out.rolls[0].faces, Tray::seeded(high).roll(1));
        assert_eq!(out.rolls[1].target, 3, "the hit half is +1 to hit on Quality 4+");
        assert_eq!(out.rolls[2].target, 4, "no AP on the hit half");
    }

    /// The MELEE-only variant must not leak into shooting: a unit stamped with
    /// the melee flag ("Unpredictable Fighter") fires no extra volley die
    /// (main.gd:5403-5412 gates the shooting leg on the other two names).
    #[test]
    fn an_unpredictable_fighters_volley_draws_no_extra_die() {
        let p = [rifle(1)];
        let att = Ctx { unpredictable: true, ..shooter(4) };
        let seed = (1i64..).find(|&s| Tray::seeded(s).roll(1)[0] >= 4).unwrap();
        let mut tray = Tray::seeded(seed);
        let out = resolve_shooting_with_tray(&p, &[0], &[1], &att, &defender(4, 5), 12.0, &mut tray);
        assert_eq!(out.rolls.len(), 2, "hit die + save batch only: {:?}", out.rolls);
        assert_eq!(out.rolls[0].count, 1);
        assert_eq!(out.rolls[0].target, 4, "plain Quality 4+ — no rule die, no +1");
        assert_eq!(out.rolls[0].faces, Tray::seeded(seed).roll(1),
            "the tray's first face is the HIT die — nothing came before it");
    }

    /// Gate 12 (Zairetia, Duchies of Vinci, 12" Toxin Bellow at a target 14" away): the book's die is rolled when the unit
    /// shoots, and with no weapon in reach it does not shoot. The table writes "no target in range or sight" and rolls
    /// nothing; the core threw the die anyway. From `PENDING_EPOCH_UPR_NEEDS_SHOT` a volley with no weapon in reach rolls
    /// no Unpredictable die (and a joined hero none for himself); below it the old die stays.
    #[test]
    fn an_unpredictable_shooter_with_no_weapon_in_reach_rolls_no_die() {
        let gun = [ShootProfile { name: "Toxin Bellow".into(), attacks: 1, count: 1, range: 12, ..Default::default() }];
        let rolls_at = |epoch: u32| {
            let att = Ctx {
                unpredictable_shooting: true,
                unpredictable_ap_bonus: 1,
                unpredictable_hit_bonus: 1,
                unpredictable_low_roll_max: 3,
                rules_epoch: epoch,
                ..shooter(4)
            };
            let one = [Shooter { profiles: &gun, keep: &[0], attacks: &[1], att: &att, owner: "Zairetia" }];
            resolve_volley_with_tray(&one, &defender(4, 5), "Target", 14.0, 14.0, true, true, true, true, &mut Tray::seeded(1)).rolls
        };
        assert!(rolls_at(crate::acts::PENDING_EPOCH_UPR_NEEDS_SHOT).is_empty(), "no weapon in reach: no volley, no die");
        let old = rolls_at(crate::acts::PENDING_EPOCH_UPR_NEEDS_SHOT - 1);
        assert_eq!((old.len(), old[0].count), (1, 1), "below the epoch the old die stays: {old:?}");
    }
