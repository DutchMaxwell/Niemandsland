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
