use super::*;

    // D-MAGIC step 2 (CAST_FORK_2026-09-16.md, plan step "price the modifier
    // spells"): `cast_ev_of` must SEE a modifier spell the way the table's
    // `spell_modifier_delta` (ai_spell.gd:255-304) does. RED on main: every
    // non-damage kind prices 0.0, so a one-buff book draws boost 0.
    //
    // The pairing decision (PR body documents it in full): the table's own
    // buff pairing (`_modifier_value_on_attack(cand, effect, false)`,
    // solo_controller.gd:4530-4556) folds def_mod onto the NEAREST ENEMY's
    // defense, pricing a friendly def buff NEGATIVE — boost 0 by
    // construction. The core prices def_mod in its DEFENSE ROLE
    // (ai_spell.gd:353 "defense: the bearer defends"): the nearest opposing
    // unit's attack INTO the bearer, delta from the attacker's perspective,
    // negated for a buff. The fold arithmetic itself (clamp [2,6],
    // truncation, the EV chain, morale -> 0) is the byte-faithful port.

    use crate::acts::EPOCH_48_CASTER_BOOST;
    use crate::rules::{Spell, SpellModifier};

    /// (c) PIN — the value main prices the bolt at (1 hit, no weapon rules,
    /// unit 0 -> unit 2 at 12"): `0.5`, captured on the pre-port build.
    /// Step 2 must not move the damage path by a hair.
    const PINNED_BOLT_EV: f64 = 0.5;

    fn def4q4() -> UnitStatic {
        UnitStatic {
            ctx: crate::unit::Ctx { quality: 4, defense: 4, ..Default::default() },
            ..UnitStatic::default()
        }
    }

    /// A shooter: 8 attacks, range 24, AP 0 — the profile the hand numbers
    /// below price (8 shots, quality 4, no weapon rules).
    fn armed() -> UnitStatic {
        UnitStatic {
            ctx: crate::unit::Ctx { quality: 4, defense: 4, ..Default::default() },
            shoot: vec![ShootProfile {
                name: "Rifle".into(),
                attacks: 8,
                count: 1,
                range: 24,
                ..Default::default()
            }],
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

    fn mod_spell(kind: &str, hit: f64, dm: f64) -> Spell {
        Spell {
            name: "mod".into(),
            status: "modeled".into(),
            threshold: 0,
            range_in: 18.0,
            target_count: 1,
            effect_kind: kind.into(),
            effect_hits: 0,
            weapon_rules: vec![],
            beneficiary: String::new(),
            modifier: SpellModifier {
                present: true,
                hit_mod: hit,
                def_mod: dm,
                ..Default::default()
            },
            grants_rule: String::new(),
        }
    }

    /// The cast_ev fixture's board: four SINGLE-model units on the
    /// four_unit_line (unit 0 the caster, unit 3 its nearest enemy at 9" —
    /// inside the Rifle's 24 and NOT over the 9" long-range gate), every
    /// unit armed and stamped quality 4 / defense 4, the caster holding
    /// 2 tokens. No attachments, no joined heroes: every unit its own
    /// profile, so the legs pair unit 0 against unit 3 cleanly.
    fn board(book: Vec<Spell>) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.casts = vec![2, 0, 0, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        let mut list = st.profiles.list.clone();
        list.extend_from_slice(&[list[0].clone(), list[0].clone(), list[0].clone()]);
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![0, 1, 2, 3],
        });
        let caster = UnitStatic { is_caster: true, spells: book, ..armed() };
        (st, vec![caster, armed(), armed(), armed()])
    }

    fn epoch(e: u32) -> Seams {
        Seams { rules_epoch: e, cast_fold: true, hero_attach: true, ..Seams::default() }
    }

    /// (b) THE DELTA equals the table primitive's number. One `Rifle` (8
    /// attacks, range 24), quality 4 vs defense 4, gap 9" (shooting side;
    /// the melee side is empty and prices 0, so the max picks the shot):
    ///   base   : 8 x P(hit 4+) x (1 - block(Def 4)) = 8 x 1/2 x 1/2 = 2.0
    ///   hit +1 : 8 x P(hit 3+) x 1/2                 = 8 x 4/6 x 1/2 = 8/3
    ///   -> hit leg = 8/3 - 2 = +2/3                (ai_spell.gd:269-270 fold)
    ///   def +1 : 8 x 1/2 x (1 - block(Def 3))      = 8 x 1/2 x 2/6 = 4/3
    ///   -> attacker-side delta -2/3, bearer's value +2/3
    ///                                             (ai_spell.gd:272-275 fold)
    #[test]
    fn modifier_delta_matches_the_table_primitive() {
        let (st, statics) = board(vec![]);
        let eps = 1e-6;
        let hit = cast_ev_of(&statics, &st, 0, &mod_spell("buff", 1.0, 0.0), 0);
        assert!(
            (hit - 2.0 / 3.0).abs() < eps,
            "hit_mod +1 leg: want 2/3, got {hit}"
        );
        let def = cast_ev_of(&statics, &st, 0, &mod_spell("buff", 0.0, 1.0), 0);
        assert!(
            (def - 2.0 / 3.0).abs() < eps,
            "def_mod +1 leg (defense role): want 2/3, got {def}"
        );
    }

    /// (a) A caster whose book holds ONE +1 def buff spell prices the cast
    /// non-zero AND plans a non-zero boost. On main both are 0 -> RED.
    #[test]
    fn a_def_buff_book_prices_nonzero_and_boosts() {
        let (st, statics) = board(vec![mod_spell("buff", 0.0, 1.0)]);
        let ev = cast_ev_of(&statics, &st, 0, &statics[0].spells[0], 0);
        assert!(ev > 0.0, "def buff priced {ev}");
        let (boost, _, _) = plan_caster_boost(&statics, &st, 0, &statics[0].spells[0], 0, 2, &[]);
        assert!(boost > 0, "def buff boost {boost}");
    }

    /// (c) PIN — a damage spell's cast_ev_of is UNCHANGED by step 2: the
    /// damage path (bolt, 1 hit, no weapon rules, unit 0 -> unit 2 at 12")
    /// priced this exact value before the port and must keep pricing it.
    #[test]
    fn damage_ev_is_unchanged() {
        let (st, statics) = board(vec![bolt()]);
        let ev = cast_ev_of(&statics, &st, 0, &statics[0].spells[0], 2);
        assert!((ev - PINNED_BOLT_EV).abs() < 1e-9, "bolt ev {ev}");
    }

    /// The cast sub-phase's boost leg stays on the priced value too: a
    /// one-buff caster SPENDS both its leftover tokens on the attempt
    /// (the full walk, epoch 48: threshold 0, boost 2) — casts[0] 2 -> 0.
    /// On main the unpriced buff draws boost 0 and casts[0] stays 2 -> RED.
    #[test]
    fn a_def_buff_book_spends_tokens_in_the_cast_walk() {
        let (mut st, statics) = board(vec![mod_spell("buff", 0.0, 1.0)]);
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, epoch(EPOCH_48_CASTER_BOOST), None);
        assert_eq!(st.casts[0], 0, "the boost leg spent the leftover tokens");
    }
