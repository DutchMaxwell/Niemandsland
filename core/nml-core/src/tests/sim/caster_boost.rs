use super::*;

    // --- Wave 6 (port-caster-boost, analysis/CASTER_SEAM_2026-09-14.md row 1) ---
    //
    // "Caster" v3.5.1: "may spend any number of spell tokens to give the
    // caster +1 to the roll per token" (registry `Caster | aura_in=18,
    // boost_per_token=1, cast_target=4`). Table: the caster's OWN leftover
    // tokens are the FIRST boost source (solo_controller.gd:4336-4342), then
    // friendly casters and Spell Accumulator batteries within 18" in LoS —
    // batteries on their own 12" reach, a Shaken battery refused
    // (:4565-4625); +1 per token, clamped [2,6] (ai_spell.gd:105-107); paid
    // BEFORE the roll, one try per spell (:4387-4395). The core's cast
    // sub-phase read a flat 4+ and never spent a token on the boost. The
    // epoch literals here are 48/47/43, never `CURRENT_RULES_EPOCH`.

    use crate::rules::{Spell, SpellModifier};

    /// A Defense-4 static for the spell's EV (the target's save rung).
    fn def4() -> UnitStatic {
        UnitStatic {
            ctx: crate::unit::Ctx { defense: 4, ..Default::default() },
            ..UnitStatic::default()
        }
    }

    fn spell() -> Spell {
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

    /// Unit 0 = a lone Caster holding 2 tokens (threshold 0, so both are
    /// leftover); units 1-3 lend nothing (unit 1 is the joined hero and out
    /// of tokens anyway), so the boost pool is the caster's own leftover
    /// alone. Enemies sit at Defense 4 (unit 3 nearest at 9", the spell's
    /// pick), so one hit prices EV 1/2 unsaved and the table's boost
    /// calculus buys BOTH tokens: the roll lifts 4+ -> 2+.
    fn lone_caster() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.casts = vec![2, 0, 0, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        // fat enemy wound pools: the expectation must never KILL the pick
        // mid-walk (a dead nearest enemy would flip the later faces onto
        // the next unit and scramble the wound arithmetic).
        st.wounds = vec![vec![1], vec![1], vec![9], vec![9]];
        // The per-unit statics are read THROUGH the roster profile (the
        // core's own lookup, `statics[roster.profile[u]]`): every unit must
        // point at its own slot, or the Defense-4 enemies read the caster's
        // default ctx (defense 0) and the spell's EV halves to 1/6 — the
        // boost's marginal calculus then buys one token, not two.
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
            spells: vec![spell()],
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        (st, vec![caster, UnitStatic::default(), def4(), def4()])
    }

    /// The lone-caster board with a token BATTERY joined as unit 1 (profile
    /// slot 1, 2" from the caster, holding 2 tokens): the helper half of the
    /// pool. The caster holds 1 token (threshold 0), so a full boost draws
    /// own-first and the battery covers the rest.
    fn caster_and_battery() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.casts = vec![1, 2, 0, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.wounds = vec![vec![1], vec![1], vec![9], vec![9]];
        let mut list = st.profiles.list.clone();
        // Four profile slots for the four units (see `lone_caster`): the
        // enemies' Defense-4 ctx only reaches the EV walk through the
        // roster profile.
        list.extend_from_slice(&[list[0].clone(), list[0].clone(), list[0].clone()]);
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![0, 1, 2, 3],
        });
        let caster = UnitStatic {
            is_caster: true,
            spells: vec![spell()],
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        let battery = UnitStatic {
            spell_accumulator: true,
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        (st, vec![caster, battery, def4(), def4()])
    }

    fn epoch(e: u32) -> Seams {
        // The fold gate is `caster_of`'s own — the boost leg rides the same
        // chain resolution the cast sub-phase already needs.
        Seams { rules_epoch: e, cast_fold: true, hero_attach: true, ..Seams::default() }
    }

    fn logged(st: &State, needle: &str) -> bool {
        st.cast_events
            .iter()
            .any(|e| e["log"].as_str().map(|l| l.contains(needle)).unwrap_or(false))
    }

    /// THE BOTH-LEGS TEST. NEW leg — epoch 48: both leftovers go to the
    /// boost (own first, no helpers in reach), the roll lifts 4+ -> 2+
    /// (p 1/2 -> 5/6), the purse 2 -> 0. OLD leg — epoch 47 (the epoch
    /// immediately below this bump at rebase time): the pool is never
    /// read, the purse is untouched, the roll stays the flat 4+.
    /// RED before the port: the 48 leg still rolls the flat 4+ and keeps
    /// every token.
    #[test]
    fn two_leftover_tokens_cast_at_2plus_at_epoch_48_and_flat_at_epoch_47() {
        // epoch 48.
        let (mut st, statics) = lone_caster();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert_eq!(
            st.casts[0], 0,
            "epoch 48: the leftovers pay for the boost (RED before the port): {:?}",
            st.casts
        );
        // three 1/3-weight faces at 5/6 on a 1/2-EV spell: 5/12 expected
        // (the walk's first whole wound eats the 1.0 frac base, the rest is
        // the walk's own remainder).
        assert!(
            (st.wound_frac[3] - 5.0 / 12.0).abs() < 1e-9,
            "epoch 48: the cast resolves at 2+ (RED before the port): {}",
            st.wound_frac[3]
        );

        // epoch 47 — the OLD leg, the epoch immediately below this bump at
        // rebase time (a #968-rending-aura-stamped record replays byte-exact).
        let (mut st, statics) = lone_caster();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(47), None);
        assert_eq!(st.casts[0], 2, "epoch 47: the purse is untouched");
        assert!(
            (st.wound_frac[3] - 0.25).abs() < 1e-9,
            "epoch 47: the flat 4+ cast, p 1/2: {}",
            st.wound_frac[3]
        );

        // epoch 43 — the same old reading one epoch lower still.
        let (mut st, statics) = lone_caster();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(43), None);
        assert_eq!(st.casts[0], 2, "epoch 43: the purse is untouched");
        assert!(
            (st.wound_frac[3] - 0.25).abs() < 1e-9,
            "epoch 43: the flat 4+ cast, p 1/2: {}",
            st.wound_frac[3]
        );
    }

    /// Rules-must-log: the cast that spent tokens names the split and the
    /// lifted target (the brief's own line shape); nothing spent, nothing
    /// logged.
    #[test]
    fn the_boost_cast_logs_its_token_split_and_target() {
        let (mut st, statics) = lone_caster();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert!(
            logged(&st, "Caster: 2 tokens spent (own 2, helpers 0), target 4+ -> 2+"),
            "the boost line names the split and the target: {:?}",
            st.cast_events
        );

        let (mut st, statics) = lone_caster();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(43), None);
        assert!(!logged(&st, "Caster:"), "nothing spent, nothing logged: {:?}", st.cast_events);
    }

    /// The helper half: the caster's own leftover pays FIRST, the battery
    /// covers the rest — the table's draw order (:4340-4342, :4654+).
    #[test]
    fn the_boost_draws_the_own_leftover_before_the_battery() {
        let (mut st, statics) = caster_and_battery();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert_eq!(st.casts[0], 0, "the caster's own leftover goes first");
        assert_eq!(st.casts[1], 1, "the battery covers the remainder: {:?}", st.casts);
        assert!(
            logged(&st, "Caster: 2 tokens spent (own 1, helpers 1), target 4+ -> 2+"),
            "the split names both halves: {:?}",
            st.cast_events
        );
    }

    /// NML-936 for the boost pool: a Shaken BATTERY is refused (:4596-4601),
    /// so the boost falls back to the caster's own leftover alone.
    #[test]
    fn a_shaken_battery_never_joins_the_boost_pool() {
        let (mut st, statics) = caster_and_battery();
        st.shaken[1] = true;
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert_eq!(st.casts[0], 0, "the own leftover still boosts");
        assert_eq!(st.casts[1], 2, "the Shaken battery keeps every token");
        assert!(
            logged(&st, "Caster: 1 tokens spent (own 1, helpers 0), target 4+ -> 3+"),
            "the line names the reduced spend: {:?}",
            st.cast_events
        );
    }

    /// The reach split: a battery answers to its OWN 12" (:4565, :4604)
    /// while a real caster helper answers to the 18" aura (:4568) — the
    /// same board, the two readings.
    #[test]
    fn the_battery_lends_on_its_own_twelve_and_a_caster_helper_on_the_aura() {
        // battery at 15": outside its own 12", inside the aura -> refused.
        let (mut st, statics) = caster_and_battery();
        st.positions[1] = vec![[15.0 * IN2M, 0.0, 0.0]];
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert_eq!(st.casts[1], 2, "a battery past its own 12\" never lends boost");
        assert_eq!(st.casts[0], 0, "the caster still boosts from its own leftover");

        // the same board with the helper a REAL CASTER: the 18" aura reaches.
        let (mut st, statics) = caster_and_battery();
        st.positions[1] = vec![[15.0 * IN2M, 0.0, 0.0]];
        let mut statics = statics;
        statics[1] = UnitStatic {
            is_caster: true,
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert_eq!(st.casts[1], 1, "a caster helper inside the aura joins the pool");
    }

    /// "in line of sight of the caster's unit" (:4606): a helper without LoS
    /// is out of the pool even at 2".
    #[test]
    fn a_helper_without_line_of_sight_is_out_of_the_boost_pool() {
        let (mut st, statics) = caster_and_battery();
        let los = vec![true, false, true, true];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert_eq!(st.casts[1], 2, "no LoS, no lend");
        assert_eq!(st.casts[0], 0, "the own leftover still boosts");
    }

    /// The [2,6] clamp ends the spend: a fat purse lifts the roll to 2+ and
    /// stops there — the rest of the purse stays held (ai_spell.gd:105-107).
    #[test]
    fn the_boost_stops_at_the_clamp_even_with_a_fat_purse() {
        let (mut st, statics) = lone_caster();
        st.casts[0] = 10;
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(48), None);
        assert_eq!(st.casts[0], 8, "two tokens lift 4+ -> 2+, the clamp ends the spend");
    }
