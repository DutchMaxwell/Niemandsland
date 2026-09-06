use super::*;

    // ------------------------------------------- block B5: hit & run ---

    /// `len` is the pythagorean SUM `dx² + dz²`: with dx = 0 it is |dz|, so
    /// the normalized direction is exactly [0, -1] and the unit ends 3" from
    /// where it started. `dx² - dz²` is negative here — NaN poisons every
    /// later step and the unit never arrives.
    #[test]
    fn the_flee_length_is_a_pythagorean_sum_never_a_difference() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// Each delta is SQUARED, not doubled: `dz + dz` over a negative dz is
    /// negative, sqrt gives NaN — no 3" step ever lands.
    #[test]
    fn the_flee_length_squares_each_delta_never_doubles_one() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// The zero-length guard at EXACTLY the boundary: a 1e-6 m gap measures
    /// as len == 1e-6 (f32), which is NOT less than the 1e-6 threshold — the
    /// unit must still flee. An `==` guard returns on the boundary value.
    #[test]
    fn a_hair_gap_is_measured_not_guarded_away() {
        let (mut st, statics) = har_line();
        st.positions[3] = vec![[0.0, 0.0, 1e-6f32 as f64]];
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// Same boundary, `<=` form: 1e-6 <= 1e-6 returns too. The original
    /// strictly-below guard lets the hair-gap through and the step lands.
    #[test]
    fn a_gap_at_the_guard_boundary_still_flees() {
        let (mut st, statics) = har_line();
        st.positions[3] = vec![[0.0, 0.0, 1e-6f32 as f64]];
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// The direction DIVIDES dz by len: -9a/9a = -1, a unit vector. A
    /// remainder `-9a % 9a` is -0 — the unit stands still instead of fleeing.
    #[test]
    fn the_flee_direction_divides_the_delta_never_takes_a_remainder() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
        assert_eq!(st.positions[0][0][0], 0.0, "no sideways drift");
    }

    /// And never multiplies: dz·len ≈ -0.0522 m of "direction" drags the
    /// step to a crawl (≈ 4 mm) instead of the full 3".
    #[test]
    fn the_flee_direction_normalizes_to_a_unit_vector() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// The step is ADDED to the position, moving AWAY from the enemy (dir z
    /// is -1): `p[2] += -step`. A `-=` walks TOWARD the enemy (+step).
    #[test]
    fn the_flee_step_moves_away_from_the_enemy() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// `+=` never becomes `*=`: 0 · step is still 0 and the host never moves.
    #[test]
    fn the_flee_step_is_added_never_multiplied_in() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// dir · step_m is the metres-per-inch conversion: (-1)·3" = -0.0762 m.
    /// A division (-1)/0.0762 ≈ -13.1 hurls the unit 13 metres south.
    #[test]
    fn the_flee_step_scales_the_direction_by_the_inches() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// The hero fold moves the joined hero by the SAME away-step: the hero
    /// sits 2" east on the x line, so its z (0) ends at -3". A `-=` walks
    /// the hero INTO the enemy (+step).
    #[test]
    fn the_joined_hero_flees_away_with_the_host() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            Cover::Recorded(None),
            false,
        );
        assert_eq!(st.positions[1][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// `*=` on the hero's position scales its z (0) by step — 0 stays 0 and
    /// the hero never moves, instead of taking the fold's away-step.
    #[test]
    fn the_heros_flee_step_is_added_never_multiplied_in() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            Cover::Recorded(None),
            false,
        );
        assert_eq!(st.positions[1][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// dir·step in the hero loop too: dir + step ≈ -0.92 m of step.
    #[test]
    fn the_heros_flee_step_scales_the_direction_by_the_inches() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            Cover::Recorded(None),
            false,
        );
        assert_eq!(st.positions[1][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// And dir/step ≈ -13.1 m — the hero teleports instead of fleeing 3".
    #[test]
    fn the_heros_flee_direction_stays_a_unit_vector() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            Cover::Recorded(None),
            false,
        );
        assert_eq!(st.positions[1][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }
