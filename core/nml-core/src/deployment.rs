//! NML-1152 step 2 — the arena pre-game's shared seam: the roll-off and the per-side
//! deploy seeds. The roll-off consumes the GAME stream (`solo._rng`, arena_match.gd:373
//! → :462) BEFORE deployment; each side's deployment gets a FRESH stream seeded
//! `game_seed + slot` attached to the SLOT (arena_match.gd:487), never the game stream.
//! `roll_off_traced` mirrors `SoloController.roll_off` (solo_controller.gd:7507-7524):
//! 2 `randi_range(1, 6)` draws per attempt, ties re-roll, cap 100 — trace kept because
//! the attempt count is data-dependent (the gate compares the FULL attempt list).

use crate::rng::GodotRng;

/// `SoloController.roll_off`'s tie cap (solo_controller.gd:7508).
pub const ROLL_OFF_CAP: usize = 100;

/// One roll-off outcome: every d6 pair in order, then the winner (1 or 2) —
/// the fixture's `roll_off_attempts` + `opener` (research knobs unset).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RollOff {
    pub attempts: Vec<(i64, i64)>,
    pub winner: i64,
}

/// Pregame input for one unit, built py-side from the list profile (§3.2).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct UnitSpec {
    pub key: String,
    pub model_count: i64,
    pub base_r_m: f64,
    pub footprint: Vec<(f64, f64)>,
    pub scout: bool,
    pub ambush: bool,
    pub ignores_terrain: bool,
    pub vanguard: bool,
    pub transport_capacity: i64,
}

/// One unit's deployed result (slice 5/6 fill this; the gate compares it).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Placement {
    pub key: String,
    pub section: i64,
    pub scout: bool,
    pub spot: (f64, f64),
    pub vanguard_pushed: bool,
    pub models: Vec<(f64, f64)>,
}

/// One side's full deployment result — the fixture's `sides[slot]`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct SideDeploy {
    pub seed_value: i64,
    pub fills: Vec<(String, String)>,
    pub placements: Vec<Placement>,
    pub reserved: Vec<String>,
}

/// `SoloController.roll_off` with the trace kept (fallback winner 1 after the cap).
pub fn roll_off_traced(rng: &mut GodotRng) -> RollOff {
    let mut attempts = Vec::new();
    for _ in 0..ROLL_OFF_CAP {
        let d1 = rng.randi_range(1, 6);
        let d2 = rng.randi_range(1, 6);
        attempts.push((d1, d2));
        if d1 != d2 {
            return RollOff { attempts, winner: if d1 > d2 { 1 } else { 2 } };
        }
    }
    RollOff { attempts, winner: 1 }
}

/// The per-side deploy seed, attached to the SLOT: `_seed + slot`
/// (arena_match.gd:487 → pregame_dump.gd `seed_value = seed_v + slot`).
pub fn side_seed_value(game_seed: i64, slot: i64) -> i64 {
    game_seed + slot
}

/// Roll-off winner deploys first (arena_match.gd:500).
pub fn deploy_order(winner: i64) -> [i64; 2] {
    if winner == 1 {
        [1, 2]
    } else {
        [2, 1]
    }
}
