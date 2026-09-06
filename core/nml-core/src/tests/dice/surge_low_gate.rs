use super::*;

    // ------------------------------------- block B6 mutant killer: the LOW gate ---

    /// Primal Boost's LOW surge (`surge_attack_low < 6`, main.gd:4417-4443):
    /// the successful unmodified 5s are extra attack dice ON TOP of the 6s —
    /// `xn` ADDS the 5-count, so one 6 and two 5s draw three extras, not the
    /// `6s - 5s` of an inverted sign, which would draw nothing at all.
    #[test]
    fn a_low_surge_adds_the_fives_to_the_sixes_never_subtracts() {
        let p = [ShootProfile { surge_attack: true, surge_attack_low: 5, ..rifle(8) }];
        let mut tray = Tray::seeded(5);
        let mut rolls = Vec::new();
        let extra = surge_attack_hits(&p[0], &[6, 5, 5], 4, "shooter", &mut tray, &mut rolls);
        assert_eq!(rolls.len(), 1, "one extra-attack-die roll: {:?}", rolls);
        assert_eq!(rolls[0].count, 3, "one 6 plus two 5s = three extra dice");
        assert_eq!(rolls[0].target, 4, "the extras roll at the weapon's own target");
        let want = Tray::seeded(5).roll(3);
        assert_eq!(extra, faces_to_hits(&want, 4) as i64, "the extras are the tray's next three");
    }
