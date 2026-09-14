use super::*;

    // --- TEST WAVE (2026-09-14, D-PROOF) — Grounded Reinforcement's NUMBER
    // pin: the EXACT name read (`shielded_alias_of`'s own literal, gf
    // soul_snatcher_cults) stamps the terrain-pending alias through the REAL
    // `build_for`, and the live majority-in-cover fold produces exactly the
    // +1 defense rung when the bearer is in cover.

    /// The carrier template: one rifle, Defense 4, so the rung number is
    /// observable on `ctx.defense`'s own floor.
    const GR_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn gr_unit(faction: &str, special: &str, epoch: u32) -> UnitStatic {
        let tpl = GR_HEADER
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":{special}"));
        let header = crate::acts::read_act_header(&tpl).expect("GR_HEADER parses");
        let mut reg = crate::rules::Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// "Grounded Reinforcement" (gf/soul_snatcher_cults, primitive Shielded,
    /// defense_bonus 1, terrain_within_in 1): the STATIC stamp leaves
    /// `shielded` off (the terrain gate is live state); `ctx_of` + `ctx_live`
    /// fold the +1 in exactly when the unit is in cover — Defense 4 saves at
    /// 3+ there, at plain 4+ out of it, and a rule-less carrier never folds.
    #[test]
    fn a_grounded_reinforcement_carrier_shields_by_one_in_cover_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let built = gr_unit("soul_snatcher_cults", "[\"Grounded Reinforcement\"]", epoch);
        assert_eq!(
            built.ctx.shielded_alias,
            crate::unit::ShieldedAlias::GroundedReinforcement,
            "the exact name stamps the alias"
        );
        assert!(!built.ctx.shielded, "terrain-pending: the static stamp keeps the +1 off");

        let (mut st, mut statics) = buff_line();
        statics[0] = built;
        st.in_cover[0] = false;
        let off = ctx_live(ctx_of(&statics[0], &st, 0), &statics, &st, 0, false, epoch);
        assert!(!off.shielded, "out of cover: no fold");
        assert_eq!(off.shielded_bonus(), 0);

        st.in_cover[0] = true;
        let on = ctx_live(ctx_of(&statics[0], &st, 0), &statics, &st, 0, false, epoch);
        assert!(on.shielded, "in cover: the live majority read fires the alias");
        assert_eq!(on.shielded_bonus(), 1, "the +1 the rule produces");
        assert_eq!(
            crate::combat::shielded_defense(on.defense, on.shielded_bonus()),
            3,
            "Defense 4 -> hit on 3+ in cover"
        );

        // The rule-less carrier of the same faction: never folds, even in cover.
        let (mut st2, mut statics2) = buff_line();
        statics2[0] = gr_unit("soul_snatcher_cults", "[]", epoch);
        st2.in_cover[0] = true;
        let bare = ctx_live(ctx_of(&statics2[0], &st2, 0), &statics2, &st2, 0, false, epoch);
        assert!(!bare.shielded && bare.shielded_bonus() == 0, "no rule, no fold");
    }
