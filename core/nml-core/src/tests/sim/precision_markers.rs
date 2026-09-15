use super::*;

    // --------------- wave 6: the PRECISION MARKERS trio (epoch 61) ---

    /// PRECISION_TEXT_2026-09-15 §3-§5: the three placeholder "Utility Buff"
    /// entries (Precision Spotter / Tag / Target) carried `hit_mod: "X"`/"Y"
    /// string placeholders nobody could read, and `acts.rs` said so. From the
    /// FROZEN `EPOCH_61_PRECISION_MARKERS` the trio carries the real shape
    /// (`bonus` + `markers`) and the two seams exist:
    ///   * placement — `sim::tray_precision_markers`: the Spotter (once per
    ///     activation, one 4+ tray draw, 30", pool `State::spot_markers`)
    ///     fires at the END of the activation; Tag (24") and Target (18")
    ///     in the pre-attack slot, once per game.
    ///   * consumption — the volley seam's take-all spend (+1 to hit per
    ///     removed marker; Target rides a PERSISTENT attackers-side record,
    ///     never spent — the book text has no removal clause).
    ///
    /// The OLD leg is pinned at the landed predecessor constant (never a
    /// literal — re-point it at rebase): below the gate the placeholders
    /// parse as hit_mod 0, nothing stamps, every recorded game replays
    /// byte-exact.
    const OLD_EPOCH: u32 = crate::acts::EPOCH_60_GROUNDED_STEALTH;

    /// The Spotter fixture: buff_line's shooter carrying "Precision Spotter"
    /// (bonus per_removed_marker, ONE marker per placement, 4+ on the tray,
    /// 30", LOS). Seed 1's first tray face is a 4.
    fn spotter_line() -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = buff_line();
        statics[0].shoot = vec![gun("Rifle", 6, 24)];
        statics[0].utility_buffs = vec![UtilityBuff {
            bonus: "per_removed_marker".into(),
            markers: 1,
            place_roll: 4,
            range_in: 30.0,
            target: "enemy".into(),
            ..ub("Precision Spotter")
        }];
        (st, statics)
    }

    /// The Target fixture: 2 markers per placement (X = 2), once per game,
    /// 18" — the SAME buff_line 12" pair is inside every one of the ranges.
    fn target_line() -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = buff_line();
        statics[0].shoot = vec![gun("Rifle", 1, 24)];
        statics[0].utility_buffs = vec![UtilityBuff {
            bonus: "per_placed_marker".into(),
            markers: 2,
            uses_per_game: 1,
            range_in: 18.0,
            target: "enemy".into(),
            ..ub("Precision Target")
        }];
        (st, statics)
    }

    /// The Tag fixture: 2 markers per placement (the rating read), once per
    /// game, 24" — the pre-attack slot's own volley spends them.
    fn tag_line_h() -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = buff_line();
        statics[0].shoot = vec![gun("Rifle", 1, 24)];
        statics[0].utility_buffs = vec![UtilityBuff {
            bonus: "per_removed_marker".into(),
            markers: 2,
            uses_per_game: 1,
            range_in: 24.0,
            target: "enemy".into(),
            ..ub("Precision Tag")
        }];
        (st, statics)
    }

    fn spot_hold() -> Action {
        // A bare HOLD draws NOTHING before the spot beat (no weapons that
        // fire, no specs) — the spot roll is the tray's first draw.
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None, }
    }

    fn run_act(st: &State, statics: &[UnitStatic], action: &Action, seed: i64, epoch: u32) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch: epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    /// A Spotter marker placed on a forced 4 lowers the next friendly
    /// attack's to-hit target by one and is consumed with the exchange.
    #[test]
    fn a_spotter_marker_on_a_forced_four_gives_the_next_friendly_attack_plus_one() {
        let (st, statics) = spotter_line();
        let (spotted, shot1) = run_act(&st, &statics, &spot_hold(), 1, crate::acts::EPOCH_61_PRECISION_MARKERS);
        assert_eq!(spotted.spot_markers[2], 1, "the 4+ placement landed one marker");
        assert_eq!(spotted.spot_round[0], st.round, "the once-per-activation stamp burned");
        assert!(
            shot1.log.iter().any(|l| l.starts_with("Precision Spotter: a marks b (1 marker")),
            "rules-must-log: the placement line, main.gd:10077 shape — got {:#?}",
            shot1.log
        );

        // The next friendly volley removes the marker for +1 to hit — the
        // recorded attack target drops by one, the pool spends whole, and
        // the same round's stamp refuses a second spot.
        let (next2, volley) = run_act(&spotted, &statics, &buff_action(Some("b")), 13, crate::acts::EPOCH_61_PRECISION_MARKERS);
        assert_eq!(volley.rolls[0].target, 3, "Quality 4 + one removed marker");
        assert!(volley.log.iter().any(|l| l.starts_with("Precision Spotter: 1 marker removed")),
            "rules-must-log: the consumption line — got {:#?}", volley.log);
        assert_eq!(next2.spot_markers[2], 0, "the removal consumed the pool");
        assert_eq!(next2.spot_round[0], st.round, "once per activation: no re-spot this round");
    }

    /// A Precision Target with 2 markers: EVERY friendly attack against the
    /// marked unit rides +2, on BOTH legs, and nothing is ever spent (the
    /// text has no removal clause — the bonus persists for the whole game).
    #[test]
    fn a_target_with_two_markers_gives_every_friendly_attack_plus_two() {
        let (st, statics) = target_line();
        let (next, volley) = run_act(&st, &statics, &buff_action(Some("b")), 13, crate::acts::EPOCH_61_PRECISION_MARKERS);
        assert_eq!(next.buffs[2].len(), 1, "the persistent record landed once");
        assert_eq!(next.buffs[2][0].hit_mod, 2);
        assert!(next.buffs[2][0].attackers);
        assert!(!next.buffs[2][0].once);
        assert_eq!(next.precision_used[0], vec!["Precision Target".to_string()]);
        assert_eq!(volley.rolls[0].target, 2, "Quality 4 + two markers");
        assert!(
            volley.log.iter().any(|l| l.starts_with("Precision Target: a places 2 markers on b")),
            "rules-must-log: the placement names the rule and the count — got {:#?}",
            volley.log
        );

        // The bonus is NOT consumable: a second volley still rides +2, and a
        // spent-style pass places nothing new (once per game, never reset).
        let (next2, volley2) = run_act(&next, &statics, &buff_action(Some("b")), 13, crate::acts::EPOCH_61_PRECISION_MARKERS);
        assert_eq!(volley2.rolls[0].target, 2, "the bonus persists for every friendly attack");
        assert_eq!(next2.buffs[2].len(), 1, "no second placement this game");
        assert_eq!(next2.precision_used[0], vec!["Precision Target".to_string()]);
    }

    /// The OLD leg by the FROZEN CONSTANT immediately below the bump: below
    /// the gate nothing stamps, nothing folds, the plain roll stands — the
    /// shape every already recorded game replays with.
    #[test]
    fn at_the_landed_predecessor_epoch_nothing_places_and_the_roll_stays_plain() {
        let (st, statics) = spotter_line();
        let (next, shot) = run_act(&st, &statics, &spot_hold(), 1, OLD_EPOCH);
        assert_eq!(next.spot_markers[2], 0, "the old leg places nothing");
        assert_eq!(next.spot_round[0], -1);
        assert!(shot.rolls.is_empty(), "no spot roll burns a draw below the gate");
        let (_, volley) = run_act(&st, &statics, &buff_action(Some("b")), 13, OLD_EPOCH);
        assert_eq!(volley.rolls[0].target, 4, "the plain Quality roll, unmodified");
        assert!(volley.log.iter().all(|l| !l.contains("Precision")));
    }

    /// Precision Tag — the once-per-game pool at its own params (24", the
    /// rating count): one activation tags and the SAME volley spends the
    /// pool whole; a preset latch keeps the second activation quiet.
    #[test]
    fn a_tag_with_two_markers_drains_whole_on_the_first_friendly_volley() {
        let (st, statics) = tag_line_h();
        let (next, volley) = run_act(&st, &statics, &buff_action(Some("b")), 13, crate::acts::EPOCH_61_PRECISION_MARKERS);
        assert_eq!(volley.rolls[0].target, 2, "Quality 4 + two removed markers");
        assert_eq!(next.tag_markers[2], 0, "the pool spends whole");
        assert_eq!(next.precision_used[0], vec!["Precision Tag".to_string()]);

        let (next2, volley2) = run_act(&next, &statics, &buff_action(Some("b")), 13, crate::acts::EPOCH_61_PRECISION_MARKERS);
        assert_eq!(volley2.rolls[0].target, 4, "once per game: no second placement");
        assert_eq!(next2.tag_markers[2], 0);
    }
