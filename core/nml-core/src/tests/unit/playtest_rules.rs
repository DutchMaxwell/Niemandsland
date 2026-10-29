use super::*;

    // The 29.10.2026 play-test fixes in the core, gated on `EPOCH_72_PLAYTEST_RULES` (the table's
    // #1911 / #1914): A1 a printed Lacerate re-rolls the Defense 6s but keeps the defender's
    // Regeneration roll (only Bane bypasses it); A4 a Deadly(X) wound against the Regeneration
    // family rolls all X dice before the model's cap, in the dice and in the EV. Below 72 every
    // record replays byte-exact. (A2, the wound-triggered morale test, is in tests/sim.)

    use crate::acts::EPOCH_72_PLAYTEST_RULES;
    use crate::dice::{resolve_volley_leg, ShootResult, Shooter, Tray};
    use crate::spell::{spell_damage_ev, spell_facets};

    /// The BANE_HEADER carrier with `unit_rules` on the unit and `rifle_rules` on its rifle.
    fn carrier_at(unit_rules: &str, rifle_rules: &str, epoch: u32) -> UnitStatic {
        let tpl = BANE_HEADER
            .replace("\"special_rules\":[\"Bane in Melee\"]", &format!("\"special_rules\":[{unit_rules}]"))
            .replacen("\"ap\":0,\"rules\":[]},", &format!("\"ap\":0,\"rules\":[{rifle_rules}]}},"), 1);
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
    }

    fn regen_def(playtest_rules: bool) -> Ctx {
        Ctx {
            defense: 4, tough: 1, models: 5,
            regeneration: true, regen_target: 5, regen_target_spell: 5,
            playtest_rules,
            ..Default::default()
        }
    }

    fn close(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-9
    }

    /// OLD leg: at 71 a printed Lacerate (weapon or unit) still carries the Regeneration bypass.
    #[test]
    fn a_printed_lacerate_bypasses_regeneration_at_epoch_71() {
        let weapon = carrier_at("", "\"Lacerate\"", 71);
        assert!(weapon.shoot[0].bane && weapon.shoot[0].bypass_regen, "71 replays the old alias");
        let unit = carrier_at("\"Lacerate\"", "", 71);
        assert!(unit.shoot[0].bane && unit.shoot[0].bypass_regen);
        assert!(unit.melee[0].bane && unit.melee[0].bypass_regen);
        assert!(!regen_def_at(71).playtest_rules, "the stamp follows the record's epoch");
    }

    fn regen_def_at(epoch: u32) -> Ctx {
        carrier_at("", "", epoch).ctx
    }

    /// NEW leg (A1): from 72 the re-roll stays and the bypass goes; Bane keeps it.
    #[test]
    fn lacerate_keeps_regeneration_from_epoch_72_and_bane_still_bypasses() {
        let e = EPOCH_72_PLAYTEST_RULES;
        assert!(regen_def_at(e).playtest_rules);
        let weapon = carrier_at("", "\"Lacerate\"", e);
        assert!(weapon.shoot[0].bane, "the Defense-6 re-roll stays");
        assert!(!weapon.shoot[0].bypass_regen, "A1: a weapon's Lacerate keeps Regeneration");
        let unit = carrier_at("\"Lacerate\"", "", e);
        assert!(unit.shoot[0].bane && !unit.shoot[0].bypass_regen, "A1: the unit-level Lacerate too");
        assert!(unit.melee[0].bane && !unit.melee[0].bypass_regen);
        assert!(carrier_at("", "\"Bane\"", e).shoot[0].bypass_regen, "a printed Bane bypasses");
        assert!(carrier_at("\"Bane\"", "", e).shoot[0].bypass_regen, "a carried Bane bypasses");
        assert!(carrier_at("\"Bane\"", "\"Lacerate\"", e).shoot[0].bypass_regen, "Bane on the unit wins");
    }

    /// A1 in the spell EV: 6 hits at Defense 4+ with the 6s re-rolled let 6 × 7/12 through; from 72
    /// Regeneration (5+) keeps 2/3 of them against Lacerate, never against Bane.
    #[test]
    fn a_lacerate_spell_keeps_regeneration_from_epoch_72() {
        let through = 6.0 * (1.0 - 5.0 / 12.0);
        let lacerate = spell_facets(&["Lacerate".to_string()]);
        assert!(close(spell_damage_ev(6, &regen_def(false), &lacerate), through), "below 72: bypass");
        assert!(close(spell_damage_ev(6, &regen_def(true), &lacerate), through * 2.0 / 3.0));
        let bane = spell_facets(&["Bane".to_string()]);
        assert!(close(spell_damage_ev(6, &regen_def(true), &bane), through), "Bane bypasses");
    }

    /// A4 in the EV (weapon and spell): Deadly(3) on a 1-wound Regeneration (5+) model is worth
    /// 1 - (1/3)^3 = 26/27 per unsaved wound from 72 (all three rolls must succeed); at 71 the
    /// capped single roll, 2/3. Tough(3) never bites the cap: unchanged.
    #[test]
    fn deadly_against_regeneration_is_priced_roll_then_cap_from_epoch_72() {
        let att = Ctx { quality: 4, models: 5, ..Default::default() };
        let p = ShootProfile { attacks: 10, range: 24, deadly: 3, ..Default::default() };
        let ev = |d: &Ctx| crate::combat::profile_ev(&p, 10, &att, d, 12.0, false);
        assert!(close(ev(&regen_def(false)), 2.5 * 2.0 / 3.0), "at 71: one die on the capped wound");
        assert!(close(ev(&regen_def(true)), 2.5 * 26.0 / 27.0), "from 72: three dice");
        assert!(close(ev(&Ctx { tough: 3, ..regen_def(true) }), 2.5 * 3.0 * 2.0 / 3.0));
        let d3 = spell_facets(&["Deadly(3)".to_string()]);
        assert!(close(spell_damage_ev(6, &regen_def(false), &d3), 3.0 * 2.0 / 3.0));
        assert!(close(spell_damage_ev(6, &regen_def(true), &d3), 3.0 * 26.0 / 27.0));
    }

    /// A4 in the dice: the same seeded volley rolls ONE Regeneration batch on the raw unsaved count
    /// at 71 (one group ×3), and three dice per unsaved wound from 72 (one group per wound, each
    /// landing what its three dice let through).
    #[test]
    fn deadly_rolls_three_regeneration_dice_per_wound_from_epoch_72() {
        let att = Ctx { quality: 2, models: 1, ..Default::default() };
        let p = [ShootProfile { name: "Rifle".into(), attacks: 4, count: 1, range: 24, deadly: 3, ..Default::default() }];
        let run = |def: &Ctx| -> ShootResult {
            let one = [Shooter { profiles: &p, keep: &[0], attacks: &[4], att: &att, owner: "" }];
            let mut tray = Tray::seeded(27);
            resolve_volley_leg(&one, def, "", 12.0, 12.0, true, true, true, true, true, false, &|_| false, &mut tray)
        };
        let regen = |r: &ShootResult| -> Vec<i64> { r.rolls.iter().filter(|x| x.target == 5).map(|x| x.count).collect() };
        let old = run(&Ctx { defense: 6, ..regen_def(false) });
        let w = old.deadly_tally;
        assert!(w >= 2, "fixture seed no longer wounds twice — pick another");
        assert_eq!(regen(&old), vec![w], "at 71: one die per RAW unsaved wound");
        assert_eq!(old.deadly_groups.len(), 1);
        assert_eq!(old.deadly_groups[0].1, 3);
        let new = run(&Ctx { defense: 6, ..regen_def(true) });
        assert_eq!(new.deadly_tally, w, "the saves are the same dice");
        assert_eq!(regen(&new), vec![3; w as usize], "from 72: three dice per wound");
        assert!(new.deadly_groups.iter().all(|&(n, m)| n == 1 && (1..=3).contains(&m)));
    }
