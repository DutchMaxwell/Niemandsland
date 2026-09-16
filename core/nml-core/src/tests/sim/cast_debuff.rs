use super::*;

    // D-MAGIC step 2d — the DEBUFF arm of `modifier_cast_ev_of` must price a
    // penalty the way the table's step 2c (PR #1020) does, number for number.
    // On main the arm is #1012's buff fold VERBATIM
    // (`-(sh.max(ml))`, analysis/EV_DEBUFF_TABLE_2026-09-16.md): for a
    // DEBUFF's negative deltas the maxf picks the mode that LOSES LEAST, and
    // an unusable ranged mode's 0.0 masks the melee leg. Measured on main
    // (the whole-modifier fold):
    //   rifle8+CCW target @9": +1/3  (maxf picked the CCW leg that loses least)
    //   CCW-only target @1":   -0.0  (the empty ranged mode's 0.0 masked melee)
    //   CCW-only target @9":   -0.0
    //   def_mod -1 @9":        -2/3  (the malus folded onto OUR unit's defense)
    // Hand numbers (both sides Q4, defense 4, no cover, no long-range mod):
    //   rifle8 @9": baseline shoot 8 x 1/2 x 1/2 = 2.0; with -1 hit
    //   8 x 1/3 x 1/2 = 4/3 -> +2/3 (the CCW leg is NOT usable at 9" — no
    //   strike reach; an unusable mode is not a mode)
    //   CCW-only @1": melee 4 x 1/2 x 1/2 = 1.0; with -1 hit 4 x 1/3 x 1/2
    //   = 2/3 -> +1/3
    //   CCW-only @9": shooting has no profile AND melee has no strike reach —
    //   both modes unusable is legitimately 0.0: a target that cannot attack
    //   us cannot be made worse
    //   def_mod -1 @9": the malus lands on the DEFENDER of the target's
    //   attack (= our unit), so it is priced from OUR side: our rifle 8 INTO
    //   the target with the target's defense worsened (4 -> 5): baseline
    //   8 x 1/2 x 1/2 = 2.0, with the worsened defense 8 x 1/2 x (1 - 1/3)
    //   = 8/3 -> +2/3, sign = caster gain.

    use crate::rules::{Spell, SpellModifier};

    const EPS: f64 = 1e-6;

    /// Q4/D4 rifle line: an 8-attack 24" Rifle plus a 4-attack CCW — the
    /// table fixture's exact weapon set (the +1/3-on-main number needs the
    /// CCW's melee leg on the target).
    fn rifle_ccw() -> UnitStatic {
        UnitStatic {
            ctx: crate::unit::Ctx { quality: 4, defense: 4, ..Default::default() },
            shoot: vec![ShootProfile {
                name: "Rifle".into(),
                attacks: 8,
                count: 1,
                range: 24,
                ..Default::default()
            }],
            melee: vec![ShootProfile {
                name: "CCW".into(),
                attacks: 4,
                count: 1,
                range: 0,
                ..Default::default()
            }],
            ..UnitStatic::default()
        }
    }

    /// Q4/D4 CCW-only: a 4-attack melee profile, no ranged weapon at all.
    fn ccw_only() -> UnitStatic {
        UnitStatic {
            ctx: crate::unit::Ctx { quality: 4, defense: 4, ..Default::default() },
            melee: vec![ShootProfile {
                name: "CCW".into(),
                attacks: 4,
                count: 1,
                range: 0,
                ..Default::default()
            }],
            ..UnitStatic::default()
        }
    }

    fn debuff(hit: f64, dm: f64) -> Spell {
        Spell {
            name: "debuff".into(),
            status: "modeled".into(),
            threshold: 0,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "debuff".into(),
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

    /// The debuff board: the caster (unit 0) holds the spell, a filler (unit
    /// 1) keeps the caster's side occupied far out, the target (unit 2) sits
    /// at x=0 and OUR nearest unit (unit 3) at `our_x` inches from it — every
    /// unit its own profile, so the legs pair unit 2 against unit 3 cleanly
    /// and `nearest_enemy(2)` reads unit 3 at exactly `our_x`.
    fn board(target: UnitStatic, our: UnitStatic, our_x: f64) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.player = vec![0, 0, 1, 0];
        st.casts = vec![2, 0, 0, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.positions = vec![
            vec![[18.0 * crate::IN2M, 0.0, 0.0]],
            vec![[40.0 * crate::IN2M, 0.0, 0.0]],
            vec![[0.0, 0.0, 0.0]],
            vec![[our_x * crate::IN2M, 0.0, 0.0]],
        ];
        let mut list = st.profiles.list.clone();
        list.extend_from_slice(&[list[0].clone(), list[0].clone(), list[0].clone()]);
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![0, 1, 2, 3],
        });
        (st, vec![rifle_ccw(), rifle_ccw(), target, our])
    }

    /// (a) RED on main (+1/3: the maxf over the deltas picked the CCW leg
    /// that loses least): -1 hit on an 8-attack rifle target at 9" prices the
    /// SHOOT leg's full loss, +2/3.
    #[test]
    fn hit_debuff_picks_the_target_s_best_baseline_mode() {
        let (st, statics) = board(rifle_ccw(), rifle_ccw(), 9.0);
        let ev = cast_ev_of(&statics, &st, 0, &debuff(-1.0, 0.0), 2);
        assert!(
            (ev - 2.0 / 3.0).abs() < EPS,
            "rifle8 target @9\": want +2/3, got {ev}"
        );
    }

    /// (b) RED on main (-0.0: the empty ranged mode's 0.0 masked the melee
    /// leg): -1 hit on a CCW-only target IN strike reach prices +1/3.
    #[test]
    fn hit_debuff_on_a_ccw_only_target_in_reach_prices_the_melee_leg() {
        let (st, statics) = board(ccw_only(), rifle_ccw(), 1.0);
        let ev = cast_ev_of(&statics, &st, 0, &debuff(-1.0, 0.0), 2);
        assert!(
            (ev - 1.0 / 3.0).abs() < EPS,
            "CCW-only target @1\": want +1/3, got {ev}"
        );
    }

    /// (c) PIN — both sides agree: -1 hit on a CCW-only target OUT of strike
    /// reach prices 0.0. Both modes unusable is legitimately zero (a target
    /// that cannot attack us cannot be made worse) — this guards the fix
    /// against over-shooting into a negative.
    #[test]
    fn hit_debuff_on_a_ccw_only_target_out_of_reach_is_legitimately_zero() {
        let (st, statics) = board(ccw_only(), rifle_ccw(), 9.0);
        let ev = cast_ev_of(&statics, &st, 0, &debuff(-1.0, 0.0), 2);
        assert!(ev.abs() < EPS, "CCW-only target @9\": want 0.0, got {ev}");
    }

    /// (d) RED on main (-2/3: the malus folded onto OUR unit's defense and
    /// priced the cast negative): -1 def on the rifle target prices the
    /// attack-role number — OUR unit's attack INTO the target with the
    /// target's defense worsened, sign = caster gain.
    #[test]
    fn def_debuff_prices_our_attack_into_the_target() {
        let (st, statics) = board(rifle_ccw(), rifle_ccw(), 9.0);
        let ev = cast_ev_of(&statics, &st, 0, &debuff(0.0, -1.0), 2);
        assert!(ev > 0.0, "def debuff must price the attack-role number > 0, got {ev}");
    }
