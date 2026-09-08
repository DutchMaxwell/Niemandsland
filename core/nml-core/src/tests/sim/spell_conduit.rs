use super::*;

    // --- Spell Conduit PR 2 (design #824 §4, core: candidate + replay) ---
    //
    // "Spell Conduit": "Friendly casters within X" may cast as if standing at
    // this unit's position (the spell's range and line of sight are measured
    // THERE, with the rule's casting bonus), as long as this unit isn't
    // Shaken." Table: the engine's spell_candidates origin walk
    // (solo_controller.gd:4405-4414) and PR 1's mirror-SIM twin + record
    // (battle_sim.gd `_cast_origins`, the cast act's `origin` key, #826).
    // Core seam: the cast candidate's origin (sim.rs pick_cast/
    // best_spell_target) and the +1 that rides it, behind the frozen
    // EPOCH_7_TABLE_RULES. The epoch literals here are 7/6, never
    // CURRENT_RULES_EPOCH.

    use crate::rules::{Spell, SpellModifier};

    /// One 12" damage bolt, threshold 2 — the PR 1 fixture's damage spell.
    fn bolt() -> Spell {
        Spell {
            name: "bolt".into(),
            status: "modeled".into(),
            threshold: 2,
            range_in: 12.0,
            target_count: 1,
            effect_kind: "damage".into(),
            effect_hits: 3,
            weapon_rules: vec![],
            beneficiary: String::new(),
            modifier: SpellModifier::default(),
            grants_rule: String::new(),
        }
    }

    /// The REAL registry product (`build_for`): a single-model gf
    /// "alien_hives" unit whose only rule is "Spell Conduit" (the committed
    /// gf map fields it with range_in 12, casting_mod 1, requires_not_shaken
    /// true — the same entry PR 1's fixture resolves). Built through the
    /// registry so the RED run (no stamp yet) answers a PLAIN unit and every
    /// conduit test fails for the right reason.
    fn conduit_bearer(name: &str, epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "c".into(),
            name: name.into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Spell Conduit".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "alien_hives".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// Caster `a` (2 tokens, the bolt) at 0", the ONLY enemy at `enemy_x`
    /// (a deep 1000-wound pool so the walk never kills it mid-flight), and
    /// two friendly slots: c1 at `c1.0"`, c2 at `c2.0"` — `(x, true)` a
    /// conduit bearer, `(x, false)` a plain unit, `None` dead. With the bolt
    /// at 12", a 20" enemy is reachable ONLY through a conduit at 12" or
    /// nearer to it; a 10" enemy is reachable from the caster itself.
    fn conduit_line(
        enemy_x: f64,
        c1: Option<(f64, bool)>,
        c2: Option<(f64, bool)>,
        epoch: u32,
    ) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.player = vec![0, 0, 1, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.positions[1] = vec![[c1.map_or(40.0, |(x, _)| x) * IN2M, 0.0, 0.0]];
        st.positions[2] = vec![[enemy_x * IN2M, 0.0, 0.0]];
        st.positions[3] = vec![[c2.map_or(42.0, |(x, _)| x) * IN2M, 0.0, 0.0]];
        st.alive[1] = c1.is_some() as i64;
        st.alive[3] = c2.is_some() as i64;
        st.casts = vec![2, 0, 0, 0];
        st.wounds[2] = vec![1000];
        st.wound_frac[2] = 0.0;
        let mut caster = UnitStatic { name: "a".into(), ..Default::default() };
        caster.is_caster = true;
        caster.spells = vec![bolt()];
        caster.casts_per_round = 2;
        let stat = |o: Option<(f64, bool)>, name: &str| match o {
            Some((_, true)) => conduit_bearer(name, epoch),
            _ => UnitStatic { name: name.into(), ..Default::default() },
        };
        (st, vec![caster, stat(c1, "c1"), UnitStatic { name: "b".into(), ..Default::default() }, stat(c2, "c2")])
    }

    /// One cast sub-phase on a clone, at the given record epoch.
    fn run(st: &State, statics: &[UnitStatic], epoch: u32) -> State {
        let mut next = st.clone();
        let los = vec![true; st.units()];
        cast_phase(statics, &mut next, 0, &los, Seams { rules_epoch: epoch, ..Seams::default() }, None);
        next
    }

    /// Wounds landed on the deep-pool enemy (the cast EV, unscaled by the pool).
    fn damage(s: &State) -> f64 {
        (1000.0 - s.wounds[2][0] as f64) + s.wound_frac[2]
    }

    /// Rules-must-log: some cast_events line names `needle`.
    fn logged(s: &State, needle: &str) -> bool {
        s.cast_events.iter().any(|e| e["log"].as_str().map_or(false, |l| l.contains(needle)))
    }

    /// (a) A target reachable ONLY from the conduit is legal WITH a conduit
    /// (the cast pays, lands and names the conduit) and illegal WITHOUT one
    /// (today's reading: the caster's own 20" gap is twice the bolt's reach).
    #[test]
    fn a_target_only_the_conduit_reaches_is_legal_at_epoch_7_not_without() {
        let (st, statics) = conduit_line(20.0, Some((12.0, true)), None, 7);
        let next = run(&st, &statics, 7);
        assert_eq!(next.casts[0], 0, "RED: the only target is 20\" out — unreachable from the caster");
        assert!(damage(&next) > 0.0, "the cast lands through the conduit");
        assert!(logged(&next, "Spell Conduit") && logged(&next, "c1"),
            "rules-must-log: the line names the rule and the conduit origin: {:?}",
            next.cast_events);

        let (st, statics) = conduit_line(20.0, Some((12.0, false)), None, 7);
        let next = run(&st, &statics, 7);
        assert_eq!(next.casts[0], 2, "no conduit, no cast: the target stays illegal");
        assert_eq!(damage(&next), 0.0);
    }

    /// (b) Two conduits: the FIRST REACHABLE origin in walk order is the
    /// cast's origin — never EV-shopping over origins (the official walk).
    #[test]
    fn two_conduits_pick_the_first_reachable_origin() {
        // c1 (12") reaches the 20" enemy, c2 (4") does not (16" out): the
        // walk's first REACHABLE entry is c1, though c2 sits nearer the caster.
        let (st, statics) = conduit_line(20.0, Some((12.0, true)), Some((4.0, true)), 7);
        let next = run(&st, &statics, 7);
        assert_eq!(next.casts[0], 0);
        assert!(logged(&next, "c1") && !logged(&next, "c2"),
            "the first reachable origin is the cast's origin: {:?}", next.cast_events);

        // Both reach (enemy at 14"): still c1 — the walk order, not the EV.
        let (st, statics) = conduit_line(14.0, Some((12.0, true)), Some((4.0, true)), 7);
        let next = run(&st, &statics, 7);
        assert_eq!(next.casts[0], 0);
        assert!(logged(&next, "c1") && !logged(&next, "c2"),
            "both reach — the walk's first entry wins: {:?}", next.cast_events);
    }

    /// (c) The PR 1 record's replay: a cast whose origin is the conduit's
    /// position lands on the recorded target at the recorded chance — the
    /// rule's +1 RIDES the origin (success_chance(3), not the flat 4+).
    #[test]
    fn the_recorded_origin_cast_replays_on_the_recorded_target_and_chance() {
        let (st, statics) = conduit_line(20.0, Some((12.0, true)), None, 7);
        let next = run(&st, &statics, 7);
        let ctx = ctx_of(&statics[2], &st, 2);
        let ev = spell_damage_ev_of(&bolt(), &ctx);
        let riden = (1.0 / 3.0) * cast_success_chance(1) * ev;
        let flat = (1.0 / 3.0) * cast_success_chance(0) * ev;
        assert!((damage(&next) - riden).abs() < 1e-9,
            "the landed EV is the +1-riden chance (the record's p_success): got {} want {}",
            damage(&next), riden);
        assert!((riden - flat).abs() > 1e-6, "the discriminator is live: riden {riden} vs flat {flat}");
        assert_eq!(next.wounds[0], st.wounds[0], "the caster itself takes nothing");
    }

    /// (d) An epoch-6 record replays byte-identical with a conduit present:
    /// the seam is gated on the RECORD's epoch and the stamp on its own —
    /// either below 7 and the walk never runs.
    #[test]
    fn an_epoch_6_record_replays_byte_identical_with_a_conduit_present() {
        let (st, statics) = conduit_line(20.0, Some((12.0, true)), None, 7);
        let next = run(&st, &statics, 6);
        assert_eq!(next.casts, st.casts, "below the gate the origin walk never runs");
        assert_eq!(damage(&next), 0.0);
        assert!(next.cast_events.is_empty());

        // The other half: statics stamped at 6 (no flag) replaying at 7.
        let (st, statics) = conduit_line(20.0, Some((12.0, true)), None, 6);
        let next = run(&st, &statics, 7);
        assert_eq!(next.casts, st.casts, "a record stamped below 7 keeps the flag inert");
        assert_eq!(damage(&next), 0.0);
    }

    /// (e) No conduit (a plain friendly at the same spot, or the bearer
    /// simply out of the caster's reach): the caster's own origin is
    /// unchanged — the flat chance, zero new bytes.
    #[test]
    fn no_conduit_leaves_the_caster_origin_bytes_unchanged() {
        // The caster reaches the 10" enemy itself: its own origin is first in
        // the walk, with or without an eligible conduit standing nearby.
        let (st_plain, s_plain) = conduit_line(10.0, Some((4.0, false)), None, 7);
        let (st_cond, s_cond) = conduit_line(10.0, Some((4.0, true)), None, 7);
        let next_plain = run(&st_plain, &s_plain, 7);
        let next_cond = run(&st_cond, &s_cond, 7);
        assert_eq!(next_plain.casts, next_cond.casts, "the caster's own origin wins the walk");
        assert_eq!(damage(&next_plain), damage(&next_cond), "byte-identical landed EV");
        assert!(next_cond.cast_events.is_empty(), "no conduit rode the cast, nothing logs");

        let ctx = ctx_of(&s_cond[2], &st_cond, 2);
        let flat = (1.0 / 3.0) * cast_success_chance(0) * spell_damage_ev_of(&bolt(), &ctx);
        assert!((damage(&next_cond) - flat).abs() < 1e-9, "the flat chance, not the +1");

        // And a bearer PAST the rule's own 12" reach is no origin at all.
        let (st_far, s_far) = conduit_line(20.0, Some((13.0, true)), None, 7);
        let next_far = run(&st_far, &s_far, 7);
        assert_eq!(next_far.casts[0], 2, "past the rule's own reach_in: no origin");
        assert_eq!(damage(&next_far), 0.0);
    }

    /// The Shaken gate binds the CONDUIT (the rule's own "isn't Shaken"
    /// line, PR 1's read at battle_sim.gd `_cast_origins`).
    #[test]
    fn a_shaken_conduit_is_never_an_origin() {
        let (mut st, statics) = conduit_line(20.0, Some((12.0, true)), None, 7);
        st.shaken[1] = true;
        let next = run(&st, &statics, 7);
        assert_eq!(next.casts[0], 2, "a Shaken bearer is no origin");
        assert_eq!(damage(&next), 0.0);
    }
