use super::super::*;

/// SHO-08e, rules 3.6 Unstoppable EV twin: from `EPOCH_73_V36` the expected-wound
/// path clamps only the ENEMY-side negative hit modifiers; the bearer's own net
/// (its `hit_mod`) stays. At `EPOCH_72_PLAYTEST_RULES` the old single clamp over
/// the whole sum stays byte-identical, and a minus from the target is ignored at
/// both epochs.
mod sho_08e_unstoppable_own_minus_in_ev {
    use super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::combat::profile_ev;

    /// A Quality 4+ rifle or blade at `rules_epoch`; `hit_mod` is the bearer's own net.
    fn gunner(hit_mod: i64, rules_epoch: u32) -> Ctx {
        Ctx { quality: 4, models: 5, hit_mod, rules_epoch, ..Default::default() }
    }

    fn rifle(unstoppable: bool) -> ShootProfile {
        ShootProfile { name: "Rifle".into(), attacks: 10, count: 1, range: 24, unstoppable_ev: unstoppable, ..Default::default() }
    }

    fn blade(unstoppable: bool) -> ShootProfile {
        ShootProfile { name: "Blade".into(), attacks: 10, count: 1, range: 0, unstoppable_ev: unstoppable, ..Default::default() }
    }

    fn stealthy() -> Ctx {
        Ctx { stealth: true, ..defender(4, 5) }
    }

    /// 10 attacks at 4+ into Defense 4+: 5 hits, half saved -> 2.5 wounds.
    const FREE: f64 = 2.5;
    /// 10 attacks at 5+ into Defense 4+: 10/3 hits, half saved.
    const ONE_MINUS: f64 = 10.0 / 3.0 * 0.5;
    /// 10 attacks at 6+ into Defense 4+: 10/6 hits, half saved.
    const TWO_MINUS: f64 = 10.0 / 6.0 * 0.5;

    /// OLD leg: at 72 Unstoppable clamps the whole sum, the own -1 included, so the
    /// volley prices like the free one.
    #[test]
    fn unstoppable_clamps_the_own_minus_at_epoch_72() {
        let att = gunner(-1, EPOCH_72_PLAYTEST_RULES);
        assert!((profile_ev(&rifle(true), 10, &att, &stealthy(), 12.0, false) - FREE).abs() < 1e-9, "72: whole sum clamped");
        assert!((profile_ev(&blade(true), 10, &att, &Ctx { evasive: true, ..defender(4, 5) }, 0.0, true) - FREE).abs() < 1e-9, "72 melee: whole sum clamped");
    }

    /// NEW leg: from 73 the bearer's own -1 survives while the target's Stealth -1 is
    /// ignored, so the volley prices exactly like the own-minus-only one.
    #[test]
    fn unstoppable_keeps_the_own_minus_at_epoch_73() {
        let att = gunner(-1, EPOCH_73_V36);
        let own_only = profile_ev(&rifle(true), 10, &att, &defender(4, 5), 12.0, false);
        assert!((own_only - ONE_MINUS).abs() < 1e-9, "own -1 is real");
        assert!((profile_ev(&rifle(true), 10, &att, &stealthy(), 12.0, false) - own_only).abs() < 1e-9, "73: own kept, enemy ignored");
        let evasive = Ctx { evasive: true, ..defender(4, 5) };
        let melee_own = profile_ev(&blade(true), 10, &att, &defender(4, 5), 0.0, true);
        assert!((melee_own - ONE_MINUS).abs() < 1e-9, "melee own -1 is real");
        assert!((profile_ev(&blade(true), 10, &att, &evasive, 0.0, true) - melee_own).abs() < 1e-9, "73 melee: own kept, enemy ignored");
    }

    /// HOLD: an enemy minus alone is still clamped at both epochs.
    #[test]
    fn unstoppable_still_ignores_enemy_minuses_at_both_epochs() {
        for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
            let att = gunner(0, epoch);
            assert!((profile_ev(&rifle(true), 10, &att, &stealthy(), 12.0, false) - FREE).abs() < 1e-9, "{epoch}: Stealth ignored");
            let evasive = Ctx { evasive: true, ..defender(4, 5) };
            assert!((profile_ev(&blade(true), 10, &att, &evasive, 0.0, true) - FREE).abs() < 1e-9, "{epoch}: Evasive ignored");
        }
    }

    /// CONTROL: without Unstoppable the own and enemy minuses both count at 73.
    #[test]
    fn a_plain_weapon_keeps_both_minuses_at_epoch_73() {
        let att = gunner(-1, EPOCH_73_V36);
        assert!((profile_ev(&rifle(false), 10, &att, &stealthy(), 12.0, false) - TWO_MINUS).abs() < 1e-9);
    }
}
