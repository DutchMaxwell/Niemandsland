use super::*;

    // --- D-MAGIC telemetry (analysis/CAST_FORK_2026-09-16.md Finding 2) ---
    //
    // `selfplay._spells_by_kind_tally` (selfplay.py:1440) and its GDScript
    // twin (core_selfplay.gd:74-81) count `state["cast_events"]` entries'
    // "kind" stamp from the pre-apply mark. The core's cast sub-phase pushed
    // its rules-must-log lines with "rule"/"log" only, so every kind read ""
    // and the tally was structurally zero. The stamp: the spell's own
    // `effect_kind` ("damage" | "buff" | "debuff" | "utility"), the same
    // strings the GDScript table's `by_kind` keys carry (unknown kinds are
    // skipped by both counters). The epoch literals here are 48/47, never
    // `CURRENT_RULES_EPOCH`.

    use crate::acts::EPOCH_48_CASTER_BOOST;
    use crate::rules::{Spell, SpellModifier};

    fn def4() -> UnitStatic {
        UnitStatic {
            ctx: crate::unit::Ctx { defense: 4, ..Default::default() },
            ..UnitStatic::default()
        }
    }

    fn bolt() -> Spell {
        Spell {
            name: "bolt".into(),
            status: "modeled".into(),
            threshold: 0,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "damage".into(),
            effect_hits: 1,
            weapon_rules: vec![],
            beneficiary: String::new(),
            modifier: SpellModifier::default(),
            grants_rule: String::new(),
        }
    }

    fn blessing() -> Spell {
        Spell {
            name: "blessing".into(),
            status: "modeled".into(),
            threshold: 0,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "buff".into(),
            effect_hits: 0,
            weapon_rules: vec![],
            beneficiary: String::new(),
            modifier: SpellModifier::default(),
            grants_rule: String::new(),
        }
    }

    /// The caster_boost fixture's lone-caster board: unit 0 a lone Caster
    /// holding 2 tokens (threshold 0, so both are leftover and the boost leg
    /// pays and logs), units 1-3 lend nothing, enemies sit at Defense 4 with
    /// fat wound pools so the walk never kills the pick mid-flight.
    fn lone_caster(book: Vec<Spell>) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.casts = vec![2, 0, 0, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.wounds = vec![vec![1], vec![1], vec![9], vec![9]];
        let mut list = st.profiles.list.clone();
        list.extend_from_slice(&[list[0].clone(), list[0].clone(), list[0].clone()]);
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![0, 1, 2, 3],
        });
        let caster = UnitStatic {
            is_caster: true,
            spells: book,
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        (st, vec![caster, UnitStatic::default(), def4(), def4()])
    }

    fn epoch(e: u32) -> Seams {
        // The fold gate is `caster_of`'s own — the cast leg rides the same
        // chain resolution the cast sub-phase already needs.
        Seams { rules_epoch: e, cast_fold: true, hero_attach: true, ..Seams::default() }
    }

    fn kinds(st: &State) -> Vec<&str> {
        st.cast_events
            .iter()
            .map(|e| e["kind"].as_str().unwrap_or(""))
            .collect()
    }

    /// THE STAMP TEST. A caster that casts ONE damage spell (one activation,
    /// the damage book) and ONE buff spell (a second activation, the buff
    /// book) leaves cast_events whose "kind" values are exactly
    /// ["damage", "buff"]. RED before the stamp: the pushed lines carry
    /// "rule"/"log" only, every kind reads "".
    #[test]
    fn a_casting_activation_stamps_the_spells_kind_on_its_cast_events() {
        let (mut st, statics) = lone_caster(vec![bolt()]);
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_48_CASTER_BOOST), None);
        assert_eq!(
            st.casts[0], 0,
            "the boost leg paid the activation's tokens: {:?}",
            st.casts
        );
        let mut seen = kinds(&st);
        assert_eq!(
            seen,
            vec!["damage"],
            "the damage cast's entries carry its kind (RED before the stamp): {:?}",
            st.cast_events
        );

        let (mut st, statics) = lone_caster(vec![blessing()]);
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_48_CASTER_BOOST), None);
        seen.extend(kinds(&st));
        assert_eq!(
            seen,
            vec!["damage", "buff"],
            "one damage cast and one buff cast stamp exactly their kinds: {:?}",
            st.cast_events
        );
    }

    /// The tally reads kinds off EVERY new entry from its pre-apply mark, so
    /// no entry may carry a kind that is not the cast's own — and a cast that
    /// logs through the conduit rides the SAME stamp the plain path would.
    #[test]
    fn the_stamp_is_the_spells_own_effect_kind_not_something_else() {
        // A debuff and a utility spell: the pick's own kind strings, whatever
        // the book carries, land verbatim on the pushed entries.
        let mut hex = bolt();
        hex.name = "hex".into();
        hex.effect_kind = "debuff".into();
        let (mut st, statics) = lone_caster(vec![hex]);
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_48_CASTER_BOOST), None);
        assert_eq!(
            kinds(&st),
            vec!["debuff"],
            "the debuff cast stamps \"debuff\": {:?}",
            st.cast_events
        );
    }
