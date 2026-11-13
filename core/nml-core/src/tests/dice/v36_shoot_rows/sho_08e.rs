use super::super::*;

/// SHO-08e, rules 3.6 Unstoppable EV twin: from `EPOCH_73_V36` the expected-wound
/// path clamps its non-own sum exactly like the resolver's `m - own` clamp, so a
/// bearer's spell net (`hit_mod`) joins the enemy side. At
/// `EPOCH_72_PLAYTEST_RULES` the old single clamp over the whole sum stays
/// byte-identical, and a minus from the target is ignored at both epochs.
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

    /// NEW leg: from 73 the estimate clamps the bearer's spell net with the enemy
    /// side, exactly like the resolver's `m - own` clamp: a lone spell -1 is dropped
    /// (target 4, FREE) on the shooting and the melee path.
    #[test]
    fn the_estimate_clamps_the_spell_net_like_the_resolver_at_epoch_73() {
        let att = gunner(-1, EPOCH_73_V36);
        assert!((profile_ev(&rifle(true), 10, &att, &defender(4, 5), 12.0, false) - FREE).abs() < 1e-9, "shooting: a lone -1 spell is clamped");
        let evasive = Ctx { evasive: true, ..defender(4, 5) };
        assert!((profile_ev(&blade(true), 10, &att, &evasive, 0.0, true) - FREE).abs() < 1e-9, "melee: a lone -1 spell is clamped");
    }

    /// RED -> GREEN: the estimate prices the same net the resolver folds. A +2 spell
    /// net against a -1 Stealth target resolves at +1 (target 3); the estimate must
    /// price +1, not +2.
    #[test]
    fn the_estimate_matches_the_resolver_for_a_spell_net_inside_the_enemy_side() {
        let p = rifle(true);
        let spell_two = Ctx { quality: 4, models: 5, hit_mod: 2, rules_epoch: EPOCH_73_V36, ..Default::default() };
        let one = [Shooter { profiles: std::slice::from_ref(&p), keep: &[0], attacks: &[10], att: &spell_two, owner: "Gunners" }];
        let mut tray = Tray::seeded(7);
        let out = resolve_volley_leg(&one, &stealthy(), "Target", 12.0, 12.0, true, true, true, true, true, false, &|_| false, &|_, _| None, &mut tray);
        let resolved = out.rolls.iter().find(|r| r.kind == "attack").expect("an attack die").target;
        assert_eq!(resolved, 3, "the resolver clamps the combined non-own sum (+2 -1 = +1)");
        let net_one = Ctx { hit_mod: 1, ..spell_two };
        let estimated = profile_ev(&p, 10, &spell_two, &stealthy(), 12.0, false);
        let reference = profile_ev(&p, 10, &net_one, &defender(4, 5), 12.0, false);
        assert!((estimated - reference).abs() < 1e-9, "estimate {estimated} != resolver's net +1 {reference}");
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
