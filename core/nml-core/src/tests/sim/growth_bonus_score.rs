use super::*;

    // ------------------------------------ block B7: the growth bonus ---

    /// The bonus is COMPUTED from the markers: zero markers, zero bonus —
    /// and four markers is the exact (18, 10), not a constant (1, 0).
    #[test]
    fn the_growth_bonus_is_computed_never_constant() {
        let (st, statics) = growth_line(0);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (0, 0), "no markers, no bonus");
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The AP per-marker rate MULTIPLIES the marker count: 2 · 4, not 2 / 4.
    #[test]
    fn the_ap_rate_multiplies_the_markers() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The AP per-two rate MULTIPLIES the pair count: 5 · 2, not 5 / 2.
    #[test]
    fn the_ap_pair_rate_multiplies_the_pairs() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The pair count HALVES the markers: 4 / 2 = 2 pairs, not 4 % 2 = 0.
    #[test]
    fn the_ap_pair_count_halves_the_markers() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The AP term ACCUMULATES by addition from zero: `-=` would leave -18.
    #[test]
    fn the_ap_bonus_accumulates_by_addition() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// And addition, not multiplication: 0 · 18 stays 0 — no bonus at all.
    #[test]
    fn the_ap_bonus_starts_at_zero_and_adds() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The two hit facets ADD together: 4 + 6 = 10, not 4 - 6 = -2.
    #[test]
    fn the_hit_facets_add_together() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// Addition, not multiplication: 4 · 6 = 24 is not the hit bonus.
    #[test]
    fn the_hit_facets_add_never_multiply() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The hit per-marker rate MULTIPLIES the markers: 1 · 4, not 1 + 4.
    #[test]
    fn the_hit_rate_multiplies_the_markers() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// Nor divides: 1 / 4 = 0 — the markers would count for nothing.
    #[test]
    fn the_hit_rate_divides_nothing() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The hit per-two rate MULTIPLIES the pairs: 3 · 2, not 3 + 2.
    #[test]
    fn the_hit_pair_rate_multiplies_the_pairs() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// Nor divides: 3 / 2 = 1 pair's worth instead of 2.
    #[test]
    fn the_hit_pair_count_halves_the_markers() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The hit pair count HALVES the markers: 4 / 2, not 4 % 2 (zero).
    #[test]
    fn the_hit_pair_count_is_a_half_never_a_remainder() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// And never doubles: 4 · 2 = 8 pairs would hand out 24 hit, not 6.
    #[test]
    fn the_hit_pair_count_is_a_half_never_a_double() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }
