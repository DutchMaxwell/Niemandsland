use super::*;
use crate::menu::{candidates_tuned, Tuning};

    // -------- Families 2-4 of the EV grant-blindness report (15.09.) --------
    //
    // EV_GRANT_BLINDNESS_2026-09-15: every planner EV arm is built on
    // `ctx_of` (static stamp + alive + in-cover), while the live grant
    // ledger `state.buffs` is consumed only by `ctx_live`. A unit granted a
    // utility-buff knob, a Furious-style combat grant, or a Shielded-family
    // defense grant is therefore priced by the menu and the threat model as
    // if the record did not exist. The port is ONE seam: the arms build
    // their root choice ctx through `ctx_live`, the fold the tray path
    // already runs. RED first — all four tests fail on the `ctx_of` arms.

    /// One live ledger record on a unit's own net: `beneficiary: ""`,
    /// scope "" (both halves), spent with the round. `rule` is the granted
    /// rule name ("" for a plain numeric modifier).
    fn rec(hit_mod: i64, rule: &str) -> crate::mods::LiveMod {
        crate::mods::LiveMod {
            hit_mod,
            casting_mod: 0,
            morale_mod: 0,
            ap_mod: 0,
            def_mod: 0,
            defense_mod: 0,
            move_mod: 0,
            grants_rule: Rc::from(rule),
            scope: Rc::from(""),
            attackers: false,
            once: true,
            name: Rc::from(rule),
        }
    }

    /// The buff line reshaped for the shoot arm: a Quality-4 shooter with a
    /// six-attack rifle at 0", and the enemy twin pair at 12" — roster-first
    /// `b` and its single-model twin `bh` one slot later. Each test overlays
    /// its own defense/artillery stamps on the twins.
    fn twin_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        // bh is a STANDALONE unit, not b's joined hero: the ledger reads walk
        // the joined chain (bearer, host, attached), so an attached twin
        // would inherit the record placed on `b` and the pair would price
        // identically whatever the fold does.
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.positions[3] = vec![[12.0 * IN2M, 0.0, 0.0]];
        st.radii[3] = vec![IN2M];
        st.wounds[3] = vec![1];
        st.alive[3] = 1;
        statics[3].model_count = 1;
        statics[3].wounds_max = vec![1];
        statics[3].ctx.quality = 4;
        statics[3].ctx.tough = 1;
        statics[0].shoot[0].attacks = 6;
        (st, statics)
    }

    /// The shoot arm's own pick out of a built menu — the HOLD candidate
    /// carrying the best-EV target, `None` when the arm priced nothing.
    fn menu_shoot_pick(menu: &[crate::menu::Candidate]) -> Option<String> {
        menu.iter().find_map(|c| c.shoot.clone())
    }

    /// The EV `best_shoot` prices for `i` onto `e`: the same
    /// profiles -> ctx -> `shoot_ev` composition the arm runs, with the root
    /// ctx built the way the swapped arm builds it (`ctx_live` over
    /// `ctx_of`, the shooting half). On the `ctx_of` arms the record never
    /// reaches this number.
    fn menu_shoot_ev(st: &State, statics: &[UnitStatic], i: usize, e: usize) -> f64 {
        let us = &statics[st.roster.profile[i]];
        let ut = &statics[st.roster.profile[e]];
        let d = crate::geom::dist_in(&st.positions[i], &st.positions[e]);
        let mut sc = Scratch::default();
        profiles_of(us, st.alive[i], d, &mut sc);
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let att = crate::sim::ctx_live(crate::sim::ctx_of(us, st, i), statics, st, i, false, epoch);
        let def = crate::sim::ctx_live(crate::sim::ctx_of(ut, st, e), statics, st, e, false, epoch);
        crate::combat::shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d)
    }

    /// Family 2, the hit_mod leg — unit A's own ledger carries a live
    /// `hit_mod: +1` utility-buff record and the menu's best-shoot EV must
    /// price it. The pair: `b` is an Artillery TARGET (the over-9" leg costs
    /// the shot -2 to hit) behind Defense 6, `bh` a plain Defense 3 twin.
    /// Unbuffed the plain twin's EV wins; with the record the hard target's
    /// composed to-hit rung climbs from 6+ to 5+ and overtakes it — both the
    /// priced EV pair and the menu's own argmax.
    #[test]
    fn live_hit_mod_record_moves_the_menus_best_shoot() {
        let (st, mut statics) = twin_line();
        statics[2].ctx.artillery = true;
        statics[2].ctx.defense = 6;
        statics[3].ctx.defense = 3;
        let mut sc = Scratch::default();
        let plain = candidates_tuned(
            &st, &crate::terrain::Terrain::default(), &statics, 0, &mut sc, Tuning::default(),
        );
        assert_eq!(
            menu_shoot_pick(&plain).as_deref(),
            Some("bh"),
            "control: the plain twin's EV wins the argmax"
        );
        let ev_plain = menu_shoot_ev(&st, &statics, 0, 2);
        let mut buffed = st.clone();
        buffed.buffs[0].push(rec(1, ""));
        let ev_live = menu_shoot_ev(&buffed, &statics, 0, 2);
        assert!(
            ev_live > ev_plain,
            "the live +1-to-hit record must raise the menu's priced EV ({ev_live} <= {ev_plain})"
        );
        let mut sc2 = Scratch::default();
        let live = candidates_tuned(
            &buffed, &crate::terrain::Terrain::default(), &statics, 0, &mut sc2, Tuning::default(),
        );
        assert_eq!(
            menu_shoot_pick(&live).as_deref(),
            Some("b"),
            "the record must flip the menu's pick onto the hard artillery target"
        );
    }

    /// Family 4, the defensive leg — a live Shielded-family grant ("+1 to
    /// Defense") on one of two otherwise-identical defenders must LOWER the
    /// EV the menu prices against its bearer. The exact twins tie unbuffed
    /// and the argmax's strict `>` keeps the roster-first `b`; the grant
    /// drops `b`'s working defense by the Shielded point, the priced EV
    /// crosses, and the pick moves to the plain twin.
    #[test]
    fn live_shielded_grant_lowers_the_ev_priced_against_the_defender() {
        let (st, mut statics) = twin_line();
        statics[3].ctx.defense = 4;
        let mut sc = Scratch::default();
        let plain = candidates_tuned(
            &st, &crate::terrain::Terrain::default(), &statics, 0, &mut sc, Tuning::default(),
        );
        assert_eq!(
            menu_shoot_pick(&plain).as_deref(),
            Some("b"),
            "control: the exact tie keeps the roster-first twin"
        );
        let mut marked = st.clone();
        marked.buffs[2].push(rec(0, "+1 to Defense"));
        let mut sc2 = Scratch::default();
        let live = candidates_tuned(
            &marked, &crate::terrain::Terrain::default(), &statics, 0, &mut sc2, Tuning::default(),
        );
        assert_eq!(
            menu_shoot_pick(&live).as_deref(),
            Some("bh"),
            "the Shielded grant must lower the EV priced against its bearer"
        );
    }

    /// Family 3, the melee leg — a live "Furious" grant must raise the melee
    /// threat the threat model prices: `melee_threat` values the pairing as
    /// a CHARGE, and the charging EV adds the unmodified-6 hit per attack
    /// when the striker's context carries Furious.
    #[test]
    fn live_furious_grant_raises_the_priced_melee_threat() {
        let (st, statics) = buff_line();
        let plain = crate::sim::melee_threat(&statics, &st, 0, 2);
        assert!(plain > 0.0, "control: the plain charge prices non-zero");
        let mut buffed = st.clone();
        buffed.buffs[0].push(rec(0, "Furious"));
        let live = crate::sim::melee_threat(&statics, &buffed, 0, 2);
        assert!(
            live > plain,
            "the live Furious grant must raise the priced melee threat ({live} <= {plain})"
        );
    }

    /// The threat model's shooting half — a live `hit_mod: +1` record on the
    /// ENEMY's own ledger must raise the incoming EV `reply_threat` prices
    /// against our side, through `volley_ev`'s ctx pair.
    #[test]
    fn live_hit_mod_record_raises_the_reply_threat_priced_against_us() {
        let (st, mut statics) = twin_line();
        statics[2].shoot = vec![gun("Rifle", 6, 24)];
        let without = crate::sim::reply_threat(&statics, &st, 0);
        let mut buffed = st.clone();
        buffed.buffs[2].push(rec(1, ""));
        let with = crate::sim::reply_threat(&statics, &buffed, 0);
        assert!(
            with.iter().sum::<f64>() > without.iter().sum::<f64>(),
            "the enemy's live +1-to-hit record must raise the priced incoming \
             ({with:?} vs {without:?})"
        );
    }
