use super::*;

    // --- Wave 4 follow-up (port-bloodthirsty-fighter, epoch 7) ---
    //
    // "Bloodthirsty Fighter" (aof/war_disciples, primitive self): "For each
    // unmodified roll of 1 that enemies roll when blocking hits from this
    // model's weapons in melee, this model may roll +1 attack with that
    // weapon. This rule doesn't apply to newly generated attacks."
    // Table: `_solo_last_save_ones` main.gd:5969, the count at :6505-6509,
    // the trigger in the strike loop at :6162-6189 (no-recursion reset at
    // :6184). Core seam: the melee fold's own save batches (dice.rs).
    // One RED/GREEN test through the REAL registry, plus one epoch test.
    // The epoch literals here are 7/6, never `CURRENT_RULES_EPOCH`, so a
    // wave-5 bump cannot re-date what these assertions mean.

    /// The family's carrier template: one blade, so the melee array is
    /// non-empty (the rule is melee_only by its own entry param).
    const BT_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"war_disciples",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,
          "rules":[]}]}}}"#;

    /// The REAL `build_for` product of a carrier printing `rules` in
    /// aof/war_disciples, read at `epoch`.
    fn bt_unit(rules: &[&str], epoch: u32) -> UnitStatic {
        let printed =
            rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = BT_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("BT_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// A plain Defense-4 target of one Tough(1) model.
    fn target() -> Ctx {
        Ctx { defense: 4, models: 1, tough: 1, ..Default::default() }
    }

    /// One 64-attack blade strike phase by `us` against `def`.
    fn strike(us: &UnitStatic, def: &Ctx) -> crate::dice::ShootResult {
        let profiles = [us.melee[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_melee_with_tray(&strikers, def, "def", false, false, false, &mut tray)
    }

    fn logged(out: &crate::dice::ShootResult, needle: &str) -> bool {
        out.log.iter().any(|l| l.contains(needle))
    }

    /// The strike names the rule and rolls the blocked-1s extra attacks
    /// (rules-must-log + the tray's own extra "attack" slot after the save
    /// batches). RED before the port: the melee fold never draws a second
    /// attack slot for blocked 1s and never logs the name.
    #[test]
    fn bloodthirsty_fighter_rolls_extra_attacks_off_blocked_ones_at_epoch_7() {
        let us = bt_unit(&["Bloodthirsty Fighter"], 7);
        let out = strike(&us, &target());
        assert!(
            logged(&out, "Bloodthirsty Fighter"),
            "epoch 7: the strike names the rule (RED before the port): {:?}",
            out.log
        );
        // The extra attacks are their own "attack" slot at the blade's to-hit
        // target (quality 4 => 4+), drawn after the save batch whose 1s paid
        // for them — the table's :6162-6189 order.
        let hits_target = out
            .rolls
            .iter()
            .filter(|r| r.kind == "attack" && r.owner == "att" && r.target == 4)
            .count();
        assert!(
            hits_target >= 2,
            "epoch 7: the blocked 1s pay for extra attack dice at the same to-hit target \
             (RED before the port): {} slots",
            hits_target
        );
    }

    /// EPOCH TEST: a record stamped 6 sees the old behaviour exactly — no
    /// extra attack dice, no log line. The name read is born at 7.
    #[test]
    fn bloodthirsty_fighter_is_inert_below_epoch_7() {
        let us6 = bt_unit(&["Bloodthirsty Fighter"], 6);
        let out = strike(&us6, &target());
        assert!(!logged(&out, "Bloodthirsty Fighter"), "epoch 6: nothing fires, nothing logs");
        let slots = out
            .rolls
            .iter()
            .filter(|r| r.kind == "attack" && r.owner == "att")
            .count();
        assert_eq!(slots, 1, "epoch 6: the blade's single strike slot only");
        // And a bearer-less unit at 7 is exactly as silent.
        let none = bt_unit(&[], 7);
        let plain = strike(&none, &target());
        assert!(!logged(&plain, "Bloodthirsty Fighter"), "no rule, no fire");
    }
