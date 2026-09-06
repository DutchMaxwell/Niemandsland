use super::*;

    // ---------------------------------------------- block C5: Instinctive ---

    /// (a) A carrier attacking the CLOSEST enemy hits on one better — the +1
    /// rides the strike phase's `hit_mod` fold to the melee hit target.
    #[test]
    fn instinctive_hits_one_better_when_the_target_is_the_closest_enemy() {
        assert_eq!(striker_hit_target(12.0 * IN2M), 3, "Quality 4 + Instinctive's +1");
    }

    /// (b) A second enemy 1" closer forfeits the +1 — the pick stands, the
    /// hit target falls back to the plain Quality (main.gd:5792-5793).
    #[test]
    fn instinctive_is_forfeited_when_a_second_enemy_is_closer() {
        assert_eq!(striker_hit_target(9.0 * IN2M), 4, "a rival 1\" inside the target");
    }

    /// (c) The half-inch band's own boundary: a rival at EXACTLY d - 0.5" is
    /// a tie, not closer — the bonus stands. RED when the band is written
    /// `<=` instead of `<`, or the half inch is dropped.
    #[test]
    fn instinctive_survives_a_rival_on_the_half_inch_band_boundary() {
        assert_eq!(striker_hit_target(9.5 * IN2M), 3, "9.5\" ties inside the band");
    }
