//! NML-1142 — the FITTED eval, the half `score.rs` used to decline.
//!
//! Ported expression by expression from `AiMissionEval._score_encoder` /
//! `_encoder_canon` / `_lin_relu` / `_encoder_forward` / `_encoder_selftest_ok`
//! (ai_mission_eval.gd:140-315) and the blend at `score` (:344-354).
//!
//! The net is an ENCODER net — the export of `netlab/fork_train.py`: it scores
//! the RAW BOARD ROWS (`rows::RowEncoder::board_rows`, which this module REUSES
//! rather than re-encoding) plus the 30 standardised eval features. A POLICY net
//! (`AiClone`, `row_w1`/`act_dim`, `netlab/clone_train.py`) is a different
//! function with a different forward and is NOT served here — see
//! `Search::admissible`, which still declines `playout_net` as `NetPlayout`.
//!
//! Two seams are load-bearing and reproduced, not approximated:
//!
//! * the SELFTEST gate (:297-315) — a net that carries no `selftest` block, or
//!   whose block the forward here misses by more than 1e-4, is REFUSED. A
//!   silently drifted canonicalisation must never score games.
//! * the `slots` map ships INSIDE the weights JSON, but the ROW it indexes comes
//!   out of this build's rule vocabulary. A net trained under a different
//!   `vocab_version` is refused for that reason alone.

use std::cell::RefCell;
use std::collections::HashMap;

use serde::Deserialize;

use crate::rows::{self, RowEncoder, FEATURE_KEYS, RULE_VOCAB_VERSION};
use crate::score::Incoming;
use crate::state::State;
use crate::unit::UnitStatic;

/// `AiMissionEval.FIT_BLEND_DEFAULT` ai_mission_eval.gd:330 — the fitted share.
/// The hand eval keeps the move gradient; pure fit played WORSE (37% vs 40.5%).
pub const FIT_BLEND_DEFAULT: f64 = 0.5;

/// NML-1158a — HOW an armed net joins the hand eval. `Blend` is the E4.2 mix
/// the table plays. `Residual` reads the net's sigmoid as a DELTA on the hand
/// scale: the trainer's label was `outcome - f(hand)` centred, shipped as
/// `(delta + 1) / 2`, so the core reads `delta = 2*p - 1` (neutral at p = 0.5)
/// and plays `hand + delta`. ONE scale definition, owned here: the net's
/// sigmoid is `(delta + 1) / 2` on the hand scale, in both modes, always.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FitMode {
    Blend,
    Residual,
}

/// The exported holdout row every encoder net must carry — `net["selftest"]`.
#[derive(Deserialize)]
pub struct SelfTest {
    /// RAW `BattleSim.board_rows` output, not canonicalised.
    pub board: Vec<Vec<f64>>,
    pub side: i64,
    /// The 30 feature VALUES in `keys` order, un-standardised.
    pub features: Vec<f64>,
    pub expected: f64,
}

/// A `fork_train.py` encoder net. Matrices are `[in][out]` (torch transposed),
/// exactly as the GDScript reads them.
#[derive(Deserialize)]
pub struct Net {
    pub keys: Vec<String>,
    pub mu: Vec<f64>,
    pub sd: Vec<f64>,
    /// Rule-vocabulary slot -> dense column pair. JSON object keyed by the slot
    /// number as a string, which is how `_encoder_canon` looks it up (:239).
    pub slots: HashMap<i64, usize>,
    pub unit_w1: Vec<Vec<f64>>,
    pub unit_b1: Vec<f64>,
    pub unit_w2: Vec<Vec<f64>>,
    pub unit_b2: Vec<f64>,
    pub head_w1: Vec<Vec<f64>>,
    pub head_b1: Vec<f64>,
    pub head_w2: Vec<f64>,
    pub head_b2: f64,
    /// The vocabulary the `slots` map was built against; `None` on a net old
    /// enough not to stamp it, which is then taken on trust.
    #[serde(default)]
    pub vocab_version: Option<i64>,
    #[serde(default)]
    pub selftest: Option<SelfTest>,
}

/// `AiMissionEval._lin_relu` ai_mission_eval.gd:248-256 — one dense layer, relu.
fn lin_relu(x: &[f64], w: &[Vec<f64>], b: &[f64]) -> Vec<f64> {
    let mut out = Vec::with_capacity(b.len());
    for (j, bj) in b.iter().enumerate() {
        let mut acc = *bj;
        for (i, xi) in x.iter().enumerate() {
            acc += xi * w[i][j];
        }
        out.push(acc.max(0.0));
    }
    out
}

/// `AiMissionEval._feature_value` ai_mission_eval.gd:452-460 over the feature
/// VECTOR: a weight key may be a PRODUCT `a*b` or a size-normalising RATIO `a/b`
/// whose denominator floors at 1. A name the vector does not carry reads 0.
pub fn feature_value(f: &[f64], key: &str) -> f64 {
    let one = |name: &str| {
        FEATURE_KEYS.iter().position(|k| *k == name).map_or(0.0, |i| f[i])
    };
    if let Some((a, b)) = key.split_once('*') {
        return one(a) * one(b);
    }
    if let Some((a, b)) = key.split_once('/') {
        return one(a) / one(b).max(1.0);
    }
    one(key)
}

impl Net {
    /// `AiMissionEval._net` ai_mission_eval.gd:86-102 — parse, then GATE.
    pub fn load(path: &str) -> Result<Net, String> {
        let text = std::fs::read_to_string(path)
            .map_err(|e| format!("net unreadable at {path}: {e}"))?;
        let net: Net =
            serde_json::from_str(&text).map_err(|e| format!("net malformed at {path}: {e}"))?;
        net.gate()?;
        Ok(net)
    }

    /// The width of one canonical row: 22 fixed columns plus the densified pairs.
    fn canon_width(&self) -> usize {
        22 + 2 * self.slots.len()
    }

    /// `_encoder_selftest_ok` ai_mission_eval.gd:297-315, plus the two shape
    /// checks the GDScript gets for free by crashing.
    fn gate(&self) -> Result<(), String> {
        if let Some(v) = self.vocab_version {
            if v != RULE_VOCAB_VERSION {
                return Err(format!(
                    "encoder net rejected: slots built at rule vocabulary v{v}, this build reads v{RULE_VOCAB_VERSION}"
                ));
            }
        }
        if self.unit_w1.len() != self.canon_width() || self.unit_b1.len() != self.unit_b2.len() {
            return Err("encoder net rejected: unit layer does not match the canonical row".into());
        }
        if self.keys.len() != self.mu.len() || self.keys.len() != self.sd.len() {
            return Err("encoder net rejected: keys/mu/sd disagree".into());
        }
        let st = self
            .selftest
            .as_ref()
            .ok_or("encoder net rejected: selftest block missing")?;
        let got = self.forward(&st.board, st.side, &self.standardise(&st.features));
        if (got - st.expected).abs() > 1e-4 {
            return Err(format!(
                "encoder net rejected: selftest {got:.6} != expected {:.6}",
                st.expected
            ));
        }
        Ok(())
    }

    /// `(v - mu) / max(sd, 1e-6)` per key — :145-147 and :299-303 share it.
    fn standardise(&self, vals: &[f64]) -> Vec<f64> {
        (0..self.keys.len())
            .map(|i| (vals[i] - self.mu[i]) / self.sd[i].max(1e-6))
            .collect()
    }

    /// The 30 standardised inputs off a `rows::features` vector.
    fn xs_of(&self, f: &[f64]) -> Vec<f64> {
        let vals: Vec<f64> = self.keys.iter().map(|k| feature_value(f, k)).collect();
        self.standardise(&vals)
    }

    /// `AiMissionEval._encoder_canon` ai_mission_eval.gd:209-246 — ONE raw board
    /// row into the trainer's canonical form: mine-flag perspective, a
    /// 180-degree rotation for player 2, the /30-style norms, and the sparse
    /// rule pairs densified through `slots`.
    fn canon(&self, u: &[f64], side: i64) -> Vec<f64> {
        let (mut x, mut z) = (u[1], u[2]);
        if side == 2 {
            x = -x;
            z = -z;
        }
        let mut row = Vec::with_capacity(self.canon_width());
        if u[0] as i64 == 3 {
            let owner = u[3] as i64;
            let rel = if owner == side { 1.0 } else if owner != 0 { -1.0 } else { 0.0 };
            row.extend_from_slice(&[0.0, x / 30.0, z / 30.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, rel]);
            row.resize(self.canon_width(), 0.0);
            return row;
        }
        #[rustfmt::skip]
        row.extend_from_slice(&[
            if u[0] as i64 == side { 1.0 } else { 0.0 }, x / 30.0, z / 30.0,
            u[3] / 10.0, u[4] / 10.0,                       // alive, wounds left
            u[5], u[6], u[7],                               // shaken, fatigued, activated
            0.0, 0.0,                                       // is_objective, its ownership
            u[8] / 30.0, u[9] / 20.0,                       // longest range, attacks
            u[10] / 6.0, u[11] / 6.0,                       // quality, defense
            u[12] / 5.0, u[13] / 5.0,                       // shoot EV, melee EV
            u[14], u[15], u[16], u[17], u[18], u[19],       // the six flag rules
        ]);
        row.resize(self.canon_width(), 0.0);
        // The GAME-STATE row (type 4) takes this branch too and carries 0 pairs,
        // exactly as the GDScript's `int(u[20])` reads it.
        for k in 0..u[20] as usize {
            if let Some(&di) = self.slots.get(&(u[21 + 2 * k] as i64)) {
                row[22 + 2 * di] = 1.0;
                row[22 + 2 * di + 1] = u[22 + 2 * k] / 6.0;
            }
        }
        row
    }

    /// `AiMissionEval._encoder_forward` ai_mission_eval.gd:258-294 — three pooled
    /// means (mine / theirs / objectives), their counts, the 30 standardised
    /// features, one relu head, sigmoid out.
    ///
    /// The pool width is `unit_b1.len()`, which is what the GDScript reads
    /// (:260); `gate` proves the second unit layer is that wide.
    pub fn forward(&self, rows: &[Vec<f64>], side: i64, xs: &[f64]) -> f64 {
        let h = self.unit_b1.len();
        let mut pools = vec![vec![0.0f64; h]; 3];
        let mut counts = [0.0f64; 3];
        for u in rows {
            let crow = self.canon(u, side);
            let emb = lin_relu(
                &lin_relu(&crow, &self.unit_w1, &self.unit_b1),
                &self.unit_w2,
                &self.unit_b2,
            );
            let pi = if crow[8] > 0.5 {
                2
            } else if crow[0] > 0.5 {
                0
            } else {
                1
            };
            counts[pi] += 1.0;
            for j in 0..h {
                pools[pi][j] += emb[j];
            }
        }
        let mut parts = Vec::with_capacity(3 * h + 3 + xs.len());
        for pi in 0..3 {
            let cdiv = counts[pi].max(1.0);
            parts.extend(pools[pi].iter().map(|v| v / cdiv));
        }
        parts.extend(counts.iter().map(|c| c / 10.0));
        parts.extend_from_slice(xs);
        let a = lin_relu(&parts, &self.head_w1, &self.head_b1);
        let mut z = self.head_b2;
        for (j, wj) in self.head_w2.iter().enumerate() {
            z += wj * a[j];
        }
        1.0 / (1.0 + (-z.clamp(-30.0, 30.0)).exp())
    }
}

/// A loaded net plus everything scoring a STATE with it needs: the blend share
/// and the row encoder.
///
/// The encoder is behind a `RefCell` because `board_rows` collects unknown rule
/// names and the whole search reaches the eval through `&self`. It reads THIS
/// build's rule vocabulary, which is the only one the table ever reads live —
/// a net whose `slots` were built against another is refused at load, not
/// replayed against.
pub struct Fitted {
    pub net: Net,
    /// `AiMissionEval.fit_blend()` ai_mission_eval.gd:337-342.
    pub blend: f64,
    /// NML-1158a — which combination `score_with` runs; `Blend` unless the
    /// loader was told otherwise (`Core.load_net(mode=)`).
    pub mode: FitMode,
    /// RED-PROOF seam, 1.0 in every shipping call: the net's own answer times
    /// this, BEFORE the blend. A gate that could not tell this apart from 1.0
    /// would not be reading the net.
    pub scale: f64,
    enc: RefCell<RowEncoder>,
}

impl Fitted {
    pub fn new(net: Net, repo_root: &str) -> Result<Fitted, String> {
        let enc = RowEncoder::for_version(repo_root, RULE_VOCAB_VERSION);
        if !enc.vocab.loaded {
            return Err(enc.vocab.error.clone().unwrap_or_else(|| {
                format!("rule vocab unreadable at {repo_root}/{}", rows::RULE_VOCAB_PATH)
            }));
        }
        Ok(Fitted {
            net,
            blend: FIT_BLEND_DEFAULT,
            mode: FitMode::Blend,
            scale: 1.0,
            enc: RefCell::new(enc),
        })
    }

    /// `RowEncoder::source_qd` — LEGACY REPLAY ONLY. A state rebuilt from a plain
    /// corpus (`tools/node_recheck.gd`'s stand-in `GameUnit`s, which every Godot
    /// replay tool uses) carries no `source_data`, so the table's own columns
    /// 10/11 read the blank `OPRApiClient.OPRUnit` 4/4 there. A gate that holds
    /// this port against such a replay must tell it so; nothing that plays a
    /// fresh game may.
    pub fn set_source_qd(&self, qd: Option<(i64, i64)>) {
        self.enc.borrow_mut().source_qd = qd;
    }

    /// `RowEncoder::unknown` — the rule names THIS encoder could not slot. It
    /// is a second collector beside `Core.rows`'s, and a game played with a net
    /// may run only this one (the other fills from `board_rows`, which a game
    /// calls only for its sidecars), so a caller reporting unknown rules must
    /// merge both or it reports an empty list for a roster that had them.
    pub fn unknown(&self) -> Vec<String> {
        self.enc.borrow().unknown.iter().cloned().collect()
    }

    /// `AiMissionEval._score_fit` ai_mission_eval.gd:428-443 on its ENCODER
    /// branch. A FINISHED round is scored as the NEXT round's fresh start —
    /// that is the distribution the fit was trained on, and rollout leaves are
    /// exactly round ends.
    pub fn score_fit(
        &self,
        state: &State,
        statics: &[UnitStatic],
        player: i64,
        incoming: Incoming,
    ) -> f64 {
        let view = next_round_view(state);
        let v = view.as_ref().unwrap_or(state);
        let f = rows::features(v, statics, player, incoming, false, rows::NO_RESERVES);
        let xs = self.net.xs_of(&f);
        let raw: Vec<Vec<f64>> = self
            .enc
            .borrow_mut()
            .board_rows(v, statics)
            .iter()
            .map(|r| r.iter().map(|c| c.as_f64()).collect())
            .collect();
        self.scale * self.net.forward(&raw, player, &xs)
    }
}

/// `_score_fit`'s first four lines (:429-433) — `None` when the state is scored
/// as it stands, `Some(view)` when a spent round is rolled forward.
fn next_round_view(state: &State) -> Option<State> {
    if state.round >= state.rounds_total {
        return None;
    }
    if (0..state.units()).any(|i| state.alive[i] > 0 && !state.activated[i]) {
        return None;
    }
    let mut v = state.clone();
    v.round += 1;
    v.activated.iter_mut().for_each(|a| *a = false);
    Some(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A net small enough to compute by hand: one hidden unit that fires on the
    /// canonical MINE flag alone and doubles, a head that passes the mine-pool
    /// through untouched, one feature key.
    fn tiny(slots: HashMap<i64, usize>) -> Net {
        let w = 22 + 2 * slots.len();
        let mut unit_w1 = vec![vec![0.0]; w];
        unit_w1[0][0] = 1.0;
        let mut head_w1 = vec![vec![0.0]; 3 + 3 + 1];
        head_w1[0][0] = 1.0;
        Net {
            keys: vec!["round_frac".into()],
            mu: vec![0.0],
            sd: vec![1.0],
            slots,
            unit_w1,
            unit_b1: vec![0.0],
            unit_w2: vec![vec![2.0]],
            unit_b2: vec![0.0],
            head_w1,
            head_b1: vec![0.0],
            head_w2: vec![1.0],
            head_b2: 0.0,
            vocab_version: None,
            selftest: None,
        }
    }

    /// One unit row and one objective row, both 21 columns wide — the shape
    /// `rows::board_rows` writes.
    fn two_rows() -> Vec<Vec<f64>> {
        let mut unit = vec![0.0; 21];
        unit[0] = 1.0; // player 1
        let mut obj = vec![0.0; 21];
        obj[0] = 3.0; // the objective marker type
        vec![unit, obj]
    }

    #[test]
    fn the_forward_matches_a_hand_computed_score() {
        let net = tiny(HashMap::new());
        // mine pool = relu(relu(1*1)*2) = 2, theirs pool = 0, objective pool = 0;
        // counts 1/0/1 -> parts [2, 0, 0, .1, 0, .1, xs0]; the head reads parts[0]
        // alone, so z = 2 and the sigmoid is 1/(1+e^-2).
        let got = net.forward(&two_rows(), 1, &[0.0]);
        assert!((got - 0.880_797_077_977_882_3).abs() < 1e-12, "{got}");
        // From player 2's seat the same unit is THEIRS: pool 1 carries it, the
        // head never reads pool 1, and z falls to 0.
        let flipped = net.forward(&two_rows(), 2, &[0.0]);
        assert!((flipped - 0.5).abs() < 1e-12, "{flipped}");
    }

    #[test]
    fn a_rule_pair_lands_on_its_own_dense_column() {
        let net = tiny(HashMap::from([(200, 0), (201, 1)]));
        let mut u = vec![0.0; 21];
        u[0] = 1.0;
        u[20] = 1.0; // one pair follows
        u.push(201.0); // slot
        u.push(3.0); // rating
        let row = net.canon(&u, 1);
        assert_eq!(row.len(), 26);
        assert_eq!(&row[22..26], &[0.0, 0.0, 1.0, 0.5]);
        // A slot the net was never trained on is DROPPED, not misfiled.
        let mut v = u.clone();
        v[21] = 999.0;
        assert_eq!(&net.canon(&v, 1)[22..26], &[0.0; 4]);
    }

    #[test]
    fn the_selftest_gate_refuses_a_drifted_net() {
        let mut net = tiny(HashMap::new());
        net.selftest = Some(SelfTest {
            board: two_rows(),
            side: 1,
            features: vec![0.0],
            expected: 0.880_797_077_977_882_3,
        });
        assert!(net.gate().is_ok());
        // RED: the same net claiming a different answer must not load.
        net.selftest.as_mut().unwrap().expected = 0.5;
        assert!(net.gate().unwrap_err().contains("selftest"));
        // RED: no block at all is a refusal too, never a pass.
        net.selftest = None;
        assert!(net.gate().unwrap_err().contains("missing"));
    }

    #[test]
    fn a_weight_key_may_be_a_ratio_or_a_product() {
        let mut f = vec![0.0; FEATURE_KEYS.len()];
        f[1] = 6.0; // my_wounds
        f[3] = 3.0; // my_units
        assert_eq!(feature_value(&f, "my_wounds"), 6.0);
        assert_eq!(feature_value(&f, "my_wounds/my_units"), 2.0);
        assert_eq!(feature_value(&f, "my_wounds*my_units"), 18.0);
        // The denominator floors at 1, and an unknown name reads 0.
        assert_eq!(feature_value(&f, "my_wounds/their_units"), 6.0);
        assert_eq!(feature_value(&f, "no_such_feature"), 0.0);
    }
}
