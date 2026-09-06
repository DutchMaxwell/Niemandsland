use super::*;

    // ------------------------------------------- GF v3.5.1: Limited weapons ---

    /// GF v3.5.1 weapon rule Limited — "may only be used once per game": the
    /// Limited Cannon fires alongside the plain Rifle in round 1, then draws
    /// no dice at all in round 2, while the Rifle keeps firing.
    #[test]
    fn a_limited_weapon_fires_once_then_draws_no_dice_the_next_round() {
        let (st, mut statics) = buff_line();
        statics[0].shoot = vec![ShootProfile { limited: true, ..gun("Cannon", 1, 24) }, gun("Rifle", 1, 24)];
        let (round1, shot1) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(
            shot1.rolls.iter().filter(|r| r.kind == "attack").count(), 2,
            "round 1: Cannon and Rifle both fire"
        );
        assert!(round1.limited_used[0].iter().any(|n| n == "Cannon"));

        let (_, shot2) = run_buff(&round1, &statics, &buff_action(Some("b")), 12);
        assert_eq!(
            shot2.rolls.iter().filter(|r| r.kind == "attack").count(), 1,
            "round 2: the spent Cannon draws no dice, the Rifle still fires"
        );
    }
