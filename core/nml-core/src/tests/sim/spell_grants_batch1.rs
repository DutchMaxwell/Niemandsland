use super::*;

    // --- Step 5 pins (option B-plus): the spell-grant landing is ALREADY
    // SHIPPED — the ungated DEFECT_LEDGER #33 push (apply_cast_effect, live
    // since E2) writes the once-LiveMod for every buff/debuff carrying
    // `grants_rule`, and `mods::granted` reads it. These tests PIN that
    // shipped behaviour: no epoch bump, no scope carriage — a later brief
    // owns both. The rules-must-log trace on the push is verified by hand
    // (NML_TRACE_RULES=1), like every other trace line in this crate.

    use crate::rules::Spell;

    /// A castable BUFF carrying one of the batch-1 grant names.
    fn grant_spell(name: &str, grant: &str) -> Spell {
        Spell {
            name: name.into(),
            status: "castable".into(),
            threshold: 1,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "buff".into(),
            grants_rule: grant.into(),
            ..Default::default()
        }
    }

    /// The utility_line harness shape: unit 0 = a lone Caster holding 2 tokens
    /// with ONE buff spell; the enemies sit at 12" (unit 2) and 9" (unit 3).
    /// A buff targets the caster's own unit (unit 0).
    fn grant_line(name: &str, grant: &str) -> (State, Vec<UnitStatic>) {
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
        let mut caster = UnitStatic {
            is_caster: true,
            spells: vec![grant_spell(name, grant)],
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        caster.name = "Caster".into();
        (st, vec![caster, UnitStatic::default(), UnitStatic::default(), UnitStatic::default()])
    }

    fn epoch(e: u32) -> Seams {
        Seams { rules_epoch: e, cast_fold: true, hero_attach: true, ..Seams::default() }
    }

    /// The shipped landing: the cast leaves `granted` true and the record's
    /// once-shape untouched — and the first exchange spends it, so nothing
    /// survives into the next round. Epoch 62 is the shipped epoch: the push
    /// is ungated, exactly as it has been since E2.
    #[test]
    fn a_landed_grant_buff_is_true_until_the_first_exchange_spends_it() {
        let (mut st, statics) = grant_line("Drain Spirit", "Unstoppable");
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(62), None);
        assert!(st.buffs[0].iter().any(|r| &*r.grants_rule == "Unstoppable" && r.once),
            "the shipped landing carries the once-grant record: {:?}", st.buffs[0]);
        assert!(crate::mods::granted(&st, 0, "Unstoppable"),
            "the shipped landing leaves the grant live at the current epoch");

        crate::mods::spend_once(&mut st, 0, &[crate::mods::Role::Grant], true);
        assert!(!crate::mods::granted(&st, 0, "Unstoppable"),
            "the first exchange spends the once grant — live until it is spent, gone after");
    }

    /// All six batch-1 names land and read through the same shipped chain
    /// (one real catalogue spell per grant, cast at the current epoch).
    const SPELL_FOR: [(&str, &str); 6] = [
        ("Unstoppable", "Drain Spirit"),
        ("Evasive", "Blood Dome"),
        ("Melee Evasion", "Blissful Dance"),
        ("Rapid Rush", "Spirit Wind"),
        ("Regeneration", "Rapid Mending"),
        ("Resistance", "Battle Guts"),
    ];

    #[test]
    fn every_batch1_name_lands_and_reads_through_granted() {
        for (rule, spell) in SPELL_FOR {
            let (mut st, statics) = grant_line(spell, rule);
            let los = vec![true; st.units()];
            cast_phase(&statics, &mut st, 0, &los, epoch(62), None);
            assert!(crate::mods::granted(&st, 0, rule), "{spell}'s {rule} grant lands and reads");
        }
    }

    /// The catalogue's own instance counts over the four spells_mechanics
    /// maps — the pin that keeps the batch-1 surface exactly as measured
    /// (128 instances; a catalogue change breaks this loudly).
    const CATALOGUE_COUNTS: [(&str, usize); 6] = [
        ("Unstoppable", 28),
        ("Evasive", 26),
        ("Melee Evasion", 20),
        ("Rapid Rush", 12),
        ("Regeneration", 10),
        ("Resistance", 7),
    ];

    #[test]
    fn the_catalogue_carries_the_batch1_counts() {
        let mut counts: HashMap<&str, usize> = HashMap::new();
        for s in ["aof", "aofs", "gf", "gff"] {
            let path = format!("{}/assets/solo/spells_mechanics_{s}.json", repo_root());
            let v: serde_json::Value =
                serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
            for (_, fv) in v.get("factions").unwrap().as_object().unwrap() {
                for e in fv.get("spells").unwrap().as_array().unwrap() {
                    let g = e
                        .get("effect")
                        .and_then(|e| e.get("grants_rule"))
                        .and_then(|g| g.as_str())
                        .unwrap_or("");
                    if let Some((name, _)) = CATALOGUE_COUNTS.iter().find(|(n, _)| *n == g) {
                        *counts.entry(name).or_default() += 1;
                    }
                }
            }
        }
        for (name, n) in CATALOGUE_COUNTS {
            assert_eq!(counts.get(name).copied().unwrap_or(0), n,
                "{name}: the four maps carry {n} instances");
        }
    }
