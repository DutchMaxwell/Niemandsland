//! Rules 3.6 lane AI. Row AI-05b owns the nine spell tokens of the new
//! weapon family: five are priced by the spell damage EV (Purge, Decimate,
//! Obliterate, Reap, Fragment), four stay explicit no-ops (Pierce, Smash,
//! Demolish, Scourge) because the spell EV carries no distance or terrain
//! context. Both twins read the token list off the spell itself.

mod ai_05b {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::rules::{Registries, Spell};
    use crate::spell::{spell_damage_ev, spell_facets};
    use crate::unit::Ctx;

    /// One spell entry the LIVE registry really carries, so the token list
    /// under test is the committed map's own.
    fn live_spell(system: &str, faction: &str, name: &str) -> Spell {
        let mut reg = Registries::new(&repo_root());
        reg.spells_for(system, faction)
            .iter()
            .find(|s| s.name == name)
            .cloned()
            .unwrap_or_else(|| panic!("{system}/{faction} carries no {name}"))
    }

    /// The live path: registry token list -> `spell_facets` -> `spell_damage_ev`.
    fn ev(system: &str, faction: &str, name: &str, epoch: u32, def: &Ctx) -> f64 {
        let spell = live_spell(system, faction, name);
        let hits = spell.effect_hits * spell.target_count.max(1);
        spell_damage_ev(hits, def, &spell_facets(&spell.weapon_rules, epoch))
    }

    fn defender(defense: i64, tough: i64, above_half: bool, shaken: bool) -> Ctx {
        Ctx {
            defense,
            tough,
            models: 1,
            above_half_strength: above_half,
            shaken_or_fatigued: shaken,
            ..Default::default()
        }
    }

    const PURGE: (&str, &str, &str) = ("gf", "blessed_sisters", "Eternal Flame");
    const DECIMATE: (&str, &str, &str) = ("gf", "daemons_of_plague", "Rapid Putrefaction");
    const OBLITERATE: (&str, &str, &str) = ("gf", "daemons_of_lust", "Beautiful Pain");
    const REAP: (&str, &str, &str) = ("gf", "rebel_guerrillas", "Wave of Discord");
    const FRAGMENT: (&str, &str, &str) = ("gf", "alien_hives", "Overwhelming Strike");
    const PIERCE: (&str, &str, &str) = ("gf", "blood_prime_brothers", "Blood Wound");
    const SMASH: (&str, &str, &str) = ("gf", "battle_brothers", "Cerebral Trauma");
    const DEMOLISH: (&str, &str, &str) = ("gf", "machine_cults", "Searing Shrapnel");
    const SCOURGE: (&str, &str, &str) = ("gf", "dwarf_guilds", "Smiting Rune");

    fn eval(s: (&str, &str, &str), epoch: u32, def: &Ctx) -> f64 {
        ev(s.0, s.1, s.2, epoch, def)
    }

    /// Case 1 — every EVALUABLE token moves the EV only while its condition
    /// holds, and the closed condition is exactly the epoch-72 plain spell.
    #[test]
    fn the_evaluable_tokens_price_their_conditions() {
        let shaken = defender(4, 1, false, true);
        let calm = defender(4, 1, false, false);
        assert!((eval(PURGE, EPOCH_73_V36, &shaken) - 2.5).abs() < 1e-9, "Purge AP(+2): 3 × 5/6");
        assert!((eval(PURGE, EPOCH_73_V36, &calm) - 1.5).abs() < 1e-9, "Purge closed: 3 × 1/2");
        assert_eq!(eval(PURGE, EPOCH_73_V36, &calm), eval(PURGE, EPOCH_72_PLAYTEST_RULES, &calm));

        let above = defender(4, 1, true, false);
        assert!((eval(DECIMATE, EPOCH_73_V36, &above) - 14.0 / 9.0).abs() < 1e-9, "Decimate Bane above half");
        assert!((eval(DECIMATE, EPOCH_73_V36, &calm) - 4.0 / 3.0).abs() < 1e-9, "Decimate closed: plain AP(1)");
        assert_eq!(eval(DECIMATE, EPOCH_73_V36, &calm), eval(DECIMATE, EPOCH_72_PLAYTEST_RULES, &calm));

        let tough3 = defender(4, 3, false, false);
        assert!((eval(OBLITERATE, EPOCH_73_V36, &tough3) - 8.0 / 3.0).abs() < 1e-9, "Obliterate vs Tough(3)+");
        assert_eq!(eval(OBLITERATE, EPOCH_73_V36, &calm), eval(OBLITERATE, EPOCH_72_PLAYTEST_RULES, &calm));

        assert!((eval(REAP, EPOCH_73_V36, &shaken) - 8.0 / 3.0).abs() < 1e-9, "Reap while shaken");
        assert_eq!(eval(REAP, EPOCH_73_V36, &calm), eval(REAP, EPOCH_72_PLAYTEST_RULES, &calm));

        let def5 = defender(5, 1, false, false);
        assert!((eval(FRAGMENT, EPOCH_73_V36, &def5) - 32.0 / 9.0).abs() < 1e-9, "Fragment at Defense 5-6");
        assert_eq!(eval(FRAGMENT, EPOCH_73_V36, &calm), eval(FRAGMENT, EPOCH_72_PLAYTEST_RULES, &calm));
    }

    /// Case 2 — Obliterate / Reap / Fragment widen the save window: a
    /// successful save of 5 re-rolls too, so the EV beats the sixes-only leg.
    #[test]
    fn the_widened_window_re_rolls_a_successful_five() {
        let tough3 = defender(4, 3, false, false);
        let ob = eval(OBLITERATE, EPOCH_73_V36, &tough3);
        assert!((ob - 8.0 / 3.0).abs() < 1e-9, "window from 5: {ob}");
        assert!(ob > 7.0 / 3.0 + 1e-9, "the sixes-only leg would stop at 7/3");

        let shaken = defender(4, 1, false, true);
        let reap = eval(REAP, EPOCH_73_V36, &shaken);
        assert!((reap - 8.0 / 3.0).abs() < 1e-9, "Reap window from 5: {reap}");
        assert!(reap > 7.0 / 3.0 + 1e-9, "the sixes-only leg would stop at 7/3");

        let def5 = defender(5, 1, false, false);
        let frag = eval(FRAGMENT, EPOCH_73_V36, &def5);
        assert!((frag - 32.0 / 9.0).abs() < 1e-9, "Fragment window from 5: {frag}");
        assert!(frag > 28.0 / 9.0 + 1e-9, "the sixes-only leg would stop at 28/9");
    }

    /// Case 3 — the four documented no-ops leave the EV on the plain spell
    /// even with every target state they name switched on.
    #[test]
    fn the_four_no_op_tokens_stay_at_the_plain_spell_ev() {
        let loaded = defender(4, 3, true, true);
        for (spell, expected) in [(PIERCE, 4.0), (SMASH, 4.0), (DEMOLISH, 2.0), (SCOURGE, 2.0)] {
            let now = eval(spell, EPOCH_73_V36, &loaded);
            assert!((now - expected).abs() < 1e-9, "{}: {now}", spell.2);
            assert_eq!(now, eval(spell, EPOCH_72_PLAYTEST_RULES, &loaded), "{} must not read the epoch", spell.2);
        }
    }

    /// Case 4 — at epoch 72 every one of the nine is a no-op (no 3.5 spell
    /// spells these tokens). The numbers are pinned.
    #[test]
    fn every_new_token_is_a_no_op_at_epoch_72() {
        let loaded = defender(5, 3, true, true);
        for (spell, expected) in [
            (PURGE, 2.0),
            (DECIMATE, 5.0 / 3.0),
            (OBLITERATE, 8.0 / 3.0),
            (REAP, 2.5),
            (FRAGMENT, 8.0 / 3.0),
            (PIERCE, 5.0),
            (SMASH, 5.0),
            (DEMOLISH, 8.0 / 3.0),
            (SCOURGE, 8.0 / 3.0),
        ] {
            let now = eval(spell, EPOCH_72_PLAYTEST_RULES, &loaded);
            assert!((now - expected).abs() < 1e-9, "{}: {now} vs {expected}", spell.2);
        }
    }

    /// The split is 5 priced / 4 no-ops at 73, and it must be visible on BOTH
    /// twins. This is the core half; the GD twin pins the same list.
    #[test]
    fn the_73_split_is_five_priced_and_four_no_ops() {
        let loaded = defender(5, 3, true, true);
        for (spell, priced) in [
            (PURGE, true),
            (DECIMATE, true),
            (OBLITERATE, true),
            (REAP, true),
            (FRAGMENT, true),
            (PIERCE, false),
            (SMASH, false),
            (DEMOLISH, false),
            (SCOURGE, false),
        ] {
            let now = eval(spell, EPOCH_73_V36, &loaded);
            let old = eval(spell, EPOCH_72_PLAYTEST_RULES, &loaded);
            if priced {
                assert!(now > old + 1e-9, "{} must be priced at 73: {now} vs {old}", spell.2);
            } else {
                assert_eq!(now, old, "{} must stay a no-op at 73", spell.2);
            }
        }
    }
}
