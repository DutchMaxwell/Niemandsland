use super::super::*;

// FAB-A10 (rules 3.6): a moved Slayer's shooting has no 9" leg at epoch 73 — the AP is already 0
// at every distance, so the "no AP, moved" line must name the rule at every distance too.
// Below 73 the old over-9" leg stays untouched (the generic AP line only over 9", no moved line).

mod fab_a10_slayer_moved_every_distance {
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

    /// One rifle volley at `dist_in` from a shooter that did NOT Hold.
    fn volley(u: &UnitStatic, dist_in: f64) -> ShootResult {
        let one = [Shooter { profiles: &u.shoot, keep: &[0], attacks: &[6], att: &u.ctx, owner: "Slayers" }];
        let mut tray = Tray::seeded(7);
        resolve_volley_leg(
            &one, &tough_target(), "Target", dist_in, dist_in, true, true, true, true, true, false,
            &|_| false, &|_, _| None, &mut tray,
        )
    }

    fn save_targets(r: &ShootResult) -> Vec<i64> {
        r.rolls.iter().filter(|x| x.kind == "defense").map(|x| x.target).collect()
    }

    fn no_ap_line(r: &ShootResult) -> bool {
        r.log.iter().any(|l| l == "Slayer: no AP, Slayers moved")
    }

    #[test]
    fn a_moved_slayer_names_no_ap_at_seven_inches_at_epoch_73() {
        let u = slayers(EPOCH_73_V36);
        let r = volley(&u, 7.0);
        assert!(save_targets(&r).iter().all(|&t| t == 4), "no AP under 9\": {:?}", save_targets(&r));
        assert!(no_ap_line(&r), "RED on main: the moved line only prints over 9\": {:?}", r.log);
    }

    #[test]
    fn a_moved_slayer_keeps_the_same_wording_at_twelve_inches_at_epoch_73() {
        let u = slayers(EPOCH_73_V36);
        let r = volley(&u, 12.0);
        assert!(save_targets(&r).iter().all(|&t| t == 4), "no AP over 9\" either: {:?}", save_targets(&r));
        assert!(no_ap_line(&r), "the over-9\" wording is unchanged: {:?}", r.log);
    }

    #[test]
    fn a_moved_slayer_keeps_the_old_over_nine_leg_at_epoch_72() {
        let u = slayers(EPOCH_72_PLAYTEST_RULES);
        let near = volley(&u, 7.0);
        assert!(save_targets(&near).iter().all(|&t| t == 4), "72: no AP under 9\"");
        assert!(!no_ap_line(&near), "72 has no moved line below the gate: {:?}", near.log);
        let far = volley(&u, 12.0);
        assert!(save_targets(&far).iter().all(|&t| t == 6), "72: past 9\" earns AP(+2) even after moving");
        assert!(!no_ap_line(&far), "72 keeps the old over-9\" reading only: {:?}", far.log);
    }
}
