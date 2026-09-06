use super::*;

    // --- Wave 4 "Boost bases 2" family (rules-wave4-boostbases2, epoch 7) ---
    //
    // One test per ported name, through the REAL registry (each name's own
    // (system, faction) block, the folder its book prints). The three Boost
    // AURAS that grant these bases already read core-live; this family ports
    // the GRANTED BASES, so an aura grant lands on a live handler instead of
    // a name the core never reads. Every spelling is stated BY NAME by
    // `build_for`'s epoch-7 arms (the frozen `EPOCH_7_TABLE_RULES`); the
    // epoch literals here are 7/6, never `CURRENT_RULES_EPOCH`, so a wave-5
    // bump cannot re-date what these assertions mean.

    /// The family's carrier template: one rifle and one blade, so both stamped
    /// arrays are non-empty. `boostbases2_unit` swaps in the faction whose
    /// block fields the name and the rules the carrier prints.
    const BOOSTBASES2_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The REAL `build_for` product of a carrier printing `rules` in
    /// `aof/<faction>`, read at `epoch`.
    fn boostbases2_unit(faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let printed =
            rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = BOOSTBASES2_HEADER
            .replace(
                "\"faction_folder\":\"robot_legions\"",
                &format!("\"faction_folder\":\"{faction}\""),
            )
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("BOOSTBASES2_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// One 64-attack rifle volley by `us` at centre distance `dist_in`,
    /// against a plain Defense-5 target — the seam the widened Bane window
    /// rides (the DEFENDER re-rolls its successful saves).
    fn bane_volley(us: &UnitStatic, dist_in: f64) -> crate::dice::ShootResult {
        let profiles = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let def = Ctx { defense: 5, models: 1, tough: 1, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(
            &strikers, &def, "Target", dist_in, dist_in, true, false, false, false, &mut tray,
        )
    }

    /// One 64-attack rifle volley AT `us` at centre distance `dist_in` — the
    /// seam the unconditional -1 to hit rides (the carrier is the DEFENDER).
    fn incoming_volley(us: &UnitStatic, dist_in: f64) -> crate::dice::ShootResult {
        let profiles = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(
            &strikers, &us.ctx, "Target", dist_in, dist_in, false, false, false, false, &mut tray,
        )
    }

    /// "Bestial Boost" (aof/beastmen): the Bane family's WIDENED save re-roll
    /// window — the entry's own `reroll_save_low: 5` + `over_in: 9`, behind
    /// its `upgrades` coupling ("If this model has Bestial"). Past 9" the
    /// defender's successful unmodified 5s re-roll too, not just its 6s, and
    /// the firing names itself (rules-must-log). PRESENT at 7, ABSENT at 6
    /// (the base "Bestial" alias itself banes at every epoch — only the
    /// WIDENED window is epoch-7 born), and exactly 9" is not "over".
    #[test]
    fn bestial_boost_widens_the_bane_window_over_nine_inches_at_epoch_7() {
        let us = boostbases2_unit("beastmen", &["Bestial", "Bestial Boost"], 7);
        assert!(us.shoot[0].bane, "the base alias banes at every epoch");
        let on = bane_volley(&us, 12.0);
        let saves = &on.rolls[1];
        assert_eq!(saves.kind, "defense", "rolls[1] is the save batch");
        let fives = saves.faces.iter().filter(|&&f| f == 5).count();
        let sixes = saves.faces.iter().filter(|&&f| f == 6).count();
        assert!(fives > 0 && sixes > 0, "this seed must land both faces or the test is blind");
        assert_eq!(
            on.rolls[2].count as usize,
            fives + sixes,
            "epoch 7, 12\": every successful 5-6 re-rolls (the widened window)"
        );
        assert!(
            on.log.iter().any(|l| l.contains("Bestial Boost")),
            "rules-must-log: the widened window names itself (RED before the fix)"
        );

        // Exactly 9" is not "over": the base 6s-only window.
        let at9 = bane_volley(&us, 9.0);
        assert_eq!(
            at9.rolls[2].count as usize,
            at9.rolls[1].faces.iter().filter(|&&f| f == 6).count(),
            "exactly 9\" stays shut"
        );

        // Epoch 6: the record predates this wave — the base 6s-only window.
        let us6 = boostbases2_unit("beastmen", &["Bestial", "Bestial Boost"], 6);
        let off = bane_volley(&us6, 12.0);
        assert_eq!(off.rolls[2].count as usize, sixes, "epoch 6: the base window, byte-exact");
        assert!(
            !off.log.iter().any(|l| l.contains("Bestial Boost")),
            "epoch 6: the widened window is not born yet"
        );

        // Without the Boost the base carrier keeps the 6s-only window.
        let base = boostbases2_unit("beastmen", &["Bestial"], 7);
        let without = bane_volley(&base, 12.0);
        assert_eq!(without.rolls[2].count as usize, sixes, "no Boost: only the 6s re-roll");
        assert!(
            !without.log.iter().any(|l| l.contains("Bestial Boost")),
            "no widened window fired, nothing logs"
        );
    }

    /// "Empyrean Spirit Boost" (aof/ghostly_undead): the printed unconditional
    /// form of Empyrean Spirit's own -1 ("enemies attacking them always get -1
    /// to hit … instead of only over 9\" away"). It folds into the evasive
    /// flag (any range) and the base entry's conditional Stealth alias leg
    /// stands down, so the two never stack. PRESENT at 7, ABSENT at 6 (the
    /// alias leg keeps its over-9" gate, byte-exact).
    #[test]
    fn empyrean_spirit_boost_makes_the_minus_one_unconditional_at_epoch_7() {
        let on = boostbases2_unit("ghostly_undead", &["Empyrean Spirit", "Empyrean Spirit Boost"], 7);
        assert!(on.ctx.evasive, "epoch 7: the Boost folds into evasive (RED before the fix)");
        assert_eq!(
            on.ctx.stealth_alias_penalty, 0,
            "the base entry's conditional alias leg stands down (never stacks)"
        );

        let off = boostbases2_unit("ghostly_undead", &["Empyrean Spirit", "Empyrean Spirit Boost"], 6);
        assert!(!off.ctx.evasive, "epoch 6: pre-port records stay inert");
        assert_eq!(
            off.ctx.stealth_alias_penalty, 1,
            "epoch 6: the base alias leg keeps its over-9\" gate, byte-exact"
        );

        // The volley 6" out (inside the base alias gate): the -1 lands anyway.
        let shot = incoming_volley(&on, 6.0);
        assert_eq!(
            shot.rolls[0].target, 5,
            "epoch 7, 6\": the always -1 (4+ minus 1 = 5+) (RED before the fix)"
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Empyrean Spirit Boost")),
            "rules-must-log: the Boost names itself at the volley seam"
        );

        // Without the Boost the conditional leg stays shut inside 9".
        let base = boostbases2_unit("ghostly_undead", &["Empyrean Spirit"], 7);
        let base_shot = incoming_volley(&base, 6.0);
        assert_eq!(
            base_shot.rolls[0].target, 4,
            "without the Boost the conditional alias stays shut inside 9\""
        );
        assert!(
            !base_shot.log.iter().any(|l| l.contains("Empyrean Spirit Boost")),
            "nothing fired, nothing logs"
        );
    }

    /// "Wave-Step Boost" (aof/deep_sea_elves): the placement rolls 2d3 instead
    /// of the base entry's single die, behind its own `upgrades` coupling
    /// ("If this model has Wave-Step"). The core's own per-entry read of the
    /// entry's `place_die` — the table's `bounding_dice_count` twin — is the
    /// evidence-only `bounding` shape (PR #653): the placement itself reaches
    /// this core precomputed through the RECORDED `bounding_d3` faces. 0 at
    /// epoch 6, 0 without the Boost, 0 without the base.
    #[test]
    fn wave_step_boost_reads_its_own_two_dice_placement_at_epoch_7() {
        assert_eq!(
            boostbases2_unit("deep_sea_elves", &["Wave-Step", "Wave-Step Boost"], 7).bounding_dice,
            2,
            "epoch 7: the entry's own place_die \"2d3\" (RED before the fix)"
        );
        assert_eq!(
            boostbases2_unit("deep_sea_elves", &["Wave-Step", "Wave-Step Boost"], 6).bounding_dice,
            0,
            "epoch 6: pre-port records read the base single die"
        );
        assert_eq!(
            boostbases2_unit("deep_sea_elves", &["Wave-Step"], 7).bounding_dice,
            0,
            "no Boost, no second die"
        );
        assert_eq!(
            boostbases2_unit("deep_sea_elves", &["Wave-Step Boost"], 7).bounding_dice,
            0,
            "the `upgrades` coupling: the Boost alone is not carried"
        );
    }

    /// The corpus floor, in one place: a record stamped BELOW
    /// `EPOCH_7_TABLE_RULES` sees none of this wave's three bases — the exact
    /// reading it had before the wave existed.
    #[test]
    fn an_epoch_six_record_sees_none_of_the_three_wave_four_boosts() {
        let bane = boostbases2_unit("beastmen", &["Bestial", "Bestial Boost"], 6);
        assert_eq!(bane.shoot[0].bane_low, 0, "epoch 6: the base 6s-only window");
        assert_eq!(bane.shoot[0].bane_rule, "", "epoch 6: nothing to name");
        let spirit =
            boostbases2_unit("ghostly_undead", &["Empyrean Spirit", "Empyrean Spirit Boost"], 6);
        assert!(!spirit.ctx.evasive, "epoch 6: the -1 keeps its over-9\" gate");
        assert_eq!(spirit.ctx.evasive_alias_name, "", "epoch 6: nothing to name");
        assert_eq!(
            boostbases2_unit("deep_sea_elves", &["Wave-Step", "Wave-Step Boost"], 6).bounding_dice,
            0,
            "epoch 6: the base single-die placement"
        );
    }
