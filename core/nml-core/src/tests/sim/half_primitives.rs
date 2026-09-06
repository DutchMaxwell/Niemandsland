use super::*;

    // -------------------------------- block C1: the two half-primitives ---

    /// (a) solo_controller.gd:9667 — a "Hit & Run Shooter" carrier that SHOT
    /// (`after_shoot = true`) kites 3" away from the nearest enemy and takes
    /// the shared per-round stamp (:9685), though the full "Hit & Run" gate
    /// would refuse it (no full-rule name on the profile).
    #[test]
    fn a_shooter_carrier_that_shot_steps_3_inches_and_stamps_the_round() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_shooter_active = true;
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), true);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
        assert_eq!(st.hit_and_run_round[0], st.round);
    }

    /// (b) THE RED — the same Shooter carrier after a CHARGE is on the WRONG
    /// half (the table's pick is `"Hit & Run Shooter" if after_shoot else
    /// "Hit & Run Fighter"`, :9667): no step, no stamp. This is the test that
    /// fails the moment the `after_shoot` gate is dropped.
    #[test]
    fn a_shooter_carrier_after_a_charge_is_on_the_wrong_half() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_shooter_active = true;
        let before = st.positions[0].clone();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0], before);
        assert_eq!(st.hit_and_run_round[0], -1);
    }

    /// (c) the mirror: a "Hit & Run Fighter" carrier moves after a CHARGE
    /// (the melee leg, `after_shoot = false`) and does NOT after a shot —
    /// each half fires on its own trigger and its own EXACT name only.
    #[test]
    fn a_fighter_carrier_moves_after_a_charge_never_after_a_shot() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_fighter_active = true;
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);

        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_fighter_active = true;
        let before = st.positions[0].clone();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), true);
        assert_eq!(st.positions[0], before);
        assert_eq!(st.hit_and_run_round[0], -1);
    }
