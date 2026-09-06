use super::*;

    // --------------------------------------------- NML-1152 S3: plain moves ---

    /// RED for DEFECT_LEDGER row 12: a plain ADVANCE through DANGEROUS terrain
    /// that kills half or more of the unit must draw a REAL morale die from the
    /// tray at the END of the activation (GF v3.5.1 p.10 General Morale Tests) —
    /// before this port, the wound landed and `shot.mark("dangerous_end_morale")`
    /// fired, but main.gd:1092-1098's actual test was "not ported": no die was
    /// ever drawn and `next.shaken` never moved.
    #[test]
    fn dangerous_terrain_losses_at_half_or_more_draw_a_morale_die() {
        let (st, statics) = dangerous_line();
        let t = dangerous_bar_board();
        // Seeds are searched, not guessed (same convention as the RED in
        // `the_die_count_takes_the_ratio_or_the_bearer_cap` above): the
        // dangerous roll is 4 dice, and a face of 1 is what wounds — this seed's
        // first 4 faces give >= 2 ones, so >= half of the 4 models die.
        let seed = (1i64..)
            .find(|&s| Tray::seeded(s).roll(4).iter().filter(|&&f| f == 1).count() >= 2)
            .unwrap();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(100.0), &t,
            Seams { dangerous_end_morale: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(next.alive[0] > 0 && next.alive[0] <= 2, "setup didn't kill >= half: {}", next.alive[0]);
        // Two "a"-owned rolls on the tray: the dangerous test (4 dice), THEN
        // the morale test (1 die) — RED without the port, which draws only
        // the first and never touches `next.shaken`.
        let a_rolls: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| r.owner == "a").collect();
        assert_eq!(a_rolls.len(), 2, "{:?}", shot.rolls);
        assert_eq!((a_rolls[0].count, a_rolls[1].count), (4, 1));
    }

    /// The same crossing with losses BELOW half: no morale die is drawn, and
    /// only the dangerous roll appears on the tray.
    #[test]
    fn dangerous_terrain_losses_below_half_draw_no_morale_die() {
        let (st, statics) = dangerous_line();
        let t = dangerous_bar_board();
        let seed = (1i64..)
            .find(|&s| Tray::seeded(s).roll(4).iter().filter(|&&f| f == 1).count() == 1)
            .unwrap();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(100.0), &t,
            Seams { dangerous_end_morale: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.alive[0], 3, "setup didn't kill exactly one of four: {}", next.alive[0]);
        let a_rolls: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| r.owner == "a").collect();
        assert_eq!(a_rolls.len(), 1, "no morale die below half: {:?}", shot.rolls);
    }

    /// DEFECT_LEDGER #12 knob: `Seams::default()` — every corpus recorded
    /// before this rule shipped, `dangerous_end_morale` absent and false —
    /// replays with the OLD (bug-present) behaviour: the wound lands, the
    /// mark fires, no die is drawn, even at >= half losses. This is what
    /// keeps the frozen gen0 self-play snapshot byte-exact.
    #[test]
    fn dangerous_terrain_losses_draw_no_morale_die_with_the_knob_off() {
        let (st, statics) = dangerous_line();
        let t = dangerous_bar_board();
        let seed = (1i64..)
            .find(|&s| Tray::seeded(s).roll(4).iter().filter(|&&f| f == 1).count() >= 2)
            .unwrap();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(100.0), &t, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!(next.alive[0] > 0 && next.alive[0] <= 2, "setup didn't kill >= half: {}", next.alive[0]);
        let a_rolls: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| r.owner == "a").collect();
        assert_eq!(a_rolls.len(), 1, "knob off must not draw the morale die: {:?}", shot.rolls);
    }

    /// S3 — a NON-charge move goes through `mv::step::plain_move` once
    /// `movement` is on: the unit routes AROUND the forest instead of walking
    /// its whole 6" band straight through it, so the models rest somewhere the
    /// rigid translation never puts them.
    #[test]
    fn a_plain_advance_lands_through_the_solver_under_the_movement_seam() {
        let (st, statics) = buff_line();
        let t = forest_bar_board();
        let rigid = resolve_on_board(&statics, &st, &advance_to(8.0), &t, Seams::default())
            .unwrap();
        let solved = resolve_on_board(
            &statics, &st, &advance_to(8.0), &t, Seams { movement: true, ..Seams::default() },
        )
        .unwrap();
        // The rigid arm spends the full band on the straight line, every model
        // the same delta — through the forest.
        for (got, before) in rigid.positions[0].iter().zip(st.positions[0].iter()) {
            assert!((got[0] - (before[0] + 6.0 * IN2M)).abs() < 1e-6, "rigid {got:?}");
        }
        let gap_in = solved.positions[0]
            .iter()
            .zip(rigid.positions[0].iter())
            .map(|(a, b)| ((a[0] - b[0]).powi(2) + (a[2] - b[2]).powi(2)).sqrt() / IN2M as f64)
            .fold(0.0f64, f64::max);
        assert!(gap_in > 0.5, "the solver landed on the rigid answer, gap {gap_in}\"");
    }

    /// The RED for that routing: `move_rigid` puts ADVANCE and RUSH back on the
    /// rigid arm with `movement` still on, and every model must return to the
    /// straight-line answer to the digit. Without it the assertion above could
    /// be reading any other difference the seam makes.
    #[test]
    fn the_move_rigid_red_returns_a_plain_advance_to_the_straight_line() {
        let (st, statics) = buff_line();
        let t = forest_bar_board();
        let rigid = resolve_on_board(&statics, &st, &advance_to(8.0), &t, Seams::default())
            .unwrap();
        let red = resolve_on_board(
            &statics,
            &st,
            &advance_to(8.0),
            &t,
            Seams { movement: true, move_rigid: true, ..Seams::default() },
        )
        .unwrap();
        assert_eq!(red.positions, rigid.positions);
    }

    /// NML-1152 B14 step 1 — the table RECORDS the Bounding die, the twin
    /// REPLAYS it: a `traced` draw of `faces:[2], plus:1` grows the 6" band by
    /// exactly 2+1 = 3" for THIS act (RED for the arm: comment out the
    /// `bounding_bonus_in` addend in `resolve_with` and this falls to 6"),
    /// and the resolver names it in the log. Every act with no `traced` entry
    /// (every corpus recorded before this) reads the plain 6" band, unchanged.
    #[test]
    fn a_recorded_bounding_trace_grows_the_band_by_its_faces_plus_the_flat_and_logs_it() {
        use crate::io::TracedRoll;
        let (st, statics) = buff_line();
        let terrain = crate::terrain::Terrain::default();
        let traced_advance = Action {
            traced: Some(vec![TracedRoll { tag: "bounding_d3".into(), faces: vec![2], plus: 1 }]),
            ..advance_to(20.0)
        };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &traced_advance, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!((next.positions[0][0][0] - (st.positions[0][0][0] + 9.0 * IN2M as f64)).abs() < 1e-6);
        assert!(shot.log.iter().any(|l| l.contains("Bounding") && l.contains("+3")), "{:?}", shot.log);

        // No trace on the act: the plain 6" band, no log line — every pre-B14 corpus's own reading.
        let mut tray2 = Tray::seeded(11);
        let mut rng2 = crate::rng::GodotRng::new(0);
        let (plain_next, plain_shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(20.0), &terrain, Seams::default(), &mut rng2, &mut tray2,
        )
        .unwrap();
        assert!((plain_next.positions[0][0][0] - (st.positions[0][0][0] + 6.0 * IN2M as f64)).abs() < 1e-6);
        assert!(plain_shot.log.is_empty());
    }
