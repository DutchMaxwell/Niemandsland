use super::*;

    // ------- To-hit mods / shrouding family (sweeps A/B/F/G, 14.09.) ---------
    //
    // The D-PROOF wave: the four `none` rows of the to-hit/shrouding family
    // get their numbers pinned by core tests. All four rules are read in
    // `unit.rs::ctx_for` off the REAL registry, so every fixture here is a
    // real (system, faction) block:
    //   - "Darkborn" / "Shrouded" (gf/dark_brothers, gf/dark_prime_brothers):
    //     Ranged-Shrouding DATA aliases whose own entries print
    //     `range_penalty_in: 4, floor_in: 6, melee_move_penalty_in: 2,
    //     melee_floor_in: 6` — the ranged clamp pairs ride
    //     `ranged_shroud_params` (EPOCH_6_TABLE_RULES-gated alias walk), the
    //     melee charge shroud rides `melee_shroud_params` (uncapped).
    //   - "Machine-Fog" (gf/machine_cults): a Stealth-primitive alias —
    //     `hit_penalty: 1, over_in: 9, applies_charged: true` — the generic
    //     `stealth_alias_of` walk, so the to-hit target shifts ONLY past 9".
    //   - "Machine-Fog Boost" (gf/machine_cults): the printed unconditional
    //     form of Machine-Fog's own -1 (`EPOCH_6_TABLE_RULES`), the
    //     stand-down twin of "Empyrean Spirit Boost" (#965): the base entry's
    //     conditional alias leg stands down so exactly ONE modifier applies.
    // Epoch literals for the pre-gate arms are 5, never a moving symbol; the
    // live arms read `CURRENT_RULES_EPOCH`. No epoch bump: nothing changes
    // behaviour.

    /// The family's carrier template: one 24" rifle (the reach the shroud
    /// clamps) and one blade, so both stamped arrays are non-empty.
    /// `shroud_unit` swaps in the faction whose block fields the name and the
    /// rules the carrier prints.
    const SHROUD_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The REAL `build_for` product of a carrier printing `rules` in
    /// `gf/<faction>`, read at `epoch`.
    fn shroud_unit(faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let printed =
            rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = SHROUD_HEADER
            .replace(
                "\"faction_folder\":\"robot_legions\"",
                &format!("\"faction_folder\":\"{faction}\""),
            )
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("SHROUD_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// The capture twin's `CaptureReads` at `epoch` — the melee charge
    /// shroud (`[penalty_in, floor_in]`) lives there, not on `Ctx`.
    fn shroud_capture(faction: &str, rules: &[&str], epoch: u32) -> CaptureReads {
        let printed =
            rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = SHROUD_HEADER
            .replace(
                "\"faction_folder\":\"robot_legions\"",
                &format!("\"faction_folder\":\"{faction}\""),
            )
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("SHROUD_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        capture_reads_for_epoch(&mut reg, p, epoch)
    }

    /// One 2-attack rifle volley AT `us` at centre distance `dist_in` — the
    /// seam the shroud's reach clamp and the stealth/evasive to-hit legs ride
    /// (`us.ctx` is the DEFENDER).
    fn incoming_volley(us: &UnitStatic, dist_in: f64) -> crate::dice::ShootResult {
        let profiles = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[2], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(
            &strikers, &us.ctx, "Target", dist_in, dist_in, false, false, false, false, &mut tray,
        )
    }

    /// "Darkborn" (gf/dark_brothers): the ranged half of the Ranged-Shrouding
    /// alias — the entry's own `-4"/6"` clamp, not the primitive's fixed 6/6
    /// constants. A 24" rifle against the carrier reaches 24 - 4 = 20": the
    /// full-range 24" shot is OUT, 18" is in and fires at the UNMODIFIED
    /// target (the shroud clamps reach, never the to-hit), and the clamp
    /// names itself once per volley (rules-must-log). PRESENT at
    /// `CURRENT_RULES_EPOCH`, INERT at 5 (the frozen `EPOCH_6_TABLE_RULES`
    /// gate keeps the pre-port full-reach reading byte-exact).
    #[test]
    fn darkborn_shrouds_the_enemy_shooting_reach_by_its_own_minus_four_at_current_epoch() {
        let on = shroud_unit("dark_brothers", &["Darkborn"], CURRENT_RULES_EPOCH);
        assert!(
            on.ctx.ranged_shrouding,
            "epoch 54: the alias walk resolves the entry (RED before the fix)"
        );
        assert_eq!(on.ctx.ranged_shroud_penalty_in, 4.0, "the entry's own -4\"");
        assert_eq!(on.ctx.ranged_shroud_floor_in, 6.0, "the entry's own min 6\"");

        let far = incoming_volley(&on, 24.0);
        assert!(
            far.rolls.is_empty(),
            "24\" rifle is past the clamped 20\" reach (RED before the fix)"
        );
        assert!(
            far.log.iter().any(|l| l.contains("Ranged Shrouding") && l.contains("-4\"")),
            "rules-must-log: the clamp names its own -4\" once per volley"
        );

        let near = incoming_volley(&on, 18.0);
        assert_eq!(near.rolls[0].kind, "attack", "18\" is inside the 20\" clamp: the shot fires");
        assert_eq!(
            near.rolls[0].target, 4,
            "the shroud clamps REACH, never the to-hit target: Quality 4+ stands"
        );

        let base = shroud_unit("dark_brothers", &[], CURRENT_RULES_EPOCH);
        let plain = incoming_volley(&base, 24.0);
        assert_eq!(plain.rolls[0].kind, "attack", "no rule: the 24\" shot fires at full reach");
        assert!(
            !plain.log.iter().any(|l| l.contains("Ranged Shrouding")),
            "no clamp fired, nothing logs"
        );

        let old = shroud_unit("dark_brothers", &["Darkborn"], 5);
        assert!(!old.ctx.ranged_shrouding, "epoch 5: the alias walk is behind the frozen gate");
        assert_eq!(
            incoming_volley(&old, 24.0).rolls[0].kind, "attack",
            "epoch 5: the pre-port full-reach reading, byte-exact"
        );
    }

    /// "Shrouded" (gf/dark_brothers): BOTH halves of the same alias by their
    /// own numbers — the ranged clamp pair [-4", 6"] on the ctx and the
    /// melee charge shroud [-2", 6"] on the capture read (`melee_shroud_
    /// params`'s alias walk, uncapped by the epoch gate). Without the rule
    /// both legs stay silent.
    #[test]
    fn shrouded_carries_both_shroud_halves_by_their_own_numbers_at_current_epoch() {
        let on = shroud_unit("dark_brothers", &["Shrouded"], CURRENT_RULES_EPOCH);
        assert!(
            on.ctx.ranged_shrouding,
            "epoch 54: the ranged alias walk resolves the entry (RED before the fix)"
        );
        assert_eq!(on.ctx.ranged_shroud_penalty_in, 4.0, "the entry's own ranged -4\"");
        assert_eq!(on.ctx.ranged_shroud_floor_in, 6.0, "the entry's own ranged min 6\"");
        assert_eq!(
            shroud_capture("dark_brothers", &["Shrouded"], CURRENT_RULES_EPOCH).shroud,
            Some([2.0, 6.0]),
            "the entry's own melee half: -2\" charge move to a min of 6\" (RED before the fix)"
        );

        let base = shroud_unit("dark_brothers", &[], CURRENT_RULES_EPOCH);
        assert!(!base.ctx.ranged_shrouding, "no rule: no ranged clamp");
        assert_eq!(
            shroud_capture("dark_brothers", &[], CURRENT_RULES_EPOCH).shroud,
            None,
            "no rule: no melee charge shroud on either leg"
        );
    }

    /// "Machine-Fog" (gf/machine_cults): the Stealth-primitive alias — the
    /// entry's own `hit_penalty: 1` behind its own `over_in: 9` gate lands
    /// on the generic `stealth_alias_of` walk. 12" out the to-hit target is
    /// 4+ minus 1 = 5+; at 6" the gate is shut and the target stands; and
    /// the base form never folds into `evasive` (the Boost's job). Without
    /// the rule 12" is unmodified.
    #[test]
    fn machine_fog_penalizes_the_to_hit_target_past_nine_inches_at_current_epoch() {
        let on = shroud_unit("machine_cults", &["Machine-Fog"], CURRENT_RULES_EPOCH);
        assert_eq!(
            on.ctx.stealth_alias_penalty, 1,
            "the entry's own -1 (RED before the fix)"
        );
        assert_eq!(on.ctx.stealth_alias_over_in, 9.0, "the entry's own over-9\" gate");
        assert!(
            on.ctx.stealth_alias_applies_charged,
            "the entry's charged melee leg rides the same stamp"
        );
        assert!(
            !on.ctx.evasive,
            "the base form keeps its conditional gate: no evasive fold"
        );

        let far = incoming_volley(&on, 12.0);
        assert_eq!(
            far.rolls[0].target, 5,
            "12\": 4+ minus the entry's 1 = 5+ (RED before the fix)"
        );
        let near = incoming_volley(&on, 6.0);
        assert_eq!(near.rolls[0].target, 4, "6\" is inside the gate: unmodified");

        let base = shroud_unit("machine_cults", &[], CURRENT_RULES_EPOCH);
        assert_eq!(base.ctx.stealth_alias_penalty, 0, "no entry, no alias penalty");
        assert_eq!(
            incoming_volley(&base, 12.0).rolls[0].target, 4,
            "without the rule 12\" is unmodified"
        );
    }

    /// "Machine-Fog Boost" (gf/machine_cults): the printed unconditional form
    /// of Machine-Fog's own -1 — the stand-down twin of "Empyrean Spirit
    /// Boost" (#965). It folds into `evasive` (any range), the base entry's
    /// conditional alias leg stands down so EXACTLY ONE modifier applies
    /// (a stacked reading would read 6+ at 12", not 5+), and the dice seam
    /// names the RULE once per volley. Without the Boost the conditional leg
    /// stays shut inside 9"; below the frozen `EPOCH_6_TABLE_RULES` gate the
    /// Boost is not born yet.
    #[test]
    fn machine_fog_boost_makes_the_minus_one_unconditional_and_stands_the_base_down() {
        let on = shroud_unit(
            "machine_cults", &["Machine-Fog", "Machine-Fog Boost"], CURRENT_RULES_EPOCH,
        );
        assert!(
            on.ctx.evasive,
            "epoch 54: the Boost folds into evasive (RED before the fix)"
        );
        assert_eq!(
            on.ctx.evasive_alias_name, "Machine-Fog Boost",
            "rules-must-log names the RULE that fired"
        );
        assert_eq!(
            on.ctx.stealth_alias_penalty, 0,
            "the base entry's conditional alias leg stands down (never stacks)"
        );

        let near = incoming_volley(&on, 6.0);
        assert_eq!(
            near.rolls[0].target, 5,
            "6\": the always -1 (RED before the fix)"
        );
        let far = incoming_volley(&on, 12.0);
        assert_eq!(
            far.rolls[0].target, 5,
            "12\": EXACTLY one modifier — alias + fold would read 6+"
        );
        assert!(
            far.log.iter().any(|l| l.contains("Machine-Fog Boost")),
            "rules-must-log: the Boost names itself at the volley seam"
        );

        let base = shroud_unit("machine_cults", &["Machine-Fog"], CURRENT_RULES_EPOCH);
        let base_near = incoming_volley(&base, 6.0);
        assert_eq!(
            base_near.rolls[0].target, 4,
            "without the Boost the conditional leg stays shut inside 9\""
        );
        assert!(
            !base_near.log.iter().any(|l| l.contains("Machine-Fog Boost")),
            "nothing fired, nothing logs"
        );

        let old = shroud_unit("machine_cults", &["Machine-Fog", "Machine-Fog Boost"], 5);
        assert!(!old.ctx.evasive, "epoch 5: pre-port record, byte-exact");
        assert_eq!(old.ctx.evasive_alias_name, "", "epoch 5: nothing to name");
    }
