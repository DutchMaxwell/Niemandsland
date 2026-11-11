use super::*;
use crate::sim::{reply_threat_core_with, ReplyOpts};

    // ---- the per-call reply ctx cache is invisible: `reply_threat_core` with the cache ON equals the same call with
    // the cache OFF (every ctx rebuilt at each use, the original behaviour), bit for bit. ----

    const FIXTURES: [&str; 5] = [
        "acts_wide_25.jsonl",
        "acts_25.jsonl",
        "acts_arb.jsonl",
        "acts_hero_dead.jsonl",
        "acts_charge_ev_vintage.jsonl",
    ];

    fn opts_set() -> Vec<ReplyOpts> {
        let d = ReplyOpts::default();
        vec![
            d,
            ReplyOpts { v2: true, ..d },
            ReplyOpts { v2: true, range_edge: true, reach_only: true, ..d },
            ReplyOpts { v2: true, by_speed: true, skip_activated: true, hold_gate: true, ..d },
        ]
    }

    fn rec(hit_mod: i64, ap_mod: i64, def_mod: i64, rule: &str) -> crate::mods::LiveMod {
        crate::mods::LiveMod {
            hit_mod,
            casting_mod: 0,
            morale_mod: 0,
            ap_mod,
            def_mod,
            defense_mod: 0,
            move_mod: 0,
            grants_rule: Rc::from(rule),
            scope: Rc::from(""),
            attackers: false,
            once: false,
            name: Rc::from(rule),
        }
    }

    /// Different ledger rows on different units, so a cache keyed on the wrong unit returns another unit's ctx.
    fn with_records(st: &State, salt: usize) -> State {
        const RULES: [&str; 5] = ["Furious", "Rending", "Unstoppable", "Enhanced Guardian", ""];
        let mut b = st.clone();
        for i in 0..b.units() {
            if (i + salt) % 3 == 2 {
                continue; // leave some chains record-free: both paths of the grants shortcut run
            }
            let k = (i + salt) as i64;
            b.buffs[i].push(rec(k % 3 - 1, k % 2, (k % 3) - 1, RULES[(i + salt) % RULES.len()]));
        }
        b
    }

    /// (states compared, pairs of calls, calls with a non-zero incoming, states carrying grant records)
    fn sweep() -> (usize, usize, usize, usize) {
        let repo = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
        let (mut states, mut calls, mut nonzero, mut granted) = (0, 0, 0, 0);
        for f in FIXTURES {
            let path = format!("{}/tests/fixtures/{f}", env!("CARGO_MANIFEST_DIR"));
            let Ok(c) = crate::load_acts(&path) else { continue };
            let per_act = crate::act_statics(&c, repo);
            for (ai, a) in c.acts.iter().enumerate() {
                let statics = &per_act[ai];
                let epoch = c.knobs.rules_epoch;
                let natural = a.state.clone();
                let injected = with_records(&a.state, ai);
                granted += usize::from(injected.buffs.iter().any(|b| !b.is_empty()));
                for st in [&natural, &injected] {
                    states += 1;
                    for player in [0i64, 1] {
                        for o in opts_set() {
                            let on = reply_threat_core_with(statics, st, player, epoch, o, true);
                            let off = reply_threat_core_with(statics, st, player, epoch, o, false);
                            let bits = |v: &[f64]| v.iter().map(|x| x.to_bits()).collect::<Vec<_>>();
                            assert_eq!(bits(&on), bits(&off), "{f} act {ai} player {player} opts {o:?}");
                            calls += 1;
                            nonzero += usize::from(on.iter().any(|&x| x > 0.0));
                        }
                    }
                }
            }
        }
        (states, calls, nonzero, granted)
    }

    #[test]
    fn the_cached_reply_equals_the_uncached_reply_on_recorded_states_with_and_without_grant_records() {
        let (states, calls, nonzero, granted) = sweep();
        println!("reply ctx cache: {states} states, {calls} cached-vs-uncached calls, {nonzero} with incoming > 0, {granted} states carry grant records");
        assert!(states >= 100 && nonzero >= 100, "the sweep must see real volleys or it proves nothing");
        assert!(granted > 0);
    }
