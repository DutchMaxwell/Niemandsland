use super::*;

use crate::rules::{Registries, Spell, SpellModifier};
use crate::spell::cast_success_chance;

    // ---- D-MAGIC step 3 (BRIEF_castingmod) — the spell-side
    //      `effect.modifier.casting_mod` family finally lands: 18 catalogue
    //      rows (gf/aof/aofr/aofs/gff, kind "debuff", e.g. "Sky Blaze")
    //      priced at EV 0 were STILL PICKED (best_spell_target accepts
    //      ev 0 > -1) but the stamp wrote nothing a cast roll could read.
    //      From EPOCH_62_CASTING_MOD the debuff lands in the target's
    //      `Mods.casting` snapshot slot and `casting_net_of` folds the
    //      ROUNDED reading into the cast target — the unit-rule ledger's
    //      EPOCH_6 twin, round-at-read per the table (ai_spell.gd:105-130).
    //      -------

    /// The debuff entry the catalogue's 18 rows carry, scaled down to the
    /// printed -1 shape for a hand-checkable number.
    fn casting_debuff(mod_s: f64) -> Spell {
        Spell {
            name: "Hex".into(),
            status: "modeled".into(),
            threshold: 1,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "debuff".into(),
            effect_hits: 0,
            weapon_rules: vec![],
            beneficiary: "target".into(),
            modifier: SpellModifier { present: true, casting_mod: mod_s, ..Default::default() },
            grants_rule: String::new(),
        }
    }

    fn epoch(e: u32) -> Seams {
        Seams { rules_epoch: e, ..Seams::default() }
    }

    /// THE NUMBER: a landed `casting_mod: -1` debuff shifts the enemy
    /// caster's target 4+ -> 5+ (1/2 -> 1/3, the printed drop of 1/6,
    /// ai_spell.gd:105-130) and the snapshot slot carries the scaled write.
    #[test]
    fn a_landed_casting_debuff_lowers_the_targets_cast_net() {
        let statics: Vec<_> = (0..4).map(|_| UnitStatic::default()).collect();
        let mut st = four_unit_line();

        apply_cast_effect(&statics, &mut st, 2, &casting_debuff(-1.0), 1.0, epoch(crate::acts::CURRENT_RULES_EPOCH), None);
        assert_eq!(st.mods[2].casting, -1.0, "the scaled debuff lands in the snapshot slot");

        let seams = epoch(crate::acts::CURRENT_RULES_EPOCH);
        assert_eq!(casting_net_of(&statics, &st, 2, seams), -1, "the snapshot folds into the enemy's cast net");
        assert_eq!(
            (cast_success_chance(0, 0), cast_success_chance(-1, 0)),
            (0.5, 1.0 / 3.0),
            "target 4+ -> 5+: the printed 1/6 drop"
        );
    }

    /// Below the gate NOTHING is written and the net reads flat zero — the
    /// recorded corpus (io.rs exports `mods` into every record) replays
    /// byte-exact.
    #[test]
    fn below_epoch_62_the_snapshot_stays_zero() {
        let statics: Vec<_> = (0..4).map(|_| UnitStatic::default()).collect();
        let mut st = four_unit_line();
        let old = epoch(crate::acts::EPOCH_61_PRECISION_MARKERS);

        apply_cast_effect(&statics, &mut st, 2, &casting_debuff(-1.0), 1.0, old, None);
        assert_eq!(st.mods[2].casting, 0.0, "the gated write never touches the slot");
        assert_eq!(casting_net_of(&statics, &st, 2, old), 0, "below the gate the net is the flat zero");
    }

    /// The half-landed cast rounds AWAY from the caster — the table's
    /// round-at-read: scale 0.5 on a -1 debuff stamps -0.5 in the slot and
    /// folds as -1 (5+), the same shape a D3-weight face of a 1/3 cast
    /// produces in `cast_phase`.
    #[test]
    fn the_snapshot_rounds_at_read_like_the_table() {
        let statics: Vec<_> = (0..4).map(|_| UnitStatic::default()).collect();
        let mut st = four_unit_line();

        apply_cast_effect(&statics, &mut st, 2, &casting_debuff(-1.0), 0.5, epoch(crate::acts::CURRENT_RULES_EPOCH), None);
        assert_eq!(st.mods[2].casting, -0.5, "the scaled expectation rides the slot as a float");
        assert_eq!(
            casting_net_of(&statics, &st, 2, epoch(crate::acts::CURRENT_RULES_EPOCH)),
            -1,
            "round-at-read: -0.5 folds as -1, target 5+"
        );
    }

    /// The catalogue side: "Burn the Heretic" (gf blessed_sisters — the gf
    /// json's casting_mod rows are this and change_disciples' "Shifting
    /// Form", both printed -3) parses its `casting_mod: -3` — until now
    /// `modifier_of` dropped the field on the floor.
    #[test]
    fn burn_the_heretic_parses_its_casting_mod() {
        let root = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
        let mut reg = Registries::new(&root);
        let spells = reg.spells_for("gf", "blessed_sisters");
        let hex = spells
            .iter()
            .find(|s| s.name == "Burn the Heretic")
            .expect("Burn the Heretic is in the gf blessed_sisters book");
        assert!(hex.modifier.present, "the debuff's modifier dict is non-empty");
        assert_eq!(hex.modifier.casting_mod, -3.0, "the printed -3 finally parses");
        assert_eq!(hex.beneficiary, "target", "the stamp belongs to the bearer of the debuff");
    }
