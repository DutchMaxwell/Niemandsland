//! Rules 3.6 row BG-03a tests (unstable ruins, core) for the sim module; owned by lane ux.
use super::*;

    use crate::terrain::{CellParams, PlainTerrain, Terrain};

    /// The school table (6x4 ft, 3" grid) with ONE painted cell. In `school`'s
    /// frame cell (14, 15) is the x in [-3", 0"), z in [0", 3") cell the LOS
    /// tests already use.
    fn one_cell_board(kind: i32) -> Terrain {
        Terrain::build(&PlainTerrain {
            cells: vec![[14.0, 15.0, kind as f64]],
            sandbox: Vec::new(),
            pieces: Vec::new(),
            walls: vec![],
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    fn at(x_in: f64, z_in: f64) -> [f64; 3] {
        [x_in * IN2M, 0.0, z_in * IN2M]
    }

    /// `dangerous_line` with units 1..3 cleared: ONE four-model unit (host
    /// only) standing in a column inside the painted cell's z band, so a run
    /// along +x goes into and through that cell.
    fn solo_line() -> (State, Vec<UnitStatic>) {
        let (mut st, statics) = dangerous_line();
        Rc::make_mut(&mut st.attached)[0].clear();
        Rc::make_mut(&mut st.attached_to)[1] = None;
        for u in 1..4 {
            st.positions[u].clear();
            Rc::make_mut(&mut st.radii)[u].clear();
            st.alive[u] = 0;
        }
        st.positions[0] = (0..4).map(|k| at(-5.0, 1.0 + 0.5 * k as f64)).collect();
        Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 4];
        (st, statics)
    }

    fn set_flying(st: &mut State) {
        let mut p = st.profiles.list[0].clone();
        p.special_rules.push("Flying".into());
        st.profiles = Rc::new(crate::state::Profiles { list: vec![p], index: Default::default() });
    }

    /// The landing the unit gets when it is ordered `run_in` inches along +x
    /// through the painted cell.
    fn run(st: &State, t: &Terrain, run_in: f64, epoch: u32) -> crate::mv::step::Landing {
        let start = crate::geom::centre(&st.positions[0]);
        let dest = [start[0] + (run_in * IN2M) as f32, 0.0, start[2]];
        (crate::mv::step::MoveRules { rules_epoch: epoch })
            .plain_move(st, t, 0, dest, run_in, false, true, crate::mv::FAST_PLANNER_GUARD)
            .expect("the board is real and the unit has models")
    }

    /// The Dangerous dice the unit draws for that landing, with the whole-unit
    /// test of UX-20/UX-21 already on main.
    fn dice_of(
        st: &State,
        statics: &[UnitStatic],
        t: &Terrain,
        land: &crate::mv::step::Landing,
        epoch: u32,
    ) -> i64 {
        let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
        let mut shot = crate::dice::ShootResult::default();
        dangerous_dice(statics, st, st, 0, seams, Some(land), Cover::Board(t), &mut shot)
    }

    /// Control: an 8" rush through a RUINS cell is no Dangerous terrain below
    /// 3.6 — the flag stays down and the unit draws no die.
    #[test]
    fn ruin_rush_raises_no_dangerous_flag_at_epoch_72() {
        let (st, statics) = solo_line();
        let t = one_cell_board(crate::terrain::RUINS);
        let land = run(&st, &t, 8.0, crate::acts::EPOCH_72_PLAYTEST_RULES);
        assert!(land.dangerous.iter().all(|&d| !d), "flags {land:?}");
        assert_eq!(dice_of(&st, &statics, &t, &land, crate::acts::EPOCH_72_PLAYTEST_RULES), 0);
    }

    /// The row: the same 8" rush into a RUINS cell flags every mover at 3.6, so
    /// the whole unit takes ONE test and rolls its four wounds left.
    #[test]
    fn ruin_rush_raises_a_dangerous_test_at_epoch_73() {
        let (st, statics) = solo_line();
        let t = one_cell_board(crate::terrain::RUINS);
        let land = run(&st, &t, 8.0, crate::acts::EPOCH_73_V36);
        assert!(land.dangerous.iter().all(|&d| d), "flags {land:?}");
        assert_eq!(dice_of(&st, &statics, &t, &land, crate::acts::EPOCH_73_V36), 4);
    }

    /// A 6" Advance into the same cell is not longer than 6" and never flags.
    #[test]
    fn ruin_advance_raises_no_dangerous_flag_at_epoch_72() {
        let (st, _) = solo_line();
        let t = one_cell_board(crate::terrain::RUINS);
        let land = run(&st, &t, 6.0, crate::acts::EPOCH_72_PLAYTEST_RULES);
        assert!(land.dangerous.iter().all(|&d| !d), "flags {land:?}");
    }

    #[test]
    fn ruin_advance_raises_no_dangerous_flag_at_epoch_73() {
        let (st, _) = solo_line();
        let t = one_cell_board(crate::terrain::RUINS);
        let land = run(&st, &t, 6.0, crate::acts::EPOCH_73_V36);
        assert!(land.dangerous.iter().all(|&d| !d), "flags {land:?}");
    }

    /// Flying models ignore terrain effects while moving (p.13), at any length.
    #[test]
    fn flying_ruin_rush_raises_no_dangerous_flag_at_epoch_73() {
        let (mut st, statics) = solo_line();
        set_flying(&mut st);
        let t = one_cell_board(crate::terrain::RUINS);
        let land = run(&st, &t, 8.0, crate::acts::EPOCH_73_V36);
        assert!(land.dangerous.iter().all(|&d| !d), "flags {land:?}");
        assert_eq!(dice_of(&st, &statics, &t, &land, crate::acts::EPOCH_73_V36), 0);
    }

    /// Control: a DANGEROUS cell keeps flagging at both epochs.
    #[test]
    fn dangerous_cell_rush_still_flags_at_epoch_72() {
        let (st, _) = solo_line();
        let t = one_cell_board(crate::terrain::DANGEROUS);
        let land = run(&st, &t, 8.0, crate::acts::EPOCH_72_PLAYTEST_RULES);
        assert!(land.dangerous.iter().all(|&d| d), "flags {land:?}");
    }

    #[test]
    fn dangerous_cell_rush_still_flags_at_epoch_73() {
        let (st, _) = solo_line();
        let t = one_cell_board(crate::terrain::DANGEROUS);
        let land = run(&st, &t, 8.0, crate::acts::EPOCH_73_V36);
        assert!(land.dangerous.iter().all(|&d| d), "flags {land:?}");
    }
