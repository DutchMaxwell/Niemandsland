use super::*;

    // ------------------------------------------ D1-B4: the shooting order ---

    /// THE DRAW ORDER: hit dice first, then ONE save batch for the whole
    /// defender (main.gd:6448 — not one per model), and the save batch's die
    /// count is the HIT count, so the tray's faces line up with the recorded
    /// ones only if both are right.
    #[test]
    fn a_volley_draws_hit_dice_then_one_save_batch_of_exactly_the_hits() {
        let p = [rifle(6)];
        let mut tray = Tray::seeded(27);
        let want_hits = Tray::seeded(27).roll(6);
        let out = resolve_shooting_with_tray(
            &p, &[0], &[6], &shooter(4), &defender(4, 5), 12.0, &mut tray,
        );
        assert_eq!(out.rolls.len(), 2, "one hit roll, one save batch: {:?}", out.rolls);
        assert_eq!(out.rolls[0].kind, "attack");
        assert_eq!(out.rolls[0].count, 6);
        assert_eq!(out.rolls[0].target, 4, "Quality 4+ at 12\", no modifiers");
        assert_eq!(out.rolls[0].faces, want_hits, "the hit dice are the tray's first six");
        let hits = faces_to_hits(&want_hits, 4) as i64;
        assert_eq!(out.rolls[1].kind, "defense");
        assert_eq!(out.rolls[1].count, hits, "one save die per hit");
        assert_eq!(out.rolls[1].target, 4, "Defense 4+, AP(0)");
        assert!(out.unported.is_empty(), "a plain rifle hits no unported branch");
    }
