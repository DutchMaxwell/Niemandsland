//! Niemandsland fast rules core — NML-1073, milestone 1.
//!
//! Nothing in this crate is loaded by the game. It is a standalone Rust port of
//! the GDScript rollout node (`BattleSim` + `AiMissionEval`); the JSONL node
//! corpus written by `AiPlanner._record_node` is the contract between the two.
//! Every ported function names its GDScript origin as `file:line`.

pub mod acts;
pub mod arbitration;
pub mod combat;
pub mod gate;
pub mod geom;
pub mod io;
pub mod menu;
pub mod mission;
pub mod mv;
pub mod plan;
pub mod playout;
pub mod rng;
pub mod rollout;
pub mod rules;
pub mod score;
pub mod sim;
pub mod spell;
pub mod state;
pub mod terrain;
pub mod unit;

/// `BattleSim.IN2M` — battle_sim.gd:11. Table units are metres, the book is inches.
pub const IN2M: f64 = 0.0254;
/// `SoloController.OBJECTIVE_CONTROL_IN` — solo_controller.gd:21.
pub const OBJECTIVE_CONTROL_IN: f64 = 3.0;
/// `BattleSim.CONTROL_EPS` — battle_sim.gd:656, the float guard on the 3" ring.
pub const CONTROL_EPS: f64 = 0.001;
/// `AiMissionEval.DISCOUNT` — ai_mission_eval.gd:11.
pub const DISCOUNT: f64 = 0.5;
/// `AiMissionEval.DESTROY_DEFENCE_WEIGHT` — ai_mission_eval.gd:410.
pub const DESTROY_DEFENCE_WEIGHT: f64 = 0.8;

pub use acts::{
    load_acts, read_act_header, read_acts, Act, ActCorpus, ActHeader, ActStatics, ArbitrationRec,
    Expectation, Knobs, PickRec, RolloutValue, RunnerRec, Scored,
};
pub use arbitration::{
    arbitrate, arbitrate_bent, full_playout, full_playout_bent, ArbBend, Arbitration,
    PlayoutResult, PLAYOUT_CAP, PLAYOUT_DECIDE_MARGIN, PLAYOUT_MAX_ROUNDS,
};
pub use gate::{charge_illegal, charge_illegal_tuned};
pub use io::{
    load_nodes, plain_of, read_nodes, state_from_json, Action, Node, NodeCorpus, Seams,
};
pub use menu::{candidates, candidates_in, candidates_tuned, Candidate, Tuning};
pub use mv::{load_moves, read_moves, MoveCall, MoveCorpus, MoveHeader};
pub use mission::{
    apply_destroy_step, mission_winner, playout_seize, sabotage_winner, vp_end_bonus,
    vp_round_add, vp_score_end, vp_score_round,
};
pub use plan::{
    build_pool, plan, plan_with_rollout, plan_with_rollout_sig, rank, OnePly, Pick, PlanBend,
    ScoredRow, Search,
};
pub use playout::{other_player, Policy};
pub use rollout::{cross_round, imagined_round_end, Rollout, Stop};
pub use rng::GodotRng;
pub use rules::Registries;
pub use score::{can_hold_marker, control_gap_in, presence, score, Incoming, NO_INCOMING};
pub use sim::{
    reply_threat, resolve, resolve_on_board, resolve_stochastic_on_board, Cover, Unsupported,
    ADVANCE, CHARGE, CHARGE_CONTACT_MARGIN_IN, CONTACT_IN, DEFAULT_BASE_RADIUS_M, HOLD,
    MELEE_ENGAGE_IN, RUSH, SPACING_BISECTIONS, SPACING_SAMPLES, UNIT_SPACING_IN,
};
pub use state::{
    Bands, Marker, Mods, Objective, Profile, ProfileCache, ProfileDyn, Profiles, State, Weapon,
};
pub use terrain::{PlainTerrain, Terrain};
pub use unit::{StaticsCache, Unimplemented, UnitStatic};

/// Builds the per-unit static closure for a whole corpus, in profile-table order.
/// `repo_root` is the checkout the mechanics assets are read from
/// (`assets/solo/rules_mechanics_<system>.json`, `spells_mechanics_<system>.json`).
pub fn build_statics(corpus: &NodeCorpus, repo_root: &str) -> Vec<UnitStatic> {
    statics_of(&corpus.profiles, repo_root)
}

/// The ONE static closure of an act corpus whose every activation reads the
/// header's own profile table — the shape the benches and the sweep tests want.
///
/// PANICS on a corpus where a dynamic profile read moved mid-game (a hero fell,
/// a spell granted a rule): there is no single closure for such a corpus, and
/// quietly handing back the header's would be exactly the staleness NML-1073
/// M2-5b removed. Use `act_statics` and a per-act `Policy` there.
pub fn build_act_statics(corpus: &ActCorpus, repo_root: &str) -> Vec<UnitStatic> {
    let moved = corpus
        .acts
        .iter()
        .position(|a| !std::rc::Rc::ptr_eq(&a.state.profiles, &corpus.profiles));
    if let Some(i) = moved {
        panic!(
            "act {} reads a profile table the header does not carry (a dynamic \
             profile read moved mid-game) — use act_statics(), not build_act_statics()",
            i + 1
        );
    }
    statics_of(&corpus.profiles, repo_root)
}

/// The per-ACTIVATION static closure of an act corpus — one entry per act, in
/// act order (NML-1073 M2-5b).
///
/// The act line carries the profile fields a live game rewrites (a dead hero's
/// inherited rules, a Caster Group's alive count, a spelled-on rule list), so a
/// closure derived once from the header answers with the deployment reading from
/// the activation where one of them first moves. Entries are interned: acts that
/// read alike share one `Rc`, and the whole corpus shares one when nothing ever
/// changed.
pub fn act_statics(corpus: &ActCorpus, repo_root: &str) -> Vec<std::rc::Rc<Vec<UnitStatic>>> {
    let mut reg = Registries::new(repo_root);
    let mut cache = StaticsCache::new();
    corpus.acts.iter().map(|a| cache.get(&mut reg, &a.state.profiles)).collect()
}

fn statics_of(profiles: &Profiles, repo_root: &str) -> Vec<UnitStatic> {
    let mut reg = Registries::new(repo_root);
    profiles.list.iter().map(|p| UnitStatic::build(&mut reg, p)).collect()
}
