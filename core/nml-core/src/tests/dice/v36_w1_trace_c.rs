//! Rules 3.6 row W1.TRACE-c tests (one trace key each for Thrust in Melee and
//! Counter in Melee); owned by row W1.TRACE-c.
//!
//! `trace_rule` writes its line to stderr only while `NML_TRACE_RULES=1`, so
//! each assertion runs the fixture in a CHILD copy of this test binary with
//! that switch set and reads the child's stderr. The child case is selected by
//! `NML_TRACE_CASE`; a normal suite run of `trace_child` (no such variable)
//! just returns.

use super::*;

const E72: u32 = crate::acts::EPOCH_72_PLAYTEST_RULES;
const E73: u32 = crate::acts::EPOCH_73_V36;

/// Run one fixture in a child process and return its stderr.
fn run_child(case: &str, epoch: u32) -> String {
    let exe = std::env::current_exe().expect("test binary path");
    let out = std::process::Command::new(exe)
        .arg("--exact")
        .arg("dice::tests::v36_w1_trace_c::trace_child")
        .arg("--nocapture")
        .env("NML_TRACE_RULES", "1")
        .env("NML_TRACE_CASE", case)
        .env("NML_TRACE_EPOCH", epoch.to_string())
        .output()
        .expect("spawn the trace child");
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    assert!(
        out.status.success(),
        "trace child '{case}' failed: {stderr}"
    );
    stderr
}

fn arm_count(stderr: &str, arm: &str) -> usize {
    stderr.matches(&format!("[{arm}]")).count()
}

fn assert_one_arm(case: &str, epoch: u32, arm: &str) {
    let stderr = run_child(case, epoch);
    assert_eq!(
        arm_count(&stderr, arm), 1,
        "epoch {epoch}: expected exactly one trace arm [{arm}], got:\n{stderr}"
    );
}

fn assert_no_arm(case: &str, epoch: u32, arm: &str) {
    let stderr = run_child(case, epoch);
    assert_eq!(
        arm_count(&stderr, arm), 0,
        "epoch {epoch}: the trace arm [{arm}] must not fire, got:\n{stderr}"
    );
}

// ---------------------------------------------------------------- fixtures --

fn thrust_case(epoch: u32) {
    let mut p = blade(1);
    p.thrust = true;
    let att = Ctx { quality: 4, models: 1, rules_epoch: epoch, ..Default::default() };
    let mut tray = Tray::seeded(11);
    let out = resolve_melee_leg(
        &[striker(&[p], &[0], &[1], &att)], &defender(4, 1), "Foe",
        true, true, true, false, 0.0, false, false, true, true, true, &mut tray,
    );
    assert!(out.rolls.iter().any(|r| r.kind == "attack"), "the charge strikes: {:?}", out.rolls);
}

fn counter_case(epoch: u32) {
    let att = Ctx { impact: 2, models: 2, rules_epoch: epoch, ..Default::default() };
    let def = Ctx {
        counter_models: 1,
        counter_impact_per_model: Some(1),
        ..defender(4, 2)
    };
    let pools = impact_pools(&att, &def);
    assert_eq!(pools[0], (3, 0), "Counter takes one die off the plain pool");
    assert_eq!(pools[1], (0, HEAVY_IMPACT_AP), "no heavy dice to strip");
}

#[test]
fn trace_child() {
    let Ok(case) = std::env::var("NML_TRACE_CASE") else { return };
    let epoch = std::env::var("NML_TRACE_EPOCH")
        .ok()
        .and_then(|e| e.parse().ok())
        .unwrap_or(E73);
    match case.as_str() {
        "thrust" => thrust_case(epoch),
        "counter" => counter_case(epoch),
        other => panic!("unknown trace case {other}"),
    }
}

// ---------------------------------------------------------------- RED tests --

#[test]
fn thrust_in_melee_emits_one_arm_at_73() {
    assert_one_arm("thrust", E73, "thrust-in-melee");
}

#[test]
fn counter_in_melee_emits_one_arm_at_73() {
    assert_one_arm("counter", E73, "counter-in-melee");
}

#[test]
fn the_thrust_arm_is_absent_at_72() {
    assert_no_arm("thrust", E72, "thrust-in-melee");
}

#[test]
fn the_counter_arm_is_absent_at_72() {
    assert_no_arm("counter", E72, "counter-in-melee");
}
