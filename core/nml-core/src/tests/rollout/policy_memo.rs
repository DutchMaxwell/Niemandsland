//! `playout_memo` — the exact per-worker memo of `Policy::policy_step`. Every input of the step, changed ALONE, must
//! miss; the unchanged call must hit; a hit must equal the fresh answer. RED: break the key (drop the `State ==`, the
//! player, the config compare ...) and the matching case here fails (see the PR body).
use super::rush_demotion::{HEADER, PLAIN};
use super::*;
use crate::menu::{Candidate, Tuning};
use crate::playout_memo as pm;

fn terrain() -> Terrain {
    Terrain::build(&crate::terrain::PlainTerrain {
        cells: vec![[15.0, 15.0, crate::terrain::FOREST as f64]],
        sandbox: Vec::<crate::terrain::Obb>::new(),
        pieces: vec![],
        walls: vec![],
        cell_params: crate::terrain::CellParams {
            table_size_feet: [6.0, 4.0],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 3.0,
            inches_to_meters: crate::IN2M,
        },
    })
}

fn state() -> State {
    let header = read_act_header(HEADER).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let mut roster = None;
    io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state")
}

fn seams() -> Seams {
    Seams { rules_epoch: CURRENT_RULES_EPOCH, moved_shoot: true, ..Seams::default() }
}

/// `policy_step` of `pol`, rendered; `sc_epoch` rides in `Scratch.rules_epoch` (an input of the key).
fn step(pol: &Policy, st: &State, player: i64, rich: bool, sc_epoch: u32) -> String {
    let mut sc = Scratch { rules_epoch: sc_epoch, ..Scratch::default() };
    format!("{:?}", pol.policy_step(st, player, rich, &mut sc))
}

/// The ground truth: the same call with the memo off (no scope).
fn fresh(pol: &Policy, st: &State, player: i64, rich: bool, sc_epoch: u32) -> String {
    drop(pm::enter(0, 0, pol, st));
    step(pol, st, player, rich, sc_epoch)
}

fn mem<F: FnOnce() -> R, R>(f: F) -> R {
    let _k = crate::mv::step::tests::KNOB_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    pm::begin_game();
    f()
}

#[test]
fn an_identical_second_call_hits_and_equals_the_fresh_answer() {
    mem(|| {
        let (st, t) = (state(), terrain());
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        let pol = Policy::new(&statics, &t, seams());
        let want = fresh(&pol, &st, 1, true, 0);
        let _s = pm::enter(7, t.uid(), &pol, &st);
        assert_eq!(step(&pol, &st, 1, true, 0), want);
        assert_eq!(pm::stats(), (1, 0));
        assert_eq!(step(&pol, &st, 1, true, 0), want, "the stored answer is the fresh one");
        assert_eq!(pm::stats(), (2, 1), "the repeat is a hit");
    });
}

#[test]
fn off_without_a_scope_and_for_any_other_policy_object() {
    mem(|| {
        let (st, t) = (state(), terrain());
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        let (pol, other) = (Policy::new(&statics, &t, seams()), Policy::new(&statics, &t, seams()));
        step(&pol, &st, 1, true, 0);
        step(&pol, &st, 1, true, 0);
        assert_eq!((pm::stats(), pm::stored()), ((0, 0), 0), "no scope, no memo");
        let _s = pm::enter(7, t.uid(), &pol, &st);
        step(&other, &st, 1, true, 0);
        step(&other, &st, 1, true, 0);
        assert_eq!((pm::stats(), pm::stored()), ((0, 0), 0), "an equal Policy at another address is not the scoped one");
        let force = Policy { force_leaf: Some(true), ..Policy::new(&statics, &t, seams()) };
        let _s = pm::enter(7, t.uid(), &force, &st);
        step(&force, &st, 1, true, 0);
        assert_eq!(pm::stats(), (0, 0), "force_leaf is never memoised");
    });
}

/// Every INPUT of `policy_step`, changed alone, must miss, equal the fresh answer, and hit on its own repeat.
#[test]
fn every_single_input_change_misses_and_matches_fresh() {
    mem(|| {
        let (base, t) = (state(), terrain());
        let statics = statics_of(&base, CURRENT_RULES_EPOCH);
        let pol = Policy::new(&statics, &t, seams());
        let _s = pm::enter(7, t.uid(), &pol, &base);
        step(&pol, &base, 1, true, 0);
        type Edit = Box<dyn Fn(&mut State)>;
        let edits: Vec<(&str, Edit)> = vec![
            ("objectives", Box::new(|s| s.objectives[0].pos = [-0.4, 0.0, 0.0])),
            ("round", Box::new(|s| s.round += 1)),
            ("rounds_total", Box::new(|s| s.rounds_total += 1)),
            ("alive", Box::new(|s| s.alive[1] = 0)),
            ("activated", Box::new(|s| s.activated[1] = true)),
            ("shaken", Box::new(|s| s.shaken[0] = true)),
            ("fatigued", Box::new(|s| s.fatigued[0] = true)),
            ("in_cover", Box::new(|s| s.in_cover[1] = true)),
            ("casts", Box::new(|s| s.casts[0] = 1)),
            ("wound_frac", Box::new(|s| s.wound_frac[1] = 0.5)),
            ("positions (mover)", Box::new(|s| s.positions[0][0][0] += 1e-9)),
            ("positions (target)", Box::new(|s| s.positions[1][0][0] -= 0.2)),
            ("positions (sign of zero)", Box::new(|s| s.positions[0][0][1] = -0.0)),
            ("wounds", Box::new(|s| s.wounds[1][0] = 3)),
            ("bands", Box::new(|s| s.bands[0].advance += 1.0)),
            ("moved_round", Box::new(|s| s.moved_round[0] = 1)),
            ("scoring", Box::new(|s| s.scoring = Rc::from("x"))),
            ("profiles", Box::new(|s| {
                let mut list = s.profiles.list.clone();
                list[0].special_rules.push("Flying".into());
                s.profiles = Rc::new(crate::state::Profiles { list, index: s.profiles.index.clone() });
            })),
        ];
        let mut differs_outside_bucket = 0;
        for (name, edit) in &edits {
            let mut s2 = base.clone();
            edit(&mut s2);
            assert!(s2 != base || *name == "positions (sign of zero)", "edit `{name}` changed nothing");
            let want = fresh(&pol, &s2, 1, true, 0);
            let _s = pm::enter(7, t.uid(), &pol, &base);
            let (calls, hits) = pm::stats();
            assert_eq!(step(&pol, &s2, 1, true, 0), want, "`{name}`: the answer must be the fresh one");
            assert_eq!(pm::stats(), (calls + 1, hits), "`{name}` changed alone must miss");
            assert_eq!(step(&pol, &s2, 1, true, 0), want);
            assert_eq!(pm::stats(), (calls + 2, hits + 1), "`{name}`: its own repeat must hit");
            differs_outside_bucket += usize::from(want != fresh(&pol, &base, 1, true, 0) && ["objectives", "profiles"].contains(name));
        }
        assert!(differs_outside_bucket > 0, "the table must hold a field outside the bucket hash that changes the answer");
        // arguments of the call
        for (name, p, rich, ep) in [("player", 2, true, 0), ("rich", 1, false, 0), ("scratch epoch", 1, true, 9)] {
            let want = fresh(&pol, &base, p, rich, ep);
            let _s = pm::enter(7, t.uid(), &pol, &base);
            let (calls, hits) = pm::stats();
            assert_eq!(step(&pol, &base, p, rich, ep), want, "{name}");
            assert_eq!(pm::stats(), (calls + 1, hits), "argument `{name}` changed alone must miss");
        }
    });
}

/// The config of the playout: generation, terrain, seams, tuning, root state. Each changed alone must miss.
#[test]
fn every_config_change_misses() {
    mem(|| {
        let (st, t) = (state(), terrain());
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        let pol = Policy::new(&statics, &t, seams());
        let seen = |gen: u64, uid: u64, p: &Policy, root: &State| {
            let _s = pm::enter(gen, uid, p, root);
            let (_, h0) = pm::stats();
            step(p, &st, 1, true, 0);
            pm::stats().1 - h0
        };
        assert_eq!(seen(7, t.uid(), &pol, &st), 0);
        assert_eq!(seen(7, t.uid(), &pol, &st), 1, "same config: hit");
        assert_eq!(seen(8, t.uid(), &pol, &st), 0, "generation");
        assert_eq!(seen(7, t.uid() + 1, &pol, &st), 0, "terrain");
        let tuned = Policy { tuning: Tuning { rush_k: 2, ..Tuning::default() }, ..Policy::new(&statics, &t, seams()) };
        assert_eq!(seen(7, t.uid(), &tuned, &st), 0, "tuning");
        let other = Policy::new(&statics, &t, Seams { moved_shoot: false, ..seams() });
        assert_eq!(seen(7, t.uid(), &other, &st), 0, "seams");
        let mut root = st.clone();
        root.positions[1][0][2] += 0.01;
        assert_eq!(seen(7, t.uid(), &pol, &root), 0, "root state (the reach index is built from it)");
        assert_eq!(seen(7, t.uid(), &pol, &st), 1, "the first config is still there");
    });
}

#[test]
fn the_table_is_bounded_and_a_new_game_forgets_everything() {
    mem(|| {
        let (st, t) = (state(), terrain());
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        let pol = Policy::new(&statics, &t, seams());
        let _s = pm::enter(7, t.uid(), &pol, &st);
        let mut last = st.clone();
        for i in 0..pm::MAX_ENTRIES + 40 {
            last = st.clone();
            last.positions[1][0][0] -= 1e-6 * (i + 1) as f64;
            step(&pol, &last, 1, true, 0);
            assert!(pm::stored() <= pm::MAX_ENTRIES, "never above the cap");
        }
        let (_, h0) = pm::stats();
        step(&pol, &last, 1, true, 0);
        assert_eq!(pm::stats().1, h0 + 1, "after the overflow drop the newest answers are stored again");
        pm::begin_game();
        assert_eq!((pm::stored(), pm::stats()), (0, (0, 0)));
    });
}

/// The Scratch BUFFERS (`keep`, `attacks`, `fold`) are not part of the key: every filler clears them before it reads.
/// A hit with junk left in them must still equal the fresh answer (in debug the hit's own check re-runs on the junk).
#[test]
fn scratch_buffers_are_not_an_input() {
    mem(|| {
        let (st, t) = (state(), terrain());
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        let pol = Policy::new(&statics, &t, seams());
        let want = fresh(&pol, &st, 1, true, 0);
        let _s = pm::enter(7, t.uid(), &pol, &st);
        assert_eq!(step(&pol, &st, 1, true, 0), want);
        let mut sc = Scratch { keep: vec![9; 7], attacks: vec![-3; 5], fold: vec![Default::default(); 2], ..Scratch::default() };
        assert_eq!(format!("{:?}", pol.policy_step(&st, 1, true, &mut sc)), want);
        assert_eq!(pm::stats(), (2, 1), "the junk-buffer call is a hit");
    });
}

/// RED for the debug check itself: a stored answer that is NOT the fresh one must panic on its hit. Removing the
/// check, or weakening it so it compares nothing (the #1819 form compared `Some(..)` with `Ok(Some(..))` and failed
/// on EVERY hit), fails one of these two or the hit tests above.
#[cfg(debug_assertions)]
fn stale_hit_panics(edit: impl Fn(&mut Option<Candidate>, &mut (u32, bool))) {
    mem(|| {
        let (st, t) = (state(), terrain());
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        let pol = Policy::new(&statics, &t, seams());
        let _s = pm::enter(7, t.uid(), &pol, &st);
        assert!(step(&pol, &st, 1, true, 0).starts_with("Ok(Some("), "the stored answer is a move");
        pm::tamper(edit);
        step(&pol, &st, 1, true, 0);
    });
}

#[cfg(debug_assertions)]
#[test]
#[should_panic(expected = "policy_step memo hit != fresh")]
fn debug_check_catches_a_stale_answer() {
    stale_hit_panics(|a, _| *a = None);
}

#[cfg(debug_assertions)]
#[test]
#[should_panic(expected = "policy_step memo hit != fresh")]
fn debug_check_catches_a_stale_post_state() {
    stale_hit_panics(|_, post| post.0 += 1);
}
