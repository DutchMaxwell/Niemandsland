use super::*;

    // D-MAGIC step 4 (BRIEF_castmove.md) — `cast_ev_of` must price the
    // MOVEMENT modifier fields (`SpellModifier.rush_in` / `.advance_in` /
    // `.range_in`, rules.rs:328-336) the way the table's movement bands use
    // them (movement_range_controller.gd:86-191): a spell rush folds into
    // the charge reach, a spell advance is a separate band the planner
    // spends before a shot, a spell range bonus widens every shooting
    // reach (solo_controller.gd:5625 `shooting_range_bonus`). The table's
    // spell menu prices these fields 0 (ai_spell.gd:250-252) — the core
    // prices them from its own charge/shoot EV. RED on main: every
    // movement-only modifier hits the `hit == 0 && dm == 0` bail in
    // `modifier_cast_ev_of` and prices 0.0.
    //
    // Pricing model (PR body in full): the ABSOLUTE USAGE VALUE of the
    // actor's movement with and without the modifier —
    //   movement_value = max(charge_usage, shoot_usage, 0)
    //   charge_usage   = the melee EV of the best charge the LIVE band
    //                    (band + rush_in) can reach (shroud-folded, aircraft
    //                    victims refused, the futile bar at 0.2), else 0
    //   shoot_usage    = the shoot EV at (distance − advance band), the
    //                    advance-then-shoot pattern, every shooting reach
    //                    widened by range_in
    // so a buff gains and a debuff loses exactly the usage it removes —
    // the maxf sign trap (max(−ev, 0) = 0 would zero every movement
    // debuff) never fires.

    use crate::rules::{Spell, SpellModifier};

    /// A melee-only unit: 8 claw attacks, quality 4 vs defense 4 — the
    /// hand number the charge leg prices (8 x 1/2 x 1/2 = 2.0 charging,
    /// Impact and Ravage pools empty).
    fn bruiser() -> UnitStatic {
        UnitStatic {
            ctx: crate::unit::Ctx { quality: 4, defense: 4, ..Default::default() },
            melee: vec![ShootProfile {
                name: "Claws".into(),
                attacks: 8,
                count: 1,
                range: 0,
                ..Default::default()
            }],
            ..UnitStatic::default()
        }
    }

    /// A shooter: 8 attacks, range 24, AP 0 (the `cast_ev` fixture's
    /// `armed()`, local so the two modules stay independent).
    fn rifle() -> UnitStatic {
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

    fn move_spell(kind: &str, advance_in: f64, rush_in: f64, range_field: f64) -> Spell {
        Spell {
            name: "move_mod".into(),
            status: "modeled".into(),
            threshold: 0,
            range_in: 36.0,
            target_count: 1,
            effect_kind: kind.into(),
            effect_hits: 0,
            weapon_rules: vec![],
            beneficiary: String::new(),
            modifier: SpellModifier {
                present: true,
                advance_in,
                rush_in,
                range_in: range_field,
                ..Default::default()
            },
            grants_rule: String::new(),
        }
    }

    /// The cast_ev board shape with OUR positions: four single-model units
    /// on one line (unit 0 the caster, its nearest enemy placed by `xs`),
    /// every unit stamped quality 4 / defense 4, the caster holding 2
    /// tokens, no attachments. `advance0` pins the caster's advance band
    /// to 0 (the immobile-gun detail of test (c): with the default 6 the
    /// advance-then-shoot shot already exists and the leg prices 0).
    fn board(
        unit: fn() -> UnitStatic,
        xs: [f64; 4],
        advance0: bool,
    ) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.casts = vec![2, 0, 0, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.positions = xs.iter().map(|x| vec![[x * IN2M, 0.0, 0.0]]).collect();
        if advance0 {
            let mut b = st.bands[0];
            b.advance = 0.0;
            st.bands[0] = b;
        }
        let mut list = st.profiles.list.clone();
        list.extend_from_slice(&[list[0].clone(), list[0].clone(), list[0].clone()]);
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![0, 1, 2, 3],
        });
        let caster = UnitStatic { is_caster: true, spells: vec![], ..unit() };
        (st, vec![caster, unit(), unit(), unit()])
    }

    /// (a) THE CHARGE REACH: a melee-only bearer whose nearest enemy sits
    /// at base-edge gap 13" — outside the default rush band 12, inside
    /// rush 12 + 3. The buff's rush_in +3 turns the charge from
    /// unreachable (usage 0) into an 8-attack charging swing (2.0 EV: 8 x
    /// P(hit 4+) x (1 - block(Def 4)); Impact and Ravage pools empty, the
    /// 2.0 clears the futile bar 0.2) — so the cast prices 2.0 and the
    /// boost walk spends tokens to LAND it. RED on main: 0.0 and boost 0.
    #[test]
    fn rush_buff_prices_the_charge_it_unlocks() {
        let (st, statics) = board(
            bruiser,
            [0.0, -3.0, 15.0, 20.0],
            false,
        );
        let eps = 1e-6;
        let ev = cast_ev_of(&statics, &st, 0, &move_spell("buff", 0.0, 3.0, 0.0), 0);
        assert!(
            (ev - 2.0).abs() < eps,
            "the rush buff must price the charge it unlocks, got {ev}"
        );
        let (boost, _, _) =
            plan_caster_boost(&statics, &st, 0, &move_spell("buff", 0.0, 3.0, 0.0), 0, 2, &[]);
        assert!(boost > 0, "a priced cast must draw boost tokens, got {boost}");
    }

    /// (b) THE ADVANCE DEBUFF, DOCUMENTED DEVIATION: the brief's
    /// "charge-reach edge" contradicts the table's own band math — a spell
    /// advance NEVER touches the charge reach
    /// (movement_range_controller.gd:182-191: only the spell RUSH folds
    /// into `charge = rush + charge_extra`), so the debuff must price the
    /// SHOT it pushes out of reach. An enemy rifle-24 shooter with its
    /// nearest enemy at 29": with the default advance band 6 the
    /// advance-then-shoot leg reaches 29 - 6 = 23 <= 24 (2.0 EV); with
    /// advance_in -3 the band is 3 and the shot is priced at 26 > 24 —
    /// usage gone. The debuff is worth +2.0 to the caster. RED on main: 0.0.
    #[test]
    fn advance_debuff_prices_the_shot_it_pushes_out() {
        let (st, statics) = board(
            rifle,
            [0.0, -5.0, 29.0, 60.0],
            false,
        );
        let eps = 1e-6;
        let ev =
            cast_ev_of(&statics, &st, 0, &move_spell("debuff", -3.0, 0.0, 0.0), 2);
        assert!(
            (ev - 2.0).abs() < eps,
            "the advance debuff must price the shot it removes, got {ev}"
        );
    }

    /// (c) THE SHOOTING RANGE: a range_in +6 buff on an immobile gun
    /// (advance band pinned 0 — the fixture detail: with the default 6 the
    /// advance-then-shoot shot at 20" already exists and the leg prices
    /// 0). Nearest enemy at 26": the bare rifle-24 cannot reach, the
    /// widened 30" reach fires at 26" (2.0 EV, no long-range term —
    /// `profile_ev` gates hit/target only on weapon rules here). The buff
    /// prices exactly 2.0. RED on main: 0.0.
    #[test]
    fn range_buff_prices_the_shot_it_widens() {
        let (st, statics) = board(
            rifle,
            [0.0, -3.0, 26.0, 50.0],
            true,
        );
        let eps = 1e-6;
        let ev = cast_ev_of(&statics, &st, 0, &move_spell("buff", 0.0, 0.0, 6.0), 0);
        assert!(
            (ev - 2.0).abs() < eps,
            "the range buff must price the shot it widens, got {ev}"
        );
    }
