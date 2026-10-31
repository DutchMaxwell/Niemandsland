use super::super::*;

/// SHO-08, rules 3.6 Unstoppable: a minus that comes from the shooter's OWN
/// rules (Bad Shot's -1, Indirect's moved -1) now applies; a minus from the
/// target (Evasive) is still ignored. At EPOCH_72_PLAYTEST_RULES the old single
/// clamp over the whole sum stays. The shooter is the REAL static build over the
/// shipped maps, so the epoch stamp and the Bad Shot / Unstoppable / Indirect
/// stamps are part of the proof.
mod sho_08_unstoppable_own_minus {
    use super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::rules::Registries;
    use crate::state::Profile;

    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// A Quality 4 orc squad (gf/orc_marauders fields Bad Shot) with one rifle.
    fn gunners(rules: &str, weapon_rules: &str, epoch: u32) -> UnitStatic {
        let p: Profile = serde_json::from_str(&format!(
            r#"{{"unit_id": "a", "name": "Gunners", "model_count": 1,
                "quality": 4, "defense": 4, "tough": 1,
                "game_system": "gf", "faction_folder": "orc_marauders",
                "special_rules": [{rules}],
                "weapons": [{{"name": "Rifle", "range": 24, "attacks": 10, "count": 1, "ap": 0,
                              "rules": [{weapon_rules}]}}]}}"#
        ))
        .expect("the gunners' profile parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// One 12" volley of the rifle: the to-hit target of every attack die, and the log.
    fn volley(u: &UnitStatic, att: &Ctx, def: &Ctx) -> (Vec<i64>, Vec<String>) {
        let one = [Shooter { profiles: &u.shoot, keep: &[0], attacks: &[10], att, owner: "Gunners" }];
        let mut tray = Tray::seeded(7);
        let r = resolve_volley_leg(&one, def, "Target", 12.0, 12.0, true, true, true, true, true, false, &|_| false, &mut tray);
        (r.rolls.iter().filter(|x| x.kind == "attack").map(|x| x.target).collect(), r.log)
    }

    fn keeps_own(log: &[String]) -> bool {
        log.iter().any(|l| l.contains("Unstoppable") && l.contains("own"))
    }

    /// OLD leg (and the stamp's own control): at 72 Unstoppable ignores Bad
    /// Shot's -1 like any other minus; without Unstoppable the -1 is real.
    #[test]
    fn unstoppable_ignores_its_own_bad_shot_at_epoch_72() {
        let u = gunners(r#""Bad Shot""#, r#""Unstoppable""#, EPOCH_72_PLAYTEST_RULES);
        let (targets, log) = volley(&u, &u.ctx, &defender(4, 5));
        assert_eq!(targets, vec![4], "72: one clamp over the whole sum");
        assert!(!keeps_own(&log), "no own-minus line at 72: {log:?}");
        let plain = gunners(r#""Bad Shot""#, "", EPOCH_72_PLAYTEST_RULES);
        assert_eq!(volley(&plain, &plain.ctx, &defender(4, 5)).0, vec![5], "Bad Shot is -1 to hit");
    }

    /// NEW leg: from 73 the own -1 applies (4+ becomes 5+), also next to an
    /// Evasive target whose -1 is still ignored, and the log names the kept minus.
    #[test]
    fn unstoppable_keeps_its_own_bad_shot_at_epoch_73() {
        let u = gunners(r#""Bad Shot""#, r#""Unstoppable""#, EPOCH_73_V36);
        let (targets, log) = volley(&u, &u.ctx, &defender(4, 5));
        assert_eq!(targets, vec![5], "73: the bearer's own -1 is not ignored");
        assert!(keeps_own(&log), "the log names the kept own minus: {log:?}");
        let evasive = Ctx { evasive: true, ..defender(4, 5) };
        assert_eq!(volley(&u, &u.ctx, &evasive).0, vec![5], "own -1 kept, the target's Evasive -1 ignored");
    }

    /// HOLD: an enemy minus alone (Evasive) is still ignored at both epochs.
    #[test]
    fn unstoppable_still_ignores_enemy_evasive_at_epoch_72_and_73() {
        let evasive = Ctx { evasive: true, ..defender(4, 5) };
        for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
            let u = gunners("", r#""Unstoppable""#, epoch);
            let (targets, log) = volley(&u, &u.ctx, &evasive);
            assert_eq!(targets, vec![4], "{epoch}: Evasive is not the bearer's own rule");
            assert!(!keeps_own(&log), "{epoch}: nothing own to keep: {log:?}");
        }
    }

    /// Indirect's moved -1 is the weapon's own rule: ignored at 72; at 73 the penalty is gone (SHO-02), so
    /// there is no own minus to keep and the shot hits at base.
    #[test]
    fn unstoppable_indirect_has_no_moved_minus_at_epoch_73() {
        for (epoch, want) in [(EPOCH_72_PLAYTEST_RULES, 4), (EPOCH_73_V36, 4)] {
            let u = gunners("", r#""Unstoppable", "Indirect""#, epoch);
            let moved = Ctx { moved_this_round: true, ..u.ctx };
            assert_eq!(volley(&u, &moved, &defender(4, 5)).0, vec![want], "{epoch}: Indirect moved -1");
        }
    }

    /// The melee twin (`melee_hit_target`'s clamp): Quality 6, Unpredictable
    /// Fighter's own +1 into an Evasive defender. 72 sums -1 + 1 = 0 (6+, the
    /// CHECK in melee_impact_order.rs); 73 ignores the enemy -1 and keeps the own +1 (5+).
    #[test]
    fn melee_unstoppable_keeps_its_own_bonus_against_evasive_at_epoch_73() {
        let mut p = blade(1);
        p.unstoppable = true;
        let evasive = Ctx { evasive: true, ..defender(4, 1) };
        for (epoch, want) in [(EPOCH_72_PLAYTEST_RULES, 6), (EPOCH_73_V36, 5)] {
            let att = Ctx { quality: 6, models: 1, ..gunners("", "", epoch).ctx };
            assert_eq!(melee_hit_target(&p, &att, &evasive, false, 1, 0.0, false).0, want, "{epoch}");
        }
    }
}
