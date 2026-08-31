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

// ---- the per-side deploy stream's draw phases (NML-1152 step 3). `deploy_begin`
// (solo_controller.gd:8943-9047) seeds a FRESH rng per side (:8944-8945) and
// consumes it IN ORDER: transport fill (:8957-8976) → split_into_groups (:8986)
// → assign_sections (:8987) → placement_order (:9038, step 3b). Placement draws NOTHING.

/// `AiDeployment._shuffle` (ai_deployment.gd:239-244): Fisher-Yates, one
/// `randi_range(0, i)` draw per swap, top index down to 1.
fn shuffle(v: &mut [usize], rng: &mut GodotRng) {
    for i in (1..v.len()).rev() {
        let j = rng.randi_range(0, i as i64) as usize;
        v.swap(i, j);
    }
}

/// `AiDeployment.split_into_groups` (ai_deployment.gd:15-23): indices shuffled,
/// then dealt into 3 groups of equal size as far as possible (`k % 3`).
pub fn split_into_groups(count: usize, rng: &mut GodotRng) -> Vec<Vec<usize>> {
    let mut idx: Vec<usize> = (0..count).collect();
    shuffle(&mut idx, rng);
    let mut groups: Vec<Vec<usize>> = vec![Vec::new(), Vec::new(), Vec::new()];
    for (k, &i) in idx.iter().enumerate() {
        groups[k % 3].push(i);
    }
    groups
}

/// `AiDeployment.assign_sections` (ai_deployment.gd:27-43): one D3 per group,
/// the whole roll re-done while ALL groups would share one section; a single
/// group returns after its one draw (:34-35).
pub fn assign_sections(group_count: usize, rng: &mut GodotRng) -> Vec<i64> {
    if group_count == 0 {
        return Vec::new();
    }
    loop {
        let sections: Vec<i64> = (0..group_count).map(|_| rng.randi_range(1, 3)).collect();
        if group_count == 1 || sections.iter().any(|&s| s != sections[0]) {
            return sections;
        }
    }
}

/// `AiDeployment.placement_order` (ai_deployment.gd:54-67, called at
/// solo_controller.gd:9038): units deploy one at a time in RANDOM order —
/// normals shuffled, scouts shuffled after them, scouts deploy LAST, ambush
/// units excluded entirely (reserve, arrive round 2). Draw order: n_normal−1
/// Fisher-Yates draws, then n_scout−1. Returns spec indices in deploy order.
pub fn placement_order(specs: &[UnitSpec], rng: &mut GodotRng) -> Vec<usize> {
    let mut normal: Vec<usize> = Vec::new();
    let mut scouts: Vec<usize> = Vec::new();
    for (i, s) in specs.iter().enumerate() {
        if s.ambush {
            continue;
        }
        if s.scout {
            scouts.push(i);
        } else {
            normal.push(i);
        }
    }
    shuffle(&mut normal, rng);
    shuffle(&mut scouts, rng);
    normal.extend(scouts);
    normal
}

/// `deploy_begin`'s transport fill (solo_controller.gd:8957-8976). The caller
/// passes capacities of alive, unattached, not-already-embarked units in
/// game-unit list order. Each transport (capacity > 0, list order) loads random
/// non-transport units up to its cargo limit: one `randi_range(0, len-1)` draw
/// per pop from a duplicated candidate pool until drained — the final pop (one
/// candidate left) draws NOTHING (the engine's `randi_range(0,0)` fast path).
/// The capacity gate is a unit-count stand-in for the engine's space-count
/// can_embark (opr_army_manager.gd:2930: `unit_embark_spaces` vs
/// `cap − transport_used_spaces`, plus untransportable/pre-embarked failures
/// not mirrored) — exact for the transport-free corpus lists. Returns
/// (transport, cargo) index pairs.
pub fn transport_fill(capacities: &[i64], rng: &mut GodotRng) -> Vec<(usize, usize)> {
    let mut fills: Vec<(usize, usize)> = Vec::new();
    let mut pool: Vec<usize> = (0..capacities.len()).filter(|&i| capacities[i] <= 0).collect();
    for tr in 0..capacities.len() {
        if capacities[tr] <= 0 {
            continue;
        }
        let mut tries = pool.clone();
        let mut loaded = 0usize;
        while !tries.is_empty() {
            let pick = tries.remove(rng.randi_range(0, tries.len() as i64 - 1) as usize);
            if loaded < capacities[tr] as usize {
                loaded += 1;
                let at = pool.iter().position(|&p| p == pick).expect("pick in pool");
                pool.remove(at);
                fills.push((tr, pick));
            }
        }
    }
    fills
}
