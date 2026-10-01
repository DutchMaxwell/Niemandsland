use super::*;

    // D21 / evfloor step 2: the record's epoch stamps `Ctx::modifier_sum` at STATIC BUILD, so every
    // `ctx_of`-built context (EV pricing and the dice sites that never called `with_modifier_sum`)
    // follows the table's "one sum, clamped once" from epoch 68 and replays the old floors below it.

    const SUM_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "def2":{"unit_id":"def2","name":"Def2","quality":4,
        "defense":2,"tough":1,"wounds_max":[1],"model_count":5,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":10,"count":1,"ap":1,"rules":[]}]},
      "def4":{"unit_id":"def4","name":"Def4","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":5,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[]}}}"#;

    fn def_at(name: &str, epoch: u32) -> Ctx {
        let header = read_act_header(SUM_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(name).expect("profile");
        UnitStatic::build_for(&mut reg, p, epoch).ctx
    }

    /// Ten Q4 attacks at AP(1) over 12" into `def`, expected unsaved wounds.
    fn ev_into(def: &Ctx) -> f64 {
        let att = Ctx { quality: 4, models: 5, ..Default::default() };
        let p = ShootProfile { attacks: 10, range: 24, ap: 1, ..Default::default() };
        crate::combat::profile_ev(&p, 10, &att, def, 12.0, false)
    }

    #[test]
    fn the_stamp_follows_the_records_epoch_at_build() {
        use crate::acts::EPOCH_68_MODIFIER_SUM;
        assert!(!def_at("def2", EPOCH_68_MODIFIER_SUM - 1).modifier_sum);
        assert!(def_at("def2", EPOCH_68_MODIFIER_SUM).modifier_sum);
        assert!(!def_at("def2", 0).modifier_sum, "an unstamped record replays the old floors");
    }

    /// F3.1: Def 2+ in cover vs AP(1) saves on 2+ (2 - 1 + 1), priced 0.833; the old floor priced 3+ = 1.667.
    #[test]
    fn def_2_in_cover_vs_ap_1_is_priced_on_the_sum_from_68() {
        let new = Ctx { in_cover: true, ..def_at("def2", 68) };
        let old = Ctx { in_cover: true, ..def_at("def2", 67) };
        assert!((ev_into(&new) - 10.0 * 0.5 * (1.0 / 6.0)).abs() < 1e-9);
        assert!((ev_into(&old) - 10.0 * 0.5 * (2.0 / 6.0)).abs() < 1e-9, "epoch 67 replays byte-exact");
    }

    /// F3.4 control: Def 4+ in cover vs AP(1) never touches a floor -> identical at 67 and 68.
    #[test]
    fn a_floorless_stack_prices_the_same_at_67_and_68() {
        let new = Ctx { in_cover: true, ..def_at("def4", 68) };
        let old = Ctx { in_cover: true, ..def_at("def4", 67) };
        assert_eq!(ev_into(&new), ev_into(&old));
    }

    /// D3: the dice sites that never stamped the flag (Storm / Retaliate / Impact / Surprise — the table sums
    /// them once too: main.gd `_solo_defense_vs` + `AiCombatMath.save_target`) follow it through `ctx_of`.
    /// Shielded Def 2+ vs an AP(1) storm save: 2 - 1 + 1 = 2+, the old floor saved on 3+.
    #[test]
    fn a_storm_save_follows_the_sum_from_68() {
        let save = |epoch| {
            let def = Ctx { shielded: true, ..def_at("def2", epoch) };
            let mut tray = crate::dice::Tray::seeded(27);
            let out = crate::dice::resolve_storm_hits_with_tray(10, 1, false, false, &def, "Def2", &mut tray);
            out.rolls.iter().find(|r| r.kind == "defense").expect("save").target
        };
        assert_eq!(save(68), 2);
        assert_eq!(save(67), 3);
    }

    /// Net rows stay pinned: `unit_sev_mev` prices against `neutral_defender()` (flag false), so the
    /// attacker's own stamp must not move it.
    #[test]
    fn net_rows_priced_against_the_neutral_defender_do_not_move() {
        let header = read_act_header(SUM_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("def2").expect("profile");
        let new = UnitStatic::build_for(&mut reg, p, 68);
        let old = UnitStatic::build_for(&mut reg, p, 67);
        let def = crate::rows::neutral_defender();
        assert_eq!(crate::rows::unit_sev_mev(p, &new, &def), crate::rows::unit_sev_mev(p, &old, &def));
    }
