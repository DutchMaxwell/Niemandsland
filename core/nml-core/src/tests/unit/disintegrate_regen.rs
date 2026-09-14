use super::*;

    /// EPOCH 46 DISINTEGRATE REGEN — the fixture: a gf/blessed_sisters carrier
    /// whose weapon carries "Disintegrate" (the book's own shape — the Blessed
    /// Flamer Pistol), built off the REAL registry entry
    /// (`bypass_regen: true`, condition `vs_armor`, threshold 3) at `epoch`.
    fn disintegrate_carrier(weapon_range: i64, epoch: u32) -> UnitStatic {
        let tpl = format!(
            r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":2,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Flamer","range":{weapon_range},"attacks":24,"count":1,"ap":0,
          "rules":["Disintegrate"]}}]}}}}}}"#
        );
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// One exchange of the carrier's Disintegrate weapon against a
    /// Regeneration(5+) defender — the bane_bypass harness's own numbers
    /// (24 attack dice at Quality 2, Defense 4, seed 27).
    fn disintegrate_volley(us: &UnitStatic, melee: bool) -> crate::dice::ShootResult {
        let att = Ctx { quality: 2, models: 1, ..Default::default() };
        let def = Ctx {
            defense: 4, tough: 1, models: 1,
            regeneration: true, regen_target: 5,
            ..Default::default()
        };
        let mut tray = crate::dice::Tray::seeded(27);
        if melee {
            let prof = us.melee[0].clone();
            crate::dice::resolve_melee_with_tray(
                &[crate::dice::Shooter {
                    profiles: std::slice::from_ref(&prof),
                    keep: &[0],
                    attacks: &[24],
                    att: &att,
                    owner: "Carrier",
                }],
                &def, "Target", true, false, false, &mut tray,
            )
        } else {
            let prof = us.shoot[0].clone();
            crate::dice::resolve_shooting_with_tray(
                &[prof], &[0], &[24], &att, &def, 12.0, &mut tray,
            )
        }
    }

    /// The old-leg pin — the frozen constant of the epoch immediately below
    /// the bump AT REBASE TIME (re-pointed at every rebase, never the live
    /// symbol; 44 is `EPOCH_44_SURGE_MARK`'s own landed leg, 45 the
    /// casterboost leg still in flight).
    const OLD_EPOCH: u32 = crate::acts::EPOCH_44_SURGE_MARK;

    /// EPOCH 46 DISINTEGRATE REGEN — a Regeneration unit wounded by a weapon
    /// whose Disintegrate entry carries `bypass_regen: true` gets NO
    /// Regeneration roll at 46 — the table refuses the heal
    /// (`_solo_ignores_regen`'s registry-driven weapon-rule arm,
    /// main.gd:7121-7137) while the core's regen split still pools the
    /// wounds — and still gets the roll at the epoch below. Rules-must-log:
    /// the refusal names the rule ("Disintegrate: Regeneration ignored", the
    /// Bane-in-Melee arm's own line, main.gd:7175-7176).
    #[test]
    fn disintegrate_refuses_the_regeneration_roll_at_46_and_below_still_rolls() {
        let new = disintegrate_volley(&disintegrate_carrier(24, crate::acts::EPOCH_46_DISINTEGRATE_REGEN), false);
        assert!(
            new.caused > 0,
            "fixture seed no longer wounds — pick another"
        );
        assert_eq!(
            new.wounds, new.caused,
            "the Disintegrate wounds never reach the Regeneration pool"
        );
        assert!(
            new.log.iter().any(|l| l.contains("Disintegrate") && l.contains("Regeneration ignored")),
            "rules-must-log: {:?}",
            new.log
        );
        let old = disintegrate_volley(&disintegrate_carrier(24, OLD_EPOCH), false);
        assert!(
            old.wounds < old.caused,
            "below 46 the heal still rolls (caused {}, landed {})",
            old.caused, old.wounds
        );
        assert!(
            old.log.iter().all(|l| !(l.contains("Disintegrate") && l.contains("Regeneration ignored"))),
            "no bypass, no line: {:?}",
            old.log
        );
    }

    /// The melee twin — the table's arm is reach-blind (`_solo_ignores_regen`
    /// answers for the strike phase too, main.gd:6435), so a MELEE weapon
    /// carrying Disintegrate refuses the heal as well.
    #[test]
    fn disintegrate_refuses_the_regeneration_roll_in_melee() {
        let new = disintegrate_volley(&disintegrate_carrier(0, crate::acts::EPOCH_46_DISINTEGRATE_REGEN), true);
        assert!(
            new.caused > 0,
            "fixture seed no longer wounds — pick another"
        );
        assert_eq!(
            new.wounds, new.caused,
            "the melee Disintegrate wounds skip the pool too"
        );
        let old = disintegrate_volley(&disintegrate_carrier(0, OLD_EPOCH), true);
        assert!(
            old.wounds < old.caused,
            "below 46 the melee heal still rolls (caused {}, landed {})",
            old.caused, old.wounds
        );
    }
