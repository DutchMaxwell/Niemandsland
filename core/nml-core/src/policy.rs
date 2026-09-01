//! NML-1158b step 4a — the POLICY net LOADER: `policy_net/1` JSON, the
//! `netlab/policy_train.py` export, gated the `fitted.rs` way (fitted.rs:51-105):
//! an unknown schema is refused, the layer shapes must agree, and the shipped
//! selftest row is RECOMPUTED — a drifted forward never ranks a menu. The
//! forward is `z = w2·relu(w1[phi; vec] + b1) + b2` per candidate (ONE hidden
//! layer, weights `[in][out]`, the fitted.rs/clone_train convention). The
//! per-candidate feature builder and `score_menu` land in step 4b, same file.

use std::cell::RefCell;
use std::collections::HashMap;

use serde::Deserialize;

use crate::geom;
use crate::menu::Candidate;
use crate::rows::{self, RowEncoder};
use crate::state::State;
use crate::terrain::{self, Terrain};
use crate::unit::UnitStatic;
use crate::IN2M;

/// The only schema this build reads — `netlab/policy_train.py:export`.
pub const POLICY_SCHEMA: &str = "policy_net/1";

/// `net["selftest"]`: the phi row, the per-candidate action vectors and the
/// logits the trainer computed — recomputed here at load time.
#[derive(Debug, Deserialize)]
pub struct PolicySelfTest {
    pub phi: Vec<f64>,
    pub vecs: Vec<Vec<f64>>,
    pub expected: Vec<f64>,
}

/// A `policy_train.py` policy net. `act_dim` follows the APPEND-ONLY action
/// vector (clone_train.py:50-64): 18 base slots, then cover, then sight —
/// slots may only ever be appended, never inserted.
#[derive(Debug, Deserialize)]
pub struct PolicyNet {
    pub schema: String,
    pub state_dim: usize,
    pub act_dim: usize,
    pub hidden: usize,
    pub w1: Vec<Vec<f64>>,
    pub b1: Vec<f64>,
    pub w2: Vec<f64>,
    pub b2: f64,
    #[serde(default)]
    pub selftest: Option<PolicySelfTest>,
}

impl PolicyNet {
    /// `fitted::Net::load` fitted.rs:105-112 — parse, then GATE.
    pub fn load(path: &str) -> Result<PolicyNet, String> {
        let text = std::fs::read_to_string(path)
            .map_err(|e| format!("policy net unreadable at {path}: {e}"))?;
        let net: PolicyNet = serde_json::from_str(&text)
            .map_err(|e| format!("policy net malformed at {path}: {e}"))?;
        net.gate()?;
        Ok(net)
    }

    /// How many terrain slots a net of this width carries — `AiClone.extras_for`
    /// ai_clone.gd:191-193: 0 = pre-terrain (18), 1 = cover (19), 2 = both (20).
    pub fn extras(&self) -> usize {
        (self.act_dim.saturating_sub(5 + 5 + 8)).min(2)
    }

    /// Shape + selftest gates. A wider `act_dim` is a schema this build cannot
    /// serve, never a silent re-index (ai_clone.gd:63-69 says the same).
    fn gate(&self) -> Result<(), String> {
        if self.schema != POLICY_SCHEMA {
            return Err(format!(
                "policy net rejected: schema {:?}, this build reads {POLICY_SCHEMA:?}",
                self.schema
            ));
        }
        if self.act_dim < 5 + 5 + 8 || self.act_dim > 5 + 5 + 8 + 2 {
            return Err(format!(
                "policy net rejected: act_dim {} — this build serves {}..{}",
                self.act_dim,
                5 + 5 + 8,
                5 + 5 + 8 + 2
            ));
        }
        if self.w1.len() != self.state_dim + self.act_dim
            || self.w1.first().map_or(0, |r| r.len()) != self.hidden
            || self.b1.len() != self.hidden
            || self.w2.len() != self.hidden
        {
            return Err("policy net rejected: layer shapes disagree".into());
        }
        let st = self
            .selftest
            .as_ref()
            .ok_or("policy net rejected: selftest block missing")?;
        if st.phi.len() != self.state_dim
            || st.expected.len() != st.vecs.len()
            || st.vecs.iter().any(|v| v.len() != self.act_dim)
        {
            return Err("policy net rejected: selftest block disagrees with the shapes".into());
        }
        for (i, v) in st.vecs.iter().enumerate() {
            let got = self.logit(&st.phi, v);
            let want = st.expected[i];
            // `AiClone.score_close` ai_clone.gd:303-305 — absolute + relative:
            // a f64 re-run of a f32-trained forward rounds, real drift fails.
            if (got - want).abs() > 1e-4 + want.abs() * 1e-6 {
                return Err(format!("policy net rejected: selftest {got:.6} != {want:.6}"));
            }
        }
        Ok(())
    }

    /// One candidate logit. `phi` first, the action vector appended; `b2`
    /// enters FIRST and `w2` accumulates — the order `AiClone.scores`
    /// (ai_clone.gd:180-186) uses, so the twin adds in the same order.
    pub fn logit(&self, phi: &[f64], vec: &[f64]) -> f64 {
        let mut z = self.b2;
        for (j, bj) in self.b1.iter().enumerate() {
            let mut acc = *bj;
            for (i, xi) in phi.iter().chain(vec.iter()).enumerate() {
                acc += xi * self.w1[i][j];
            }
            z += acc.max(0.0) * self.w2[j];
        }
        z
    }
}

// ---------------------------------------------------------------- step 4b --
// The per-candidate features and the play-time harness. EVERY arithmetic step
// below is the GDScript's own f64 path — the vectors must be BIT-IDENTICAL to
// what tools/policy_dump.gd writes for the same (state, candidate); that is
// the step-7 identity gate's foundation.

/// `AiClone.DEST_X_SCALE/DEST_Z_SCALE` ai_clone.gd:17-18 — the table's
/// half-width in inches; must match the trainer.
pub const DEST_X_SCALE: f64 = 36.0;
pub const DEST_Z_SCALE: f64 = 24.0;

/// Where the move ends, the tuple form `AiClone.menu_tuples` produces
/// (ai_clone.gd:106-139): inches snapped to 0.1, ALIVE-row indices, cover and
/// sight at the destination (-1 = no terrain/LOS source wired).
#[derive(Debug, Clone, Copy)]
pub struct MenuTuple {
    pub kind: i64,
    pub dest_x: f64,
    pub dest_z: f64,
    pub victim_row: i64,
    pub unit_row: i64,
    pub cover: i64,
    pub seen: i64,
    pub seen_of: i64,
}

/// `AiClone.menu_tuples` ai_clone.gd:106-139 — ONE source for the corpus dump
/// and for play, so what the clone scores is what it learned. `row_of` counts
/// ALIVE units in roster order; the nearest-3 foes are the LOS scope
/// (`LOS_NEAREST` ai_clone.gd:96), gathered once per activation — and
/// `seen_of` is the TRUNCATED count, exactly as the GDScript reassigns
/// `foes` before it reads its size.
pub fn menu_tuples(
    state: &State,
    terrain: &Terrain,
    unit: usize,
    cands: &[Candidate],
) -> Vec<MenuTuple> {
    let mut row_of: HashMap<&str, i64> = HashMap::new();
    let mut row = 0i64;
    for f in 0..state.units() {
        if state.alive[f] > 0 {
            row_of.insert(state.key(f), row);
            row += 1;
        }
    }
    let me = state.player[unit];
    let mut foes: Vec<(geom::V3, f64)> = Vec::new();
    if terrain.is_valid() {
        let mine = geom::centre(&state.positions[unit]);
        for f in 0..state.units() {
            if state.player[f] == me || state.alive[f] <= 0 {
                continue;
            }
            let fc = geom::centre(&state.positions[f]);
            foes.push((fc, geom::length(geom::sub(fc, mine)) as f64));
        }
        // STABLE sort: the GDScript's sort_custom is de-facto stable at these
        // army sizes, and a tie resolved differently would flip `seen`.
        foes.sort_by(|a, b| a.1.total_cmp(&b.1));
        foes.truncate(3);
    }
    let unit_row = row_of[state.key(unit)];
    cands.iter()
        .map(|c| {
            let dest = c.dest.unwrap_or([0.0, 0.0, 0.0]);
            let victim = c.charge.as_deref().or(c.shoot.as_deref()).unwrap_or("");
            let cover = if terrain.is_valid() {
                i64::from(terrain::gives_cover(terrain.type_at(geom::to_f32(dest))))
            } else {
                -1
            };
            let mut seen = -1i64;
            if terrain.is_valid() {
                let d3 = geom::to_f32(dest);
                seen = foes.iter()
                    .filter(|(fp, _)| !terrain.los_blocked(d3, *fp))
                    .count() as i64;
            }
            MenuTuple {
                kind: c.kind,
                dest_x: rows::snappedf(dest[0] / IN2M, 0.1),
                dest_z: rows::snappedf(dest[2] / IN2M, 0.1),
                victim_row: row_of.get(victim).copied().unwrap_or(-1),
                unit_row,
                cover,
                seen,
                seen_of: foes.len() as i64,
            }
        })
        .collect()
}

/// The three row classes `AiClone._near` distinguishes (ai_clone.gd:264-276).
#[derive(Clone, Copy)]
enum Near {
    Marker,
    Foe,
    Friend,
}

/// `AiClone._near` ai_clone.gd:264-276 — nearest board row of a class to
/// (x, z), 99.0 when nothing qualifies. The game-state row (type 4) reads as
/// a FOE here exactly as the GDScript's `c0 != 3 and c0 != side` has it.
fn near(board: &[Vec<f64>], class: Near, side: i64, actor_row: i64, x: f64, z: f64) -> f64 {
    let mut best: f64 = 99.0;
    for (i, r) in board.iter().enumerate() {
        let c0 = r[0] as i64;
        let skip = match class {
            Near::Marker => c0 != 3,
            Near::Foe => c0 == 3 || c0 == side,
            Near::Friend => c0 != side || i as i64 == actor_row,
        };
        if skip {
            continue;
        }
        let d = ((r[1] - x) * (r[1] - x) + (r[2] - z) * (r[2] - z)).sqrt();
        best = best.min(d);
    }
    best
}

/// `AiClone.geo_vec` ai_clone.gd:244-262 — where the move ENDS relative to
/// markers, the enemy and my own line, all from the SNAPPED tuple fields the
/// GDScript itself reads back. HOLD keeps its seat: dest = actor pos.
fn geo_vec(t: &MenuTuple, board: &[Vec<f64>], side: i64) -> [f64; 8] {
    let ur = t.unit_row;
    let (ax, az) = if ur >= 0 && (ur as usize) < board.len() {
        (board[ur as usize][1], board[ur as usize][2])
    } else {
        (0.0, 0.0)
    };
    let (mut dx, mut dz) = (t.dest_x, t.dest_z);
    if t.kind == 0 {
        dx = ax;
        dz = az;
    }
    let m_d = near(board, Near::Marker, side, ur, dx, dz);
    let m_now = near(board, Near::Marker, side, ur, ax, az);
    let f_d = near(board, Near::Foe, side, ur, dx, dz);
    let f_now = near(board, Near::Foe, side, ur, ax, az);
    [
        ((dx - ax) * (dx - ax) + (dz - az) * (dz - az)).sqrt() / 12.0,
        m_d / 12.0,
        if m_d <= 3.0 { 1.0 } else { 0.0 },
        (m_now - m_d) / 12.0,
        f_d / 12.0,
        (f_now - f_d) / 12.0,
        near(board, Near::Friend, side, ur, dx, dz) / 12.0,
        if f_d <= 1.0 { 1.0 } else { 0.0 },
    ]
}

/// `AiClone.action_vec` ai_clone.gd:198-246 — the compact action description,
/// byte-for-byte the trainer's. THE LAYOUT IS APPEND-ONLY (clone_train.py:50-64):
/// 5 one-hot kinds, 5 plain, 8 geo, then cover, then sight — an insertion would
/// silently re-point every weight of every net trained before it. The width
/// FOLLOWS THE NET (`extras`), so both generations stay playable side by side.
pub fn action_vec(t: &MenuTuple, board: &[Vec<f64>], side: i64, extras: usize) -> Vec<f64> {
    const KINDS: usize = 5;
    let mut v = vec![0.0; KINDS + 5 + 8 + extras.min(2)];
    if t.kind >= 0 && (t.kind as usize) < KINDS {
        v[t.kind as usize] = 1.0;
    }
    let span = board.len().max(1) as f64;
    v[KINDS] = t.dest_x / DEST_X_SCALE;
    v[KINDS + 1] = t.dest_z / DEST_Z_SCALE;
    v[KINDS + 2] = if t.victim_row >= 0 { 1.0 } else { 0.0 };
    v[KINDS + 3] = t.victim_row as f64 / span;
    v[KINDS + 4] = t.unit_row as f64 / span;
    for (i, g) in geo_vec(t, board, side).iter().enumerate() {
        v[KINDS + 5 + i] = *g;
    }
    if extras >= 1 {
        v[KINDS + 5 + 8] = if t.cover < 0 { 0.5 } else { t.cover as f64 };
    }
    if extras >= 2 {
        v[KINDS + 5 + 8 + 1] = if t.seen < 0 {
            0.5
        } else if t.seen_of <= 0 {
            0.0
        } else {
            t.seen as f64 / t.seen_of as f64
        };
    }
    v
}

/// `state_phi` (netlab/policy_train.py:50-70) — the 93-wide state row: three
/// 22-column pools (marker / own / foe) averaged over their rows, the three
/// row shares, the actor's own 22 columns, the side one-hot. The game-state
/// row (type 4) pools as a foe exactly as the trainer's `int(r[0])` reads it.
pub fn state_phi(board: &[Vec<f64>], side: i64, actor_row: i64) -> Vec<f64> {
    const FIXED: usize = 22;
    let mut pools = vec![0.0; 3 * FIXED];
    let mut n = [0.0f64; 3];
    for r in board {
        let c0 = r[0] as i64;
        let p = if c0 == 3 { 0 } else if c0 == side { 1 } else { 2 };
        for j in 0..FIXED.min(r.len()) {
            pools[p * FIXED + j] += r[j];
        }
        n[p] += 1.0;
    }
    let mut phi: Vec<f64> = Vec::with_capacity(3 * FIXED + 3 + FIXED + 2);
    for p in 0..3 {
        for j in 0..FIXED {
            phi.push(pools[p * FIXED + j] / n[p].max(1.0));
        }
    }
    let total = board.len().max(1) as f64;
    phi.extend(n.map(|c| c / total));
    for j in 0..FIXED {
        phi.push(if actor_row >= 0 && (actor_row as usize) < board.len() {
            board[actor_row as usize].get(j).copied().unwrap_or(0.0)
        } else {
            0.0
        });
    }
    phi.push(if side == 1 { 1.0 } else { 0.0 });
    phi.push(if side == 2 { 1.0 } else { 0.0 });
    phi
}

/// The play-time harness: the net plus its own row encoder — the `Fitted`
/// seam pattern (fitted.rs:264-269). Step 5 hangs the ORDER-mode re-rank off
/// this.
pub struct Policy {
    pub net: PolicyNet,
    enc: RefCell<RowEncoder>,
    /// NML-1158b step 7 — the `fitted_gate.py --red-scale` lever, ported: a
    /// multiplier on every returned logit, `1.0` in every shipping call. An
    /// ORDER gate compares a PERMUTATION, not a magnitude, so `scale < 0` is
    /// the red proof here — it reverses a unit's own within-menu order
    /// wherever it has two candidates the net does not tie.
    pub scale: f64,
}

impl Policy {
    pub fn new(net: PolicyNet, repo_root: &str) -> Result<Policy, String> {
        let enc = RowEncoder::for_version(repo_root, rows::RULE_VOCAB_VERSION);
        if !enc.vocab.loaded {
            return Err(enc.vocab.error.clone().unwrap_or_else(|| {
                format!("rule vocab unreadable at {repo_root}/{}", rows::RULE_VOCAB_PATH)
            }));
        }
        Ok(Policy { net, enc: RefCell::new(enc), scale: 1.0 })
    }

    /// `Fitted::set_source_qd` fitted.rs:282-287 — LEGACY REPLAY ONLY. A state
    /// rebuilt from a plain corpus replays with stand-in GameUnits whose blank
    /// `source_data` reads 4/4 in board columns 10/11 — the reading every
    /// Godot replay tool sees, and so the step-7 gate. phi reads those
    /// columns; nothing that plays a fresh game may set this.
    pub fn set_source_qd(&self, qd: Option<(i64, i64)>) {
        self.enc.borrow_mut().source_qd = qd;
    }

    /// One logit per menu candidate, in menu order. Softmax over ONE unit's
    /// menu happens at the caller — cross-menu logits are NOT calibrated
    /// (ai_planner.gd:672-676) — and so does the SHAKEN rule: a shaken unit's
    /// menu is the bare hold (plan_with_rollout:147), which candidates()
    /// itself never sees; the caller mirrors that, nothing is re-derived here.
    ///
    /// The actor's row for phi is BUG-COMPATIBLE -1: the trainer's build()
    /// recovers it from vec[8] (victim_row/span), which is -1 on the
    /// always-first bare HOLD — every phi policy_v1 trained on carried a ZERO
    /// actor block (policy_train.py:109). Step 6's twin must mirror THIS rule
    /// until the v2 retrain fixes the recovery to vec[9].
    pub fn score_menu(
        &self,
        state: &State,
        terrain: &Terrain,
        statics: &[UnitStatic],
        menu: &[Candidate],
    ) -> Vec<f64> {
        if menu.is_empty() {
            return Vec::new();
        }
        let actor = (0..state.units())
            .find(|i| state.key(*i) == menu[0].unit)
            .unwrap_or_else(|| panic!("score_menu: {} is not a live roster key", menu[0].unit));
        let board: Vec<Vec<f64>> = self
            .enc
            .borrow_mut()
            .board_rows(state, statics)
            .iter()
            .map(|r| r.iter().map(|c| c.as_f64()).collect())
            .collect();
        let side = state.player[actor];
        let tuples = menu_tuples(state, terrain, actor, menu);
        let phi = state_phi(&board, side, -1);
        let extras = self.net.extras();
        tuples
            .iter()
            .map(|t| self.scale * self.net.logit(&phi, &action_vec(t, &board, side, extras)))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn net_path() -> String {
        std::env::var("NML_POLICY_NET").unwrap_or_else(|_| {
            format!(
                "{}/nml-mission/netlab/nets/policy_v1.json",
                std::env::var("HOME").unwrap_or_default()
            )
        })
    }

    #[test]
    fn loader_refuses_unknown_schema_cleanly() {
        let p = std::env::temp_dir().join("nml_policy_unknown_schema.json");
        std::fs::write(
            &p,
            r#"{"schema":"policy_net/9","state_dim":93,"act_dim":20,"hidden":48,
                "w1":[],"b1":[],"w2":[],"b2":0.0}"#,
        )
        .unwrap();
        let err = PolicyNet::load(p.to_str().unwrap()).unwrap_err();
        assert!(err.contains("schema"), "clean schema error, got: {err}");
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn policy_v1_loads_and_gates_green() {
        let p = net_path();
        if !std::path::Path::new(&p).exists() {
            eprintln!("skip: no policy net at {p}");
            return;
        }
        let net = PolicyNet::load(&p).expect("policy_v1 must load and selftest green");
        assert_eq!((net.state_dim, net.act_dim, net.hidden), (93, 20, 48));
        assert_eq!(net.extras(), 2);
    }

    #[test]
    fn a_tampered_forward_fails_the_selftest_gate() {
        let p = net_path();
        if !std::path::Path::new(&p).exists() {
            eprintln!("skip: no policy net at {p}");
            return;
        }
        let mut net = PolicyNet::load(&p).expect("policy_v1 must load");
        net.b2 += 1.0; // RED control: any weight drift must refuse at load
        assert!(net.gate().is_err(), "tampered net must fail the selftest");
    }
}

// ---- step 4b identity tests: the crate vs the recorded dump, exact f64 ----

#[cfg(test)]
mod identity {
    use super::*;
    use crate::menu::{candidates_tuned, Tuning};
    use crate::rules::Registries;
    use crate::sim::{HOLD, Scratch};

    /// The checkout this crate lives in — the mechanics assets and the row
    /// vocabulary are read from there, exactly as the binaries read them.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The recorded corpus the identity is proven against (the
    /// tools/policy_dump.gd output for the qbg_ref games). Env-overridable;
    /// skipped when the corpus is not on this machine.
    fn fixtures() -> Option<(String, String, String)> {
        let home = std::env::var("HOME").ok()?;
        let pick = |env: &str, default: &str| {
            std::env::var(env).unwrap_or_else(|_| format!("{home}/{default}"))
        };
        let fx = (
            pick("NML_POLICY_DUMP", "selfplay_out/policy_rows_v1/dumps/qbg_ref_all.jsonl"),
            pick("NML_POLICY_CORPUS", "selfplay_out/qbg_ref"),
            pick("NML_POLICY_NET", "nml-mission/netlab/nets/policy_v1.json"),
        );
        if [&fx.0, &fx.1, &fx.2].iter().any(|p| !std::path::Path::new(p).exists()) {
            eprintln!("skip: policy identity fixtures missing");
            return None;
        }
        Some(fx)
    }

    /// One dump row's act, rebuilt exactly as tools/policy_dump.gd replayed
    /// it: state from the act line, terrain from the header, statics off the
    /// per-act effective profiles, and the LIVE menu — except a SHAKEN unit,
    /// whose menu is the bare hold (plan_with_rollout:147), which
    /// candidates() itself never sees; the charge gate rides the act's own
    /// `charge_gate` bit (act_recorder.gd:73).
    fn replay(
        corpus: &str,
        reg: &mut Registries,
        game: &str,
        act_no: usize,
        unit_key: &str,
    ) -> (State, Terrain, Vec<UnitStatic>, Vec<Candidate>, usize) {
        let path = format!("{corpus}/{game}/acts.jsonl");
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{path}: {e}"));
        let mut lines = text.lines();
        let header = crate::acts::read_act_header(lines.next().expect("header"))
            .expect("act header");
        let act_line =
            lines.nth(act_no - 1).unwrap_or_else(|| panic!("{path}: no act {act_no}"));
        let act: serde_json::Value = serde_json::from_str(act_line).unwrap();
        let charge_gate = act.get("charge_gate").and_then(|v| v.as_bool()).unwrap_or(true);
        let mut cache = crate::state::ProfileCache::new(header.profiles.clone());
        let mut roster = None;
        let state = crate::io::state_from_json(
            &act["state"].to_string(),
            &mut cache,
            &mut roster,
        )
        .expect("state");
        let statics: Vec<UnitStatic> =
            state.profiles.list.iter().map(|p| UnitStatic::build(reg, p)).collect();
        let actor = (0..state.units())
            .find(|i| state.key(*i) == unit_key)
            .unwrap_or_else(|| panic!("{game}:{act_no}: unit {unit_key} not live"));
        let menu = if state.shaken[actor] {
            vec![Candidate::new(unit_key, HOLD)]
        } else {
            candidates_tuned(
                &state,
                &header.terrain,
                &statics,
                actor,
                &mut Scratch::default(),
                Tuning { charge_gate, ..Tuning::default() },
            )
        };
        (state, header.terrain, statics, menu, actor)
    }

    /// STEP 4's GATE: the feature builder is BIT-IDENTICAL to what
    /// tools/policy_dump.gd wrote for the same (state, candidate) — 20 dumped
    /// menu rows, every candidate, every slot, exact f64 equality. The board
    /// is part of the claim: the dump's board feeds geo_vec and the span.
    #[test]
    fn feature_builder_is_bit_identical_to_the_dump() {
        let Some((dump_path, corpus, _net)) = fixtures() else { return };
        let mut reg = Registries::new(&repo_root());
        let mut enc = RowEncoder::new(&repo_root());
        // The dump's board is a REPLAY board: node_recheck.gd's stand-in
        // GameUnits carry no source_data, so columns 10/11 read the blank 4/4
        // (fitted.rs:278-283) — the encoder must read the same.
        enc.source_qd = Some((4, 4));
        let dump = std::fs::read_to_string(&dump_path).unwrap();
        let (mut rows_seen, mut vecs_seen) = (0usize, 0usize);
        for line in dump.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let row: serde_json::Value = serde_json::from_str(line).unwrap();
            if row["kind"] != "menu_row" {
                continue;
            }
            rows_seen += 1;
            let game = row["game"].as_str().unwrap();
            let act_no = row["act_no"].as_u64().unwrap() as usize;
            let unit = row["unit"].as_str().unwrap();
            let side = row["side"].as_i64().unwrap();
            let (state, terrain, statics, menu, actor) =
                replay(&corpus, &mut reg, game, act_no, unit);
            let board: Vec<Vec<f64>> = enc
                .board_rows(&state, &statics)
                .iter()
                .map(|r| r.iter().map(|c| c.as_f64()).collect())
                .collect();
            let want_board: Vec<Vec<f64>> =
                serde_json::from_value(row["board"].clone()).unwrap();
            for (i, (g, w)) in board.iter().zip(want_board.iter()).enumerate() {
                assert_eq!(g, w, "{game}:{act_no} {unit} board row {i}");
            }
            let cands = row["cands"].as_array().unwrap();
            assert_eq!(menu.len(), cands.len(), "{game}:{act_no} {unit} menu size");
            let tuples = menu_tuples(&state, &terrain, actor, &menu);
            for (ci, (t, cw)) in tuples.iter().zip(cands.iter()).enumerate() {
                let want: Vec<f64> = serde_json::from_value(cw["vec"].clone()).unwrap();
                let got = action_vec(t, &board, side, 2);
                assert_eq!(got.len(), want.len(), "{game}:{act_no} {unit} cand {ci} width");
                for (d, (gv, wv)) in got.iter().zip(want.iter()).enumerate() {
                    assert_eq!(
                        gv, wv,
                        "{game}:{act_no} {unit} cand {ci} slot {d}: {gv} vs {wv} (bits {:x} vs {:x})",
                        gv.to_bits(),
                        wv.to_bits()
                    );
                }
                vecs_seen += 1;
            }
            if rows_seen == 20 {
                break;
            }
        }
        assert_eq!(rows_seen, 20, "expected 20 dumped menu rows");
        eprintln!("identity: {rows_seen}/20 menu rows, {vecs_seen} candidate vectors bit-identical");
    }

    /// The loader + harness end to end: the real net scores one rebuilt
    /// fixture menu, one finite logit per candidate.
    #[test]
    fn policy_v1_scores_a_fixture_menu() {
        let Some((dump_path, corpus, net_path)) = fixtures() else { return };
        let net = PolicyNet::load(&net_path).expect("policy_v1 loads");
        let policy = Policy::new(net, &repo_root()).expect("row vocab");
        // Same replay reading as the identity gate: the fixture menu is scored
        // on a rebuilt (replayed) state, so columns 10/11 are the 4/4 blanks.
        policy.set_source_qd(Some((4, 4)));
        let mut reg = Registries::new(&repo_root());
        let dump = std::fs::read_to_string(&dump_path).unwrap();
        let row = dump
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(|l| serde_json::from_str::<serde_json::Value>(l).unwrap())
            .find(|r| r["kind"] == "menu_row")
            .expect("dump carries a menu_row");
        let (state, terrain, statics, menu, _actor) = replay(
            &corpus,
            &mut reg,
            row["game"].as_str().unwrap(),
            row["act_no"].as_u64().unwrap() as usize,
            row["unit"].as_str().unwrap(),
        );
        let scores = policy.score_menu(&state, &terrain, &statics, &menu);
        assert_eq!(scores.len(), menu.len());
        assert!(scores.iter().all(|s| s.is_finite()), "logits finite: {scores:?}");
        eprintln!("fixture menu scores: {scores:?}");
    }
}
