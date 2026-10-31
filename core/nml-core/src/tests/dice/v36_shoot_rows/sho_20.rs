use super::super::*;

/// SHO-20 (rules 3.6): a Slayer's extra AP against a Tough(3)+ target is earned by a HOLD on
/// the shooting side from `EPOCH_73_V36`; a shooter that moved gets none. At
/// `EPOCH_72_PLAYTEST_RULES` the old over-9" leg still fires, and the charge leg is unchanged at
/// every epoch. The shooter is the REAL static build over the shipped maps, so the epoch stamp is
/// part of the proof; the log line names why the AP fired (or that it was switched off).
mod sho_20_slayer_hold {
    use super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::rules::Registries;

    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// A Quality 4 dao_union squad carrying the printed "Slayer" rule, with a rifle and a blade.
    fn slayers(epoch: u32) -> UnitStatic {
        let header = r#"{"kind":"header","knobs":{},"profiles":{
          "carrier":{"unit_id":"carrier","name":"Slayers","quality":4,
            "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
            "base_radius":0.016,"game_system":"gf","faction_folder":"dao_union",
            "special_rules":["Slayer"],"item_grants":[],
            "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
            "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]},
                       {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]}}}"#;
        let parsed = crate::acts::read_act_header(header).expect("header parses");
        let mut reg = Registries::new(&repo_root());
        let p = parsed.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    fn tough_target() -> Ctx {
        Ctx { defense: 4, tough: 3, models: 5, ..Default::default() }
    }

    /// One 12" rifle volley with the shooter's Hold state.
    fn volley(u: &UnitStatic, held: bool) -> ShootResult {
        let att = Ctx { held, ..u.ctx };
        let one = [Shooter { profiles: &u.shoot, keep: &[0], attacks: &[6], att: &att, owner: "Slayers" }];
        let mut tray = Tray::seeded(7);
        resolve_volley_leg(
            &one, &tough_target(), "Target", 12.0, 12.0, true, true, true, true, true, false,
            &|_| false, &mut tray,
        )
    }

    /// One charging blade strike against the same Tough(3) target.
    fn strike(u: &UnitStatic) -> ShootResult {
        let one = [Shooter { profiles: &u.melee, keep: &[0], attacks: &[6], att: &u.ctx, owner: "Slayers" }];
        let mut tray = Tray::seeded(7);
        resolve_melee_with_tray(&one, &tough_target(), "Target", true, true, true, &mut tray)
    }

    /// Every defense batch's save target: Defense 4 with AP(2) is 6+, without AP 4+.
    fn save_targets(r: &ShootResult) -> Vec<i64> {
        r.rolls.iter().filter(|x| x.kind == "defense").map(|x| x.target).collect()
    }

    /// A HOLD earns the extra AP at 73, and the log names the Hold.
    #[test]
    fn a_holding_slayer_gets_its_extra_ap_at_epoch_73() {
        let u = slayers(EPOCH_73_V36);
        assert_eq!(u.shoot[0].cond_ap[0].gate, "hold_or_charge", "73 stamps the Hold gate");
        let r = volley(&u, true);
        assert!(save_targets(&r).iter().all(|&t| t == 6), "AP(+2): saves at 6+ not 4+: {:?}", save_targets(&r));
        assert!(r.log.iter().any(|l| l == "Slayer: AP(+2) because Slayers held"), "log: {:?}", r.log);
    }

    /// A shooter that moved gets no extra AP at 73, and the log says why it was switched off.
    #[test]
    fn a_moved_slayer_gets_no_extra_ap_at_epoch_73() {
        let u = slayers(EPOCH_73_V36);
        let r = volley(&u, false);
        assert!(save_targets(&r).iter().all(|&t| t == 4), "no AP: saves stay at 4+: {:?}", save_targets(&r));
        assert!(r.log.iter().any(|l| l == "Slayer: no AP, Slayers moved"), "log: {:?}", r.log);
    }

    /// AT 72 the old over-9" leg still pays a moved shooter (today's behaviour).
    #[test]
    fn a_moved_slayer_keeps_the_over_nine_leg_at_epoch_72() {
        let u = slayers(EPOCH_72_PLAYTEST_RULES);
        assert_eq!(u.shoot[0].cond_ap[0].gate, "ranged_over_or_charge", "72 keeps the old gate");
        let r = volley(&u, false);
        assert!(save_targets(&r).iter().all(|&t| t == 6), "72: past 9\" earns AP(+2) even after moving");
        assert!(!r.log.iter().any(|l| l == "Slayer: no AP, Slayers moved"), "no changed line below 73");
    }

    /// CONTROL: the charge leg pays at both epochs, and at 73 names the charge.
    #[test]
    fn a_charging_slayer_keeps_its_extra_ap_at_epoch_72_and_73() {
        for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
            let u = slayers(epoch);
            let r = strike(&u);
            assert!(save_targets(&r).iter().all(|&t| t == 6), "{epoch}: charging is AP(+2): {:?}", save_targets(&r));
            if epoch == EPOCH_73_V36 {
                assert!(r.log.iter().any(|l| l == "Slayer: AP(+2) because it charged"), "log: {:?}", r.log);
            }
        }
    }
}
