use super::*;

    // --- Wave 6 (port-caster-utility, analysis/CASTER_SEAM_2026-09-14.md row 5 + port 3) ---
    //
    // The cast sub-phase refused every "utility"-kind spell ("an effect kind
    // the sim has no arithmetic for", sim::pick_cast): all 56 castable
    // instances across the five spells_mechanics maps burned their pick and
    // their tokens for nothing, so the net learned those spells as wasted
    // casts. From EPOCH_52_UTILITY_SPELLS the MAPPED archetypes
    // (`spell.rs::utility_archetype_of` — the terrain-hazard grants, the
    // fatigue-on-failed-morale flag and the attacker-side AP records, 47 of
    // the 56 instances) land; the 9 unmapped ones (charging-scoped AP,
    // forced displacement) still skip. The epoch literals here are 51/50/48,
    // never `CURRENT_RULES_EPOCH`.

    use crate::rules::Spell;

    fn utility_spell(name: &str) -> Spell {
        Spell {
            name: name.into(),
            status: "castable".into(),
            threshold: 1,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "utility".into(),
            ..Default::default()
        }
    }

    /// The caster_boost harness shape: unit 0 = a lone Caster holding 2
    /// tokens with ONE utility spell; the enemies sit at 12" (unit 2) and
    /// 9" (unit 3, the nearest — a utility EV prices at 0, so the pick takes
    /// the nearest exactly like a debuff's).
    fn utility_line(name: &str) -> (State, Vec<UnitStatic>) {
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
            spells: vec![utility_spell(name)],
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        (st, vec![caster, UnitStatic::default(), UnitStatic::default(), UnitStatic::default()])
    }

    fn epoch(e: u32) -> Seams {
        Seams { rules_epoch: e, cast_fold: true, hero_attach: true, ..Seams::default() }
    }

    /// THE BOTH-LEGS TEST. NEW leg — epoch 51: the mapped utility spell is
    /// picked and the terrain-hazard grant lands on the nearest enemy (the
    /// move path's own `mods::granted_terrain_debuff` read consumes it).
    /// OLD legs — epoch 50 (the epoch immediately below this bump at rebase
    /// time, the greatsergeant leg in flight) and epoch 48 (this branch's
    /// base): the kind filter still refuses every utility spell, nothing
    /// lands and the purse is untouched. RED before the port: the 51 leg
    /// still skipped the kind.
    #[test]
    fn cursed_stride_marks_the_target_at_52_and_nothing_at_51_50_or_48() {
        // epoch 52.
        let (mut st, statics) = utility_line("Cursed Stride");
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(52), None);
        assert!(
            st.buffs[3].iter().any(|r| &*r.grants_rule == "Dangerous Terrain"),
            "epoch 52: the Dangerous Terrain grant lands on the nearest enemy: {:?}",
            st.buffs[3]
        );

        // epoch 51 — the old leg at rebase time (EPOCH_51_CASTER_INTERFERENCE;
        // no opposing casters here, so the interference pool is empty).
        let (mut st, statics) = utility_line("Cursed Stride");
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(51), None);
        assert!(
            st.buffs[3].is_empty(),
            "epoch 51: the kind filter refuses the utility spell"
        );
        assert_eq!(st.casts[0], 2, "epoch 51: the purse is untouched");

        // epoch 50 — the leg before the interference bump.
        let (mut st, statics) = utility_line("Cursed Stride");
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(50), None);
        assert!(
            st.buffs[3].is_empty(),
            "epoch 50: the kind filter refuses the utility spell"
        );
        assert_eq!(st.casts[0], 2, "epoch 50: the purse is untouched");

        // epoch 48 — the epoch immediately below this branch's base.
        let (mut st, statics) = utility_line("Cursed Stride");
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert!(
            st.buffs[3].is_empty(),
            "epoch 48: the kind filter refuses the utility spell"
        );
    }

    /// The fatigue archetype — "must take a morale test. If failed, it
    /// becomes fatigued" — stamps the same flag `tray_fatigue_debuff` writes,
    /// at cast success (the Quality die is not re-rolled in the expectation
    /// path, the same land-whole shape every spell grant rides). The 48 twin
    /// pins the kind filter.
    #[test]
    fn searing_heat_fatigues_the_target_at_52_and_nothing_at_48() {
        let (mut st, statics) = utility_line("Searing Heat");
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(52), None);
        assert!(
            st.fatigued[3],
            "epoch 52: the forced-morale spell fatigues the nearest enemy"
        );

        let (mut st, statics) = utility_line("Searing Heat");
        let los = vec![true; st.units()];
        cast_phase(
            &statics,
            &mut st,
            0,
            &los,
            Seams { rules_epoch: 48, cast_fold: true, hero_attach: true, ..Seams::default() },
            None,
        );
        assert!(!st.fatigued[3], "epoch 48: the kind filter refuses the utility spell");
    }

    /// The attacker-side AP archetype — "which loses AP(1) when shooting
    /// once" — the exact shape the Piercing Debuff row already rides
    /// (`ctx_live`'s Role::Ap net, dice's `att.ap_mod` fold). The 48 twin.
    #[test]
    fn corrode_weapons_stamps_the_enemy_shooting_ap_row_at_52_and_nothing_at_48() {
        let (mut st, statics) = utility_line("Corrode Weapons");
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(52), None);
        assert!(
            st.buffs[3].iter().any(|r| r.ap_mod == -1 && &*r.scope == "shooting"),
            "epoch 52: the enemy's own shooting attacks lose AP(+1) (the Role::Ap row): {:?}",
            st.buffs[3]
        );

        let (mut st, statics) = utility_line("Corrode Weapons");
        let los = vec![true; st.units()];
        cast_phase(
            &statics,
            &mut st,
            0,
            &los,
            Seams { rules_epoch: 48, cast_fold: true, hero_attach: true, ..Seams::default() },
            None,
        );
        assert!(st.buffs[3].is_empty(), "epoch 48: the kind filter refuses the utility spell");
    }

    /// A FRIENDLY utility takes the caster's unit (the buff convention): the
    /// Elemental Form record lands on unit 0, nowhere else.
    #[test]
    fn elemental_form_arms_the_casters_own_melee_ap_at_52() {
        let (mut st, statics) = utility_line("Elemental Form");
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(52), None);
        assert!(
            st.buffs[0].iter().any(|r| r.ap_mod == 1 && &*r.scope == "melee"),
            "epoch 52: the caster's own unit carries the melee AP(+1) record: {:?}",
            st.buffs[0]
        );
        assert!(st.buffs[3].is_empty(), "no enemy record — the spell targets the friendly side");
    }

    /// The 9 unmapped instances stay skipped: charging-scoped AP (the
    /// ledger's scope reader refuses "charging" records — the GDScript's own
    /// v1 limitation), attackers-side AP when shooting against (no
    /// defender-side AP fold) and the forced 6" displacements (the
    /// expectation path has no geometry to move an enemy unit). Both
    /// spellings of the shadow_leagues entry map (the committed map carries
    /// the book's own "Psy-Emowerment").
    #[test]
    fn the_unmapped_names_stay_unmapped() {
        assert!(crate::spell::utility_archetype_of("Berserker Frenzy").is_none());
        assert!(crate::spell::utility_archetype_of("Furious Frenzy").is_none());
        assert!(crate::spell::utility_archetype_of("Coordinated Aggression").is_none());
        assert!(crate::spell::utility_archetype_of("Deep Hypnosis").is_none());
        assert!(crate::spell::utility_archetype_of("Seductive Invocation").is_none());
        assert!(crate::spell::utility_archetype_of("Psy-Emowerment").is_some());
        assert!(crate::spell::utility_archetype_of("Psy-Empowerment").is_some());
    }
