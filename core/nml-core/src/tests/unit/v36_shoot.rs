//! Rules 3.6 lane shoot tests for the unit module; owned by lane shoot.

/// SHO-07, rules 3.6: a shot AT an Aircraft is also -1 to hit, on top of the
/// -12" range penalty (held in tests/sim/aircraft.rs). The number is the
/// shipped map's Aircraft `target_hit_penalty`, read only from EPOCH_73_V36;
/// at EPOCH_72_PLAYTEST_RULES every record keeps the 3.5 reading. The target's
/// context is the REAL static build over the shipped maps (an empty faction
/// folder resolves the common entry), so the map row is part of the proof.
mod sho_07_aircraft_hit {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::dice::{resolve_volley_leg, Shooter, Tray};

    fn target_ctx(system: &str, rules: &[&str], epoch: u32) -> Ctx {
        let mut p: Profile = serde_json::from_str(r#"{"unit_id":"flyer","name":"Flyer"}"#).unwrap();
        p.game_system = system.into();
        p.special_rules = rules.iter().map(|r| r.to_string()).collect();
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch).ctx
    }

    fn rifle(unstoppable: bool) -> ShootProfile {
        // The dice read `unstoppable`, the EV `unstoppable_ev` (the stamp sets both).
        ShootProfile { name: "Rifle".into(), attacks: 10, count: 1, range: 24, unstoppable, unstoppable_ev: unstoppable, ..Default::default() }
    }

    fn gunner() -> Ctx {
        Ctx { quality: 4, models: 1, ..Default::default() }
    }

    /// One Quality 4+ volley of 10 shots from 12" away: the to-hit target of
    /// every attack die it rolls, and the battle log it writes.
    fn volley_at(def: &Ctx, unstoppable: bool) -> (Vec<i64>, Vec<String>) {
        let att = gunner();
        let p = [rifle(unstoppable)];
        let one = [Shooter { profiles: &p, keep: &[0], attacks: &[10], att: &att, owner: "Gunner" }];
        let mut tray = Tray::seeded(7);
        let r = resolve_volley_leg(&one, def, "Flyer", 12.0, 12.0, true, true, true, true, true, false, &|_| false, &mut tray);
        let targets = r.rolls.iter().filter(|x| x.kind == "attack").map(|x| x.target).collect();
        (targets, r.log)
    }

    fn names_aircraft(log: &[String]) -> bool {
        log.iter().any(|l| l.contains("Aircraft") && l.contains("Flyer"))
    }

    /// OLD leg: at 72 a shot at an Aircraft still hits on the shooter's 4+,
    /// and the log names no Aircraft penalty.
    #[test]
    fn a_shot_at_aircraft_has_no_hit_penalty_at_epoch_72() {
        let (targets, log) = volley_at(&target_ctx("gf", &["Aircraft"], EPOCH_72_PLAYTEST_RULES), false);
        assert_eq!(targets, vec![4], "72 replays the 3.5 reading: range penalty only");
        assert!(!names_aircraft(&log), "no Aircraft to-hit line at 72: {log:?}");
    }

    /// NEW leg: from 73 the same volley needs 5+ in both systems, and the
    /// battle log names the rule against the unit it protects.
    #[test]
    fn a_shot_at_aircraft_is_minus_one_to_hit_at_epoch_73() {
        for system in ["gf", "aof"] {
            let (targets, log) = volley_at(&target_ctx(system, &["Aircraft"], EPOCH_73_V36), false);
            assert_eq!(targets, vec![5], "{system}: 4+ becomes 5+ against an Aircraft");
            assert!(names_aircraft(&log), "{system}: the -1 writes a log line naming Aircraft: {log:?}");
        }
    }

    /// Controls: a ground target keeps 4+ at 73, and Unstoppable still ignores
    /// the -1 (it is a negative modifier like any other the clamp sees).
    #[test]
    fn ground_targets_and_unstoppable_shots_keep_their_target_at_epoch_73() {
        let (targets, log) = volley_at(&target_ctx("gf", &[], EPOCH_73_V36), false);
        assert_eq!(targets, vec![4], "a ground unit takes no Aircraft penalty");
        assert!(!names_aircraft(&log));
        let (targets, _) = volley_at(&target_ctx("gf", &["Aircraft"], EPOCH_73_V36), true);
        assert_eq!(targets, vec![4], "Unstoppable ignores the Aircraft -1");
    }

    /// The EV twin (`profile_ev`): from 73 the AI prices a shot at an Aircraft
    /// at a 5+ to hit (1/3) instead of 4+ (1/2), so exactly 2/3 of the 72 value.
    #[test]
    fn the_ev_prices_the_aircraft_minus_one_from_epoch_73() {
        let ev = |def: &Ctx, unstoppable: bool| crate::combat::profile_ev(&rifle(unstoppable), 10, &gunner(), def, 12.0, false);
        let old = ev(&target_ctx("gf", &["Aircraft"], EPOCH_72_PLAYTEST_RULES), false);
        let new = ev(&target_ctx("gf", &["Aircraft"], EPOCH_73_V36), false);
        assert!(old > 0.0, "fixture: the rifle does damage");
        assert!((new - old * 2.0 / 3.0).abs() < 1e-9, "73: 1/3 hits instead of 1/2 ({new} vs {old})");
        let shrugged = ev(&target_ctx("gf", &["Aircraft"], EPOCH_73_V36), true);
        assert!((shrugged - old).abs() < 1e-9, "Unstoppable keeps the full value");
    }
}
