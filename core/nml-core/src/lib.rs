//! Niemandsland fast rules core — NML-1073, milestone 1.
//!
//! Nothing in this crate is loaded by the game. It is a standalone Rust port of
//! the GDScript rollout node (`BattleSim` + `AiMissionEval`); the JSONL node
//! corpus written by `AiPlanner._record_node` is the contract between the two.
//! Every ported function names its GDScript origin as `file:line`.

pub mod io;
pub mod score;
pub mod state;

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

pub use io::{load_nodes, read_nodes, Node, NodeCorpus};
pub use score::{can_hold_marker, control_gap_in, presence, score, Incoming, NO_INCOMING};
pub use state::{Marker, Mods, Objective, Profile, Profiles, State, Weapon};
