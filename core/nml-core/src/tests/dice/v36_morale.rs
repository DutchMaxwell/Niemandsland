//! Rules 3.6 lane morale tests for the dice module; owned by lane morale.

mod mor_17a {
    //! MOR-17a: Warding, Knightborn and Angelic Blessing are one rule. From `EPOCH_73_V36` a non-spell
    //! wound is ignored on a 6+ only when the unit was shot from over 9" or charged from over 6"; a
    //! spell wound on a 2+. Below 73 the old map entry stands (6+ at any distance, 4+ vs spells). The
    //! stamp lives in `unit::regen_targets`; the legs compare the distance gates here. The GDScript
    //! twin of these cases is test/v36/mor_17a_test.gd.
    use super::super::*;
    use crate::spell::{spell_damage_ev, spell_facets};

    /// The Knightborn / Warding carrier as `regen_targets` stamps it at 73.
    fn warding(defense: i64, models: i64) -> Ctx {
        Ctx { regeneration: true, regen_target: 6, regen_target_spell: 2,
            regen_gate_over_in: 9.0, regen_gate_charge_in: 6.0, ..defender(defense, models) }
    }

    /// The same unit BELOW 73: the old entry's target, no gate (0.0 = the older reading).
    fn warding_below_73(defense: i64, models: i64) -> Ctx {
        Ctx { regeneration: true, regen_target: 6, regen_target_spell: 4, regen_gate_over_in: 0.0,
            regen_gate_charge_in: 0.0, ..defender(defense, models) }
    }

    /// One 64-attack volley from a Quality 2 shooter at `d` inches.
    fn shot(def: &Ctx, d: f64) -> ShootResult {
        let profiles = [rifle(64)];
        let att = shooter(2);
        let squad = [Shooter { profiles: &profiles, keep: &[0], attacks: &[64], att: &att,
            owner: "Archers" }];
        let mut tray = Tray::seeded(27);
        resolve_volley_with_tray(&squad, def, "Knightborn Squad", d, d, true, true, true, true,
            &mut tray)
    }

    /// One 64-attack melee strike from a Quality 2 striker; `charge_from_in` is the pre-charge gap.
    fn melee(def: &Ctx, charging: bool, charge_from_in: f64) -> ShootResult {
        let profiles = [blade(64)];
        let att = shooter(2);
        let strikers = [striker(&profiles, &[0], &[64], &att)];
        let mut tray = Tray::seeded(27);
        resolve_melee_leg(&strikers, def, "Knightborn Squad", charging, false, false, false,
            charge_from_in, false, false, false, false, &mut tray)
    }

    /// The Regeneration-family dice this resolution actually rolled (`target == 6` is the 6+ ignore;
    /// the defender's saves run at its own Defense 4 here, so nothing else draws at 6).
    fn regen_dice(out: &ShootResult) -> i64 {
        out.rolls.iter().filter(|r| r.kind != "defense" && r.target == 6).map(|r| r.count).sum()
    }

    fn logged(out: &ShootResult, line: &str) -> bool {
        out.log.iter().any(|l| l == line)
    }

    #[test]
    fn knightborn_ignores_shot_wounds_from_over_nine_inches_at_epoch_73_and_72() {
        let now = shot(&warding(4, 8), 12.0);
        assert!(regen_dice(&now) > 0, "12in: the 6+ ignore must roll: {:?}", now.rolls);
        assert!(logged(&now, "Warding: Knightborn Squad ignores wounds on 6+ (shot from over 9in)"));
        let before = shot(&warding_below_73(4, 8), 12.0);
        assert_eq!(regen_dice(&before), regen_dice(&now), "past the gate 73 rolls what 72 rolled");
        assert_eq!(before.wounds, now.wounds);
    }

    #[test]
    fn knightborn_rolls_no_6_ignore_when_shot_from_within_nine_inches_at_epoch_73() {
        let now = shot(&warding(4, 8), 5.0);
        let before = shot(&warding_below_73(4, 8), 5.0);
        assert_eq!(regen_dice(&now), 0, "5in: no 6+ die of this kind at 73: {:?}", now.rolls);
        assert!(now.wounds > before.wounds, "the gate costs the ignore: {} vs {}", now.wounds, before.wounds);
        assert!(logged(&now, "Warding: no 6+ ignore, Knightborn Squad was shot from within 9in"));
    }

    #[test]
    fn knightborn_rolls_the_6_ignore_at_any_shot_distance_at_epoch_72() {
        let before = shot(&warding_below_73(4, 8), 5.0);
        assert!(regen_dice(&before) > 0, "72 keeps today's reading: {:?}", before.rolls);
        assert!(!before.log.iter().any(|l| l.starts_with("Warding")), "below 73 the rule is silent");
    }

    #[test]
    fn knightborn_ignores_charge_wounds_only_from_over_six_inches_at_epoch_73() {
        let far = melee(&warding(4, 8), true, 8.0);
        assert!(regen_dice(&far) > 0, "charged from 8in: the 6+ ignore rolls: {:?}", far.rolls);
        assert!(logged(&far, "Warding: Knightborn Squad ignores wounds on 6+ (charged from over 6in)"));
        let near = melee(&warding(4, 8), true, 4.0);
        assert_eq!(regen_dice(&near), 0, "charged from 4in: no 6+ die: {:?}", near.rolls);
        assert!(logged(&near, "Warding: no 6+ ignore, Knightborn Squad was charged from within 6in"));
        let charged_us = melee(&warding(4, 8), false, 0.0);
        assert_eq!(regen_dice(&charged_us), 0, "we charged: the enemy was not charged from range");
    }

    #[test]
    fn knightborn_ignores_charge_wounds_at_any_distance_at_epoch_72() {
        let before = melee(&warding_below_73(4, 8), true, 4.0);
        assert!(regen_dice(&before) > 0, "72 keeps today's reading: {:?}", before.rolls);
    }

    #[test]
    fn a_spell_wound_is_ignored_on_2_at_73_and_on_4_at_72() {
        let f = spell_facets(&[]);
        let now = spell_damage_ev(10, &warding(4, 8), &f);
        let before = spell_damage_ev(10, &warding_below_73(4, 8), &f);
        assert!(now < before, "2+ vs 4+: {now} vs {before}");
        assert!((now - 5.0 / 6.0).abs() < 1e-9, "2+ ignores 5/6 of 5 unsaved: {now}");
    }

    /// CONTROL — a plain Regeneration unit (5+, no gate) is untouched by the row at either distance.
    #[test]
    fn plain_regeneration_is_unchanged_at_both_distances() {
        let plain = Ctx { regeneration: true, regen_target: 5, ..defender(4, 8) };
        let near = shot(&plain, 5.0);
        let far = shot(&plain, 12.0);
        assert!(regen_dice(&far) == 0 && regen_dice(&near) == 0, "5+ never draws at 6");
        assert_eq!(shot(&plain, 5.0).wounds, near.wounds);
        let faces_near: Vec<u8> = near.rolls.iter().flat_map(|r| r.faces.clone()).collect();
        let faces_far: Vec<u8> = far.rolls.iter().flat_map(|r| r.faces.clone()).collect();
        assert_eq!(faces_near, faces_far, "the same dice at either distance");
        assert!(!near.log.iter().any(|l| l.starts_with("Warding")), "a plain carrier never logs Warding");
    }
}
