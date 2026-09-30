use super::*;

    // --- D-MAGIC telemetry (analysis/CAST_FORK_2026-09-16.md Finding 2) ---
    //
    // `selfplay._spells_by_kind_tally` (selfplay.py:1440) and its GDScript
    // twin (core_selfplay.gd:74-81) count `state["cast_events"]` entries'
    // "kind" from the pre-apply mark. The core pushes ONE attempt event per
    // cast (the table's `_cast_phase` shape, castparity step 4) carrying the
    // spell's own `effect_kind` ("damage" | "buff" | "debuff" | "utility"), the
    // same strings the GDScript table's `by_kind` keys carry (unknown kinds are
    // skipped by both counters); the rules-must-log lines carry no kind, so a
    // conduit/boost/interference cast still counts once. The epoch literals
    // here are 48/47, never
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

    /// The kind of every cast ATTEMPT event (the entries carrying a `spell`) —
    /// what the tally counts. Log lines carry no kind.
    fn kinds(st: &State) -> Vec<&str> {
        st.cast_events
            .iter()
            .filter(|e| e.get("spell").is_some())
            .map(|e| e["kind"].as_str().unwrap_or(""))
            .collect()
    }

    /// The table's event shape, key for key (battle_sim.gd `_cast_phase`): a
    /// plain cast (no conduit, no boost, no interference) pushes exactly ONE
    /// entry, the attempt, and log lines carry no `kind` for the tally to count.
    #[test]
    fn a_plain_cast_pushes_one_attempt_event_in_the_tables_shape() {
        let (mut st, statics) = lone_caster(vec![bolt()]);
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, Seams { cast_fold: true, hero_attach: true, ..Seams::default() }, None);
        assert_eq!(st.cast_events.len(), 1, "one attempt, no log lines: {:?}", st.cast_events);
        let ev = &st.cast_events[0];
        let mut keys: Vec<&str> = ev.as_object().unwrap().keys().map(|k| k.as_str()).collect();
        keys.sort();
        assert_eq!(keys, ["boost", "cost", "interference", "kind", "p_success", "spell", "target"]);
        assert_eq!(ev["spell"], "bolt");
        assert_eq!(ev["kind"], "damage");
        assert_eq!(ev["cost"], 0, "the bolt's own threshold");
        assert!(ev["target"] == st.roster.keys[2].as_str() || ev["target"] == st.roster.keys[3].as_str(), "an enemy key: {ev}");
        assert_eq!(ev["boost"], 0);
        assert_eq!(ev["interference"], 0);
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
