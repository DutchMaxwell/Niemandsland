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
    // sub-phase reads a flat 4+ and never spends a token on the boost. The
    // epoch literals here are 44/43/40, never `CURRENT_RULES_EPOCH`.

    use crate::rules::{Spell, SpellModifier};

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
    /// pick) on fat wound pools, so the expectation never kills the pick
    /// mid-walk, one hit prices EV 1/2 unsaved and the table's boost
    /// calculus buys BOTH tokens: the roll lifts 4+ -> 2+.
    fn lone_caster() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.casts = vec![2, 0, 0, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.wounds = vec![vec![1], vec![1], vec![9], vec![9]];
        let def4 = UnitStatic {
            ctx: crate::unit::Ctx { defense: 4, ..Default::default() },
            ..UnitStatic::default()
        };
        let caster = UnitStatic {
            is_caster: true,
            spells: vec![spell()],
            casts_per_round: 2,
            ..UnitStatic::default()
        };
        (st, vec![caster, UnitStatic::default(), def4, def4])
    }

    fn epoch(e: u32) -> Seams {
        // The fold gate is `caster_of`'s own — the boost leg rides the same
        // chain resolution the cast sub-phase already needs.
        Seams { rules_epoch: e, cast_fold: true, hero_attach: true, ..Seams::default() }
    }

    /// THE BOTH-LEGS TEST. NEW leg — epoch 44: both leftovers go to the
    /// boost (own first, no helpers in reach), the roll lifts 4+ -> 2+
    /// (p 1/2 -> 5/6), the purse 2 -> 0. OLD leg — epoch 43: the pool is
    /// never read, the purse is untouched, the roll stays the flat 4+.
    /// RED before the port: the 44 leg still rolls the flat 4+ and keeps
    /// every token.
    #[test]
    fn two_leftover_tokens_cast_at_2plus_at_epoch_44_and_flat_at_epoch_43() {
        // epoch 44.
        let (mut st, statics) = lone_caster();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(44), None);
        assert_eq!(
            st.casts[0], 0,
            "epoch 44: the leftovers pay for the boost (RED before the port): {:?}",
            st.casts
        );
        // three 1/3-weight faces at 5/6 on a 1/2-EV spell: 5/12 expected on
        // top of the 1.0 frac base.
        assert!(
            (st.wound_frac[3] - (1.0 + 5.0 / 12.0)).abs() < 1e-9,
            "epoch 44: the cast resolves at 2+ (RED before the port): {}",
            st.wound_frac[3]
        );

        // epoch 43.
        let (mut st, statics) = lone_caster();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(43), None);
        assert_eq!(st.casts[0], 2, "epoch 43: the purse is untouched");
        assert!(
            (st.wound_frac[3] - 1.25).abs() < 1e-9,
            "epoch 43: the flat 4+ cast, p 1/2: {}",
            st.wound_frac[3]
        );

        // epoch 40 — the same old reading one epoch lower: a record stamped
        // at the pre-boost live epoch replays byte-exact too.
        let (mut st, statics) = lone_caster();
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(40), None);
        assert_eq!(st.casts[0], 2, "epoch 40: the purse is untouched");
        assert!(
            (st.wound_frac[3] - 1.25).abs() < 1e-9,
            "epoch 40: the flat 4+ cast, p 1/2: {}",
            st.wound_frac[3]
        );
    }
