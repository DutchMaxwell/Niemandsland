use super::*;
use crate::acts::EPOCH_94_PARITY_BATCH;

    // Heightfield plan step 12: the activation's one commit point (`finish_activation`) settles every model a step moved
    // in x/z only. The Hit & Run step is the plainest such writer: on a board without the move port it is a rigid 3"
    // shift that keeps the model's y.

    /// An 8 x 8 board of 3 in cells (board-centred, x and z from -12 to 12 in): the column x 0..3 is a 6 in roof.
    fn roof_column() -> crate::terrain::Terrain {
        crate::terrain::tier_board_for_test(8, 8, (0..64).map(|i| if i % 8 == 4 { 6.0 } else { 0.0 }).collect(), Vec::new())
    }

    /// `a` (two models, x 0.00 and 0.02 in) stands on the roof; its Hit & Run step goes 3 in away from `b`, off the roof
    /// edge onto the ground. Red before: the models kept y 6 in over the ground (the invariant of
    /// `rollout::height_invariant` is the same sentence, played over whole games).
    #[test]
    fn a_hit_and_run_step_off_a_roof_ends_on_the_ground() {
        let (mut st, mut statics) = buff_line();
        // the joined hero carries the family too: from `EPOCH_73_V36` a mixed formation takes no step
        statics[0].hit_and_run_active = true;
        statics[1].hit_and_run_active = true;
        for p in st.positions[0].iter_mut() {
            p[1] = 6.0 * IN2M;
        }
        // the target stands 9 in away to the west, in plain sight of the roof's west rim
        st.positions[2] = vec![[-9.0 * IN2M, 0.0, 0.0], [-9.02 * IN2M, 0.0, 0.0], [-9.04 * IN2M, 0.0, 0.0]];
        let run = |t: &crate::terrain::Terrain, epoch: u32| {
            let mut tray = Tray::seeded(11);
            let mut rng = crate::rng::GodotRng::new(0);
            let seams = Seams { rules_epoch: epoch, ..Seams::default() };
            resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), t, seams, &mut rng, &mut tray).unwrap().0
        };
        let at_gate = run(&roof_column(), EPOCH_94_PARITY_BATCH);
        for p in &at_gate.positions[0] {
            assert!(p[0] >= 3.0 * IN2M - 1e-9, "stepped off the roof, east: x {:.3} in", p[0] / IN2M);
            assert_eq!(p[1], 0.0, "and stands on the ground there");
        }
        assert_eq!(at_gate.positions[1], st.positions[1], "a unit that did not move is not touched");
        // one epoch below the gate, and a board with no tiers at the gate: the step keeps its y as before
        for next in [run(&roof_column(), EPOCH_94_PARITY_BATCH - 1), run(&crate::terrain::Terrain::default(), EPOCH_94_PARITY_BATCH)] {
            assert!(next.positions[0].iter().all(|p| p[0] > 0.0 && p[1] == 6.0 * IN2M), "{:?}", next.positions[0]);
        }
    }

    /// Heightfield plan step 15: the core never decides a marker's height - a captured marker keeps the table's y - except
    /// when the activation moves it: a relic dropped by its carrier (`mission::drop_carried`) lands ~1 in away at the
    /// CARRIER's y. Here the carrier stood on the 6 in roof, the relic lands off the roof edge: it stands on the ground.
    /// Red before: the relic hung at 6 in over the ground. A marker the activation did not move is not touched.
    #[test]
    fn a_dropped_relic_lands_at_its_tier_height() {
        let (parent, _) = buff_line();
        let mut parent = parent;
        let (on_roof, away) = ([1.0 * IN2M, 6.0 * IN2M, 0.0], [5.0 * IN2M, 0.0, 0.0]);
        parent.objectives = vec![crate::state::Objective { pos: on_roof, owner: 0 }, crate::state::Objective { pos: away, owner: 0 }];
        let mut next = parent.clone();
        next.objectives[0].pos = [-IN2M, 6.0 * IN2M, 0.0]; // dropped 2 in west of where it was, still at the carrier's y
        let t = roof_column();
        let mut settled = next.clone();
        settle_on_surface(&mut settled, &parent, Cover::Board(&t), EPOCH_94_PARITY_BATCH);
        assert_eq!(settled.objectives[0].pos[1], 0.0, "the dropped relic stands on the ground");
        assert_eq!(settled.objectives[1].pos, away, "a marker that did not move is left as captured");
        let mut below = next.clone();
        settle_on_surface(&mut below, &parent, Cover::Board(&t), EPOCH_94_PARITY_BATCH - 1);
        assert_eq!(below.objectives[0].pos[1], 6.0 * IN2M, "below the gate nothing changes");
    }
