use super::*;

    // --- Wave 6 (port-caster-interference, analysis/CASTER_SEAM_2026-09-14.md row 2) ---
    //
    // "Caster" v3.5.1: enemy models with spell tokens within 18" in line of
    // sight of the caster's unit may spend them for -1 per token on the
    // cast (registry `Caster | aura_in=18`, ai_spell.gd:105-107). Table:
    // auto-planned in both-AI (solo_controller.gd:4379-4386) with
    // `plan_interference`'s deterministic mirrored marginal calculus
    // (ai_spell.gd:518-527), paid before the roll alongside the boost
    // (:4387-4395); in human-vs-AI main.gd:3474-3478 prompts instead. The
    // core had no reader anywhere. The epoch pins here are the frozen constants 51/50,
    // never `CURRENT_RULES_EPOCH`.

    use crate::acts::{EPOCH_50_SURGE_LOW, EPOCH_51_CASTER_INTERFERENCE};
use crate::rules::{Spell, SpellModifier};

    /// A Defense-4 static for the spell's EV (the target's save rung).
    fn def4() -> UnitStatic {
        UnitStatic {
            ctx: crate::unit::Ctx { defense: 4, ..Default::default() },
            ..UnitStatic::default()
        }
    }

    /// The spell's threshold EQUALS the caster's purse: every own token
    /// pays for the attempt, nothing is left to boost with — so the ONLY
    /// thing that can move the roll is the enemy's interference.
    fn spell() -> Spell {
        Spell {
            name: "bolt".into(),
            status: "modeled".into(),
            threshold: 2,
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

    /// Unit 0 = a lone Caster holding exactly the threshold (own_left 0, no
    /// boost on either leg); unit 3 = an enemy CASTER 9" away (the spell's
    /// pick, inside the 18" aura) holding 2 interference tokens. One hit
    /// into Defense 4 prices EV 1/2, and `plan_interference`'s mirrored
    /// calculus buys BOTH enemy tokens: the roll drops 4+ -> 6+.
    fn caster_and_foe() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.casts = vec![2, 0, 0, 2];
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
        // interference calculus then buys one token, not two.
        let mut list = st.profiles.list.clone();
        list.extend_from_slice(&[list[0].clone(), list[0].clone(), list[0].clone()]);
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![0, 1, 2, 3],
        });
        let caster = UnitStatic {
            name: "caster".into(),
            is_caster: true,
            spells: vec![spell()],
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        let foe = UnitStatic {
            name: "foe".into(),
            is_caster: true,
            casts_per_round: 2,
            // the interferer is also the pick's nearest DEFENSE-4 target (the
            // lone-caster board's own shape): a default ctx (defense 0) would
            // flip the EV walk onto the 12" unit and scramble the arithmetic.
            ctx: crate::unit::Ctx { defense: 4, ..Default::default() },
            ..UnitStatic::default()
        };
        (st, vec![caster, UnitStatic::default(), def4(), foe])
    }

    fn epoch(e: u32) -> Seams {
        // The fold gate is `caster_of`'s own — the interference leg rides
        // the same chain resolution the cast sub-phase already needs.
        Seams { rules_epoch: e, cast_fold: true, hero_attach: true, ..Seams::default() }
    }

    fn logged(st: &State, needle: &str) -> bool {
        st.cast_events
            .iter()
            .any(|e| e["log"].as_str().map(|l| l.contains(needle)).unwrap_or(false))
    }

    /// THE BOTH-LEGS TEST. NEW leg — epoch 51: the enemy caster's 2 tokens
    /// within 18" LoS are spent against the announced cast, the roll drops
    /// 4+ -> 6+ (p 1/2 -> 1/6), the enemy purse 2 -> 0. OLD leg — epoch 50
    /// (the epoch immediately below this bump at rebase time, #966's boost
    /// leg): the interference pool is never read, the enemy purse is
    /// untouched, the roll stays the flat 4+.
    /// RED before the port: the 49 leg still rolls the flat 4+ and the foe
    /// keeps every token.
    #[test]
    fn two_enemy_tokens_cast_at_6plus_at_epoch_49_and_flat_at_epoch_48() {
        // epoch 51.
        let (mut st, statics) = caster_and_foe();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_51_CASTER_INTERFERENCE), None);
        assert_eq!(
            st.casts[3], 0,
            "epoch 51: the foe's tokens pay for the interference (RED before the port): {:?}",
            st.casts
        );
        assert_eq!(
            st.casts[0], 0,
            "epoch 51: the caster's own purse still pays the threshold: {:?}",
            st.casts
        );
        // three 1/3-weight faces at 1/6 on a 1/2-EV spell: 1/12 (the walk's
        // frac arithmetic, the boost test's own shape at p 1/6).
        assert!(
            (st.wound_frac[3] - 1.0 / 12.0).abs() < 1e-9,
            "epoch 51: the cast resolves at 6+ (RED before the port): {}",
            st.wound_frac[3]
        );

        // epoch 50 — the OLD leg, the epoch immediately below this bump at
        // rebase time (a #966-caster-boost-stamped record replays byte-exact).
        let (mut st, statics) = caster_and_foe();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_50_SURGE_LOW), None);
        assert_eq!(st.casts[3], 2, "epoch 50 (old leg): the enemy purse is untouched");
        assert_eq!(st.casts[0], 0, "epoch 50 (old leg): only the threshold is spent");
        assert!(
            (st.wound_frac[3] - 0.25).abs() < 1e-9,
            "epoch 50 (old leg): the flat 4+ cast, p 1/2: {}",
            st.wound_frac[3]
        );
    }

    /// Rules-must-log (the brief's own line shape): the interfered cast
    /// names the counter-spend and the target's drop; nothing interfered,
    /// nothing logged.
    #[test]
    fn an_interfered_cast_logs_one_line_and_a_clear_cast_logs_none() {
        let (mut st, statics) = caster_and_foe();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_51_CASTER_INTERFERENCE), None);
        assert!(
            logged(&st, "Caster: interference 2 tokens from foe, target 4+ -> 6+"),
            "the interference line names the foe and the target: {:?}",
            st.cast_events
        );

        let (mut st, statics) = caster_and_foe();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_50_SURGE_LOW), None);
        assert!(
            !logged(&st, "interference"),
            "epoch 50 (old leg): no interference, no line: {:?}",
            st.cast_events
        );
    }

    /// The pool walk: "within 18" in line of sight of the caster's unit"
    /// (:4606) — a foe past the aura, or one without line of sight, never
    /// spends a token, however fat its purse.
    #[test]
    fn a_foe_out_of_the_aura_or_without_line_of_sight_never_spends() {
        // 20" out: the spell still legally picks the 12" enemy — the POOL
        // is what refuses the far caster.
        let (mut st, statics) = caster_and_foe();
        st.positions[3] = vec![[20.0 * IN2M, 0.0, 0.0]];
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_51_CASTER_INTERFERENCE), None);
        assert_eq!(st.casts[3], 2, "a foe past the aura keeps every token");
        assert!(
            (st.wound_frac[2] - 0.25).abs() < 1e-9,
            "the cast still lands on the 12\" enemy at the flat 4+: {}",
            st.wound_frac[2]
        );

        // the same board with the foe INSIDE the aura but without line of
        // sight from the caster's unit (:4606).
        let (mut st, statics) = caster_and_foe();
        let los = vec![true, true, true, false];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_51_CASTER_INTERFERENCE), None);
        assert_eq!(st.casts[3], 2, "no LoS, no counter-spend");
    }

    /// The counter plans AGAINST the committed boost: a caster with two
    /// leftovers boosts to 2+ (the boost line names it), the foe's two
    /// tokens pull the roll right back to 4+ — both purses drain, both
    /// lines log (solo_controller.gd:4379-4397).
    #[test]
    fn the_counter_plans_against_the_committed_boost() {
        let (mut st, statics) = caster_and_foe();
        st.casts[0] = 4;
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_51_CASTER_INTERFERENCE), None);
        assert_eq!(st.casts[0], 0, "threshold 2 + boost 2");
        assert_eq!(st.casts[3], 0, "the foe's two tokens are spent");
        assert!(
            logged(&st, "Caster: 2 tokens spent (own 2, helpers 0), target 4+ -> 2+"),
            "the boost line names its own leg: {:?}",
            st.cast_events
        );
        assert!(
            logged(&st, "Caster: interference 2 tokens from foe, target 2+ -> 4+"),
            "the counter line rides against the boost: {:?}",
            st.cast_events
        );
    }

    /// The pure arithmetic (spell.rs): +1 per enemy token onto the target,
    /// the [2,6] clamp at both ends, and the mirrored marginal calculus
    /// priced at the RAW EV — an unpriced cast draws no counter, and a fat
    /// pool stops at the 6+ clamp.
    #[test]
    fn plan_interference_ports_the_tables_mirrored_calculus() {
        use crate::combat::success_chance;
        assert_eq!(crate::spell::cast_success_chance_vs(0, 2, 0), success_chance(2));
        assert_eq!(crate::spell::cast_success_chance_vs(0, 2, 2), success_chance(4));
        assert_eq!(
            crate::spell::cast_success_chance_vs(0, 0, 10),
            success_chance(6),
            "clamped at 6+, never above"
        );
        assert_eq!(crate::spell::plan_interference(0.5, 2, 0), 2, "EV 1/2: both tokens beat the floor");
        assert_eq!(crate::spell::plan_interference(0.5, 10, 2), 4, "the counter stops at the 6+ clamp");
        assert_eq!(crate::spell::plan_interference(0.0, 6, 0), 0, "an unpriced cast draws no counter");
    }
