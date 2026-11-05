use super::*;

    // ---- AI-G4 C-PORT-LEDGE: the move port climbs a container like the table's planner (heights B2, GF p.11) ----

    /// A 6x4 ft board with a long CONTAINER wall on cells [16,9..=20] - x 3..6", z -18..18", too long to walk around inside a
    /// 12" move - whose four OBB edges are in the header's wall list the way `TerrainOverlay.get_wall_segments_world`
    /// writes them. `lone` adds a ruin-style wall at x = 12" with no container ground beside it.
    fn container_board(painted: bool, lone: bool) -> crate::terrain::Terrain {
        let e = |ax: f64, az: f64, bx: f64, bz: f64| [[ax * IN2M, az * IN2M], [bx * IN2M, bz * IN2M]];
        let mut walls = vec![e(3.0, -18.0, 6.0, -18.0), e(6.0, -18.0, 6.0, 18.0), e(6.0, 18.0, 3.0, 18.0), e(3.0, 18.0, 3.0, -18.0)];
        if lone {
            walls.push(e(12.0, -6.0, 12.0, 6.0));
        }
        let cells = if painted {
            (9..=20).map(|j| [16.0, j as f64, crate::terrain::CONTAINER as f64]).collect()
        } else {
            vec![]
        };
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells,
            sandbox: vec![],
            pieces: vec![],
            containers: Vec::new(),
            walls,
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// Unit "a" is ONE 1"-radius model at `x_in`; everything else is parked far to the side.
    fn climber(x_in: f64) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        st.positions[0] = vec![[x_in * IN2M, 0.0, 0.0]];
        Rc::make_mut(&mut st.radii)[0] = vec![IN2M];
        st.wounds[0] = vec![1];
        st.alive[0] = 1;
        statics[0].model_count = 1;
        statics[0].wounds_max = vec![1];
        st.positions[1] = vec![[0.0, 0.0, 18.0 * IN2M]];
        st.positions[2] = vec![[30.0 * IN2M, 0.0, 18.0 * IN2M]; 3];
        (st, statics)
    }

    fn go(kind: i64, x_in: f64, dest_in: f64, t: &crate::terrain::Terrain, epoch: u32) -> (State, ShootResult) {
        let (st, statics) = climber(x_in);
        let action = Action { kind, dest: Some([dest_in * IN2M, 0.0, 0.0]), ..advance_to(dest_in) };
        let seams = Seams { movement: true, rules_epoch: epoch, ..Seams::default() };
        let (mut tray, mut rng) = (Tray::seeded(11), crate::rng::GodotRng::new(0));
        resolve_stochastic_tray_on_board(&statics, &st, &action, t, seams, &mut rng, &mut tray).unwrap()
    }

    fn lands(next: &State) -> (f64, f64) {
        (next.positions[0][0][0] / IN2M, next.positions[0][0][2] / IN2M)
    }

    /// RED on main: a rush from x = 0 toward x = 20 (so the planner's allowance is the whole 12" band) meets the
    /// container's two edges at x = 3 and x = 6. The table's planner climbs both - 3" + 2.5" to the first, 3" + 2.5"
    /// to the second - and spends its last inch on the far side: the band is 7" of ground plus 5" of climb, so the
    /// model rests at (7, 0). The core kept the edges as walls, stopped at the first one or went around it.
    #[test]
    fn a_rush_over_a_container_pays_the_climb_and_lands_beyond_it_at_epoch_73() {
        let (next, _) = go(RUSH, 0.0, 20.0, &container_board(true, false), crate::acts::EPOCH_73_V36);
        let (x, z) = lands(&next);
        assert!((x - 7.0).abs() < 0.15 && z.abs() < 0.15, "landed at ({x:.2}, {z:.2}), want (7, 0) (RED on main)");
    }

    /// Control: below `EPOCH_73_V36` the container edges stay walls, so the same rush never crosses at z = 0.
    #[test]
    fn a_container_edge_stays_a_wall_at_epoch_72() {
        let (next, _) = go(RUSH, 0.0, 20.0, &container_board(true, false), crate::acts::EPOCH_72_PLAYTEST_RULES);
        let (x, z) = lands(&next);
        assert!(!(x > 6.0 && z.abs() < 1.0), "epoch 72 replays the wall: ({x:.2}, {z:.2})");
    }

    /// Control (passes before and after): a wall with NO container ground beside it is not a ledge, at epoch 73 too.
    #[test]
    fn a_wall_without_container_ground_still_blocks_at_epoch_73() {
        let (next, _) = go(RUSH, 4.0, 30.0, &container_board(false, true), crate::acts::EPOCH_73_V36);
        let (x, z) = lands(&next);
        assert!(!(x > 12.0 && z.abs() < 1.0), "a bare wall is not climbed: ({x:.2}, {z:.2})");
    }

    /// RED on main: an advance from x = -1.5 has 6" of band, but the first climb costs 4.5" of ground + 2.5" = 7".
    /// A model never ends mid-climb, and (AIG-L6b) never with its 1" base on the block: the planner halts it at the
    /// edge (x = 2.95) and the gate pulls it back along its route to the first spot its base may rest on, a base and
    /// the 2 mm clearance short of the edge (x = 3 - 1 - 0.079 = 1.92).
    #[test]
    fn a_move_that_cannot_pay_the_climb_halts_just_short_of_the_ledge_at_epoch_73() {
        let (next, _) = go(ADVANCE, -1.5, 8.0, &container_board(true, false), crate::acts::EPOCH_73_V36);
        let (x, z) = lands(&next);
        assert!(x > 1.85 && x < 1.93 && z.abs() < 0.15, "halted at ({x:.2}, {z:.2}), want (1.92, 0) (RED on main)");
    }

    /// RED on main: the climb is a rule the battle log names (rules-must-log), with the inches it cost.
    #[test]
    fn the_climb_is_logged_by_its_book_rule_with_the_inches_it_cost() {
        let (_, shot) = go(RUSH, 0.0, 20.0, &container_board(true, false), crate::acts::EPOCH_73_V36);
        assert!(shot.log.iter().any(|l| l.contains("Terrain") && l.contains("climbs") && l.contains("+5.0")),
            "log: {:?} (RED on main)", shot.log);
    }
