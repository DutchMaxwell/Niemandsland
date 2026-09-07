use super::*;

    // --- Wave 4 follow-up (port-spell-accumulator, epoch 7) ---
    //
    // "Spell Accumulator": "Gets X accumulator tokens at the start of each
    // round, but can't hold more than 6 tokens at once. Casters from other
    // friendly units within 12" may spend this model's accumulator tokens as
    // if they were their own spell tokens. Friendly casters may only use
    // this rule if this unit isn't Shaken." Table: the battery pool
    // (solo_controller.gd:4520-4548, nearest-first), the Shaken gate
    // (:4556-4565, NML-936), the banking half already ported
    // (`round_start_refresh`'s accumulate branch over the loader's
    // `caster_value` fallback). Core seam: the cast sub-phase's token pool
    // (sim.rs `battery_pool` + the empty-pool fallback). The epoch literals
    // here are 7/6, never `CURRENT_RULES_EPOCH`.

    use crate::rules::{Spell, SpellModifier};

    fn spell() -> Spell {
        Spell {
            name: "bolt".into(),
            status: "modeled".into(),
            threshold: 2,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "damage".into(),
            effect_hits: 3,
            weapon_rules: vec![],
            beneficiary: String::new(),
            modifier: SpellModifier::default(),
            grants_rule: String::new(),
        }
    }

    /// Unit 0 = a Caster host with an EMPTY token pool, unit 1 = the battery
    /// 2" away holding 3 tokens (a unit of its OWN — the joined-hero chain is
    /// `caster_of`'s business, never a battery), units 2/3 = enemies at
    /// 12"/9". The spell's threshold (2) is affordable ONLY through the
    /// battery when the caster holds fewer than 2 of its own.
    fn caster_and_battery() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.casts = vec![0, 3, 0, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        // Two profile slots — the caster host (0) and the battery (1): the
        // statics vec is indexed BY PROFILE, so unit 1 must map to slot 1.
        let mut list = st.profiles.list.clone();
        let mut bat = list[0].clone();
        bat.caster_value = 2;
        list.push(bat);
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![0, 1, 0, 0],
        });
        let mut caster = UnitStatic::default();
        caster.is_caster = true;
        caster.spells = vec![spell()];
        caster.casts_per_round = 2;
        let mut battery = UnitStatic::default();
        battery.spell_accumulator = true;
        battery.casts_per_round = 2;
        (st, vec![caster, battery, UnitStatic::default(), UnitStatic::default()])
    }

    fn epoch(e: u32) -> Seams {
        Seams { rules_epoch: e, ..Seams::default() }
    }

    fn logged_events(st: &State, needle: &str) -> bool {
        st.cast_events.iter().any(|e| e["log"].as_str().map(|l| l.contains(needle)).unwrap_or(false))
    }

    /// The caster's own pool is empty, so ONLY the battery can pay: at epoch
    /// 7 the cast fires, the battery pays, and the draw names itself
    /// (rules-must-log). RED before the port: the empty pool ends the
    /// sub-phase before any battery is read.
    #[test]
    fn an_empty_caster_pool_spends_a_nearby_battery_at_epoch_7() {
        let (mut st, statics) = caster_and_battery();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(7), None);
        assert!(
            st.casts[1] < 3,
            "epoch 7: the battery pays for the cast (RED before the port): {:?}",
            st.casts
        );
        assert!(
            logged_events(&st, "Spell Accumulator"),
            "rules-must-log: the battery's draw names itself (RED before the port): {:?}",
            st.cast_events
        );
    }

    /// A caster with its OWN tokens still spends those first — the battery
    /// is only drawn on for the remainder.
    #[test]
    fn the_caster_spends_its_own_tokens_before_the_battery() {
        let (mut st, statics) = caster_and_battery();
        st.casts[0] = 1;
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(7), None);
        assert_eq!(st.casts[0], 0, "the caster's own token goes first");
        assert!(logged_events(&st, "Spell Accumulator"), "the remainder rides the battery");
    }

    /// EPOCH + GATE TESTS: below epoch 7 nothing moves (every recorded
    /// corpus replays byte-exact); a Shaken battery never lends (NML-936);
    /// a battery past 12" is out of the pool.
    #[test]
    fn the_battery_leg_is_inert_below_epoch_7_shaken_or_out_of_reach() {
        let (mut st, statics) = caster_and_battery();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(6), None);
        assert_eq!(st.casts[1], 3, "epoch 6: the pool is never read");
        assert!(!logged_events(&st, "Spell Accumulator"), "epoch 6: nothing fires, nothing logs");

        let (mut st, statics) = caster_and_battery();
        st.shaken[1] = true;
        cast_phase(&statics, &mut st, 0, &los, epoch(7), None);
        assert_eq!(st.casts[1], 3, "NML-936: a Shaken battery never lends");

        let (mut st, statics) = caster_and_battery();
        st.positions[1] = vec![[13.0 * IN2M, 0.0, 0.0]];
        cast_phase(&statics, &mut st, 0, &los, epoch(7), None);
        assert_eq!(st.casts[1], 3, "past the rule's own 12\": no lend");
    }
