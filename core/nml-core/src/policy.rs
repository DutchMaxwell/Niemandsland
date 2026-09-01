//! NML-1158b step 4a — the POLICY net LOADER: `policy_net/1` JSON, the
//! `netlab/policy_train.py` export, gated the `fitted.rs` way (fitted.rs:51-105):
//! an unknown schema is refused, the layer shapes must agree, and the shipped
//! selftest row is RECOMPUTED — a drifted forward never ranks a menu. The
//! forward is `z = w2·relu(w1[phi; vec] + b1) + b2` per candidate (ONE hidden
//! layer, weights `[in][out]`, the fitted.rs/clone_train convention). The
//! per-candidate feature builder and `score_menu` land in step 4b, same file.

use serde::Deserialize;

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

#[cfg(test)]
mod tests {
    use super::*;

    fn net_path() -> String {
        std::env::var("NML_POLICY_NET").unwrap_or_else(|_| {
            format!("{}/netlab/nets/policy_v1.json", std::env::var("HOME").unwrap_or_default())
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
