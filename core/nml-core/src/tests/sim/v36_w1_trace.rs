//! Rules 3.6 row W1.TRACE tests (one trace key per primitive that has none); owned by row W1.TRACE.
//!
//! `trace_rule` writes its line to stderr only while `NML_TRACE_RULES=1`, so
//! each assertion runs the fixture in a CHILD copy of this test binary with
//! that switch set and reads the child's stderr. The child case is selected by
//! `NML_TRACE_CASE`; a normal suite run of `trace_child` (no such variable)
//! just returns.

use super::*;

const E72: u32 = crate::acts::EPOCH_72_PLAYTEST_RULES;
const E73: u32 = crate::acts::EPOCH_73_V36;

fn rec(hit_mod: i64, rule: &str) -> crate::mods::LiveMod {
    crate::mods::LiveMod {
        hit_mod,
        casting_mod: 0,
        morale_mod: 0,
        ap_mod: 0,
        def_mod: 0,
        defense_mod: 0,
        move_mod: 0,
        grants_rule: Rc::from(rule),
        scope: Rc::from(""),
        attackers: false,
        once: true,
        name: Rc::from(rule),
    }
}

/// Run one fixture in a child process and return its stderr.
fn run_child(case: &str, epoch: u32) -> String {
    let exe = std::env::current_exe().expect("test binary path");
    let out = std::process::Command::new(exe)
        .arg("--exact")
        .arg("sim::tests::v36_w1_trace::trace_child")
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

fn assert_arm(case: &str, epoch: u32, arm: &str) {
    let stderr = run_child(case, epoch);
    assert!(
        stderr.contains(&format!("[{arm}]")),
        "epoch {epoch}: expected the trace arm [{arm}], got:\n{stderr}"
    );
}

fn assert_no_arm(case: &str, epoch: u32, arm: &str) {
    let stderr = run_child(case, epoch);
    assert!(
        !stderr.contains(&format!("[{arm}]")),
        "epoch {epoch}: the trace arm [{arm}] must not fire, got:\n{stderr}"
    );
}

// ---------------------------------------------------------------- fixtures --

fn utility_case(epoch: u32) {
    let mut st = four_unit_line();
    st.buffs[1].push(rec(1, "Precision Attacks Buff"));
    let statics = vec![UnitStatic::default(); 4];
    let c = ctx_live(statics[0].ctx, &statics, &st, 1, false, epoch);
    assert_eq!(c.hit_mod, 1);
}

fn regen_case(epoch: u32) {
    let mut st = four_unit_line();
    st.buffs[0].push(rec(0, "Enhanced Self-Repair"));
    let statics = vec![UnitStatic::default(); 4];
    let c = ctx_live(statics[0].ctx, &statics, &st, 0, false, epoch);
    assert!(c.regeneration);
}

fn fortified_case(epoch: u32) {
    let mut st = four_unit_line();
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, None]);
    st.alive = vec![1, 0, 0, 0];
    let mut profile = st.profiles.list[0].clone();
    profile.special_rules = vec!["Fortified".into()];
    st.profiles = Rc::new(Profiles { list: vec![profile], index: HashMap::new() });
    let mut statics = vec![UnitStatic::default(); 4];
    statics[0].ctx.fortified = true;
    let c = ctx_live(statics[0].ctx, &statics, &st, 0, false, epoch);
    assert!(c.fortified);
}

fn hit_and_run_case(epoch: u32) {
    let (st, mut statics) = vr_charge_line(2.0);
    statics[0].hit_and_run_active = true;
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    let (next, _) = resolve_stochastic_tray_on_board(
        &statics,
        &st,
        &vr_charge(),
        &small_board(),
        Seams { movement: true, rules_epoch: epoch, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .expect("the charge resolves");
    assert_eq!(next.hit_and_run_round[0], next.round);
}

fn bounding_case(epoch: u32) {
    let (st, mut statics) = dangerous_line();
    statics[0].bounding_place = Some(crate::unit::PlaceSpec {
        name: "Bounding".into(),
        dice: 1,
        plus: 1.0,
    });
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        &statics,
        &st,
        &advance_to(20.0),
        &small_board(),
        Seams { rules_epoch: epoch, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .expect("the activation resolves");
}

fn versatile_case(epoch: u32) {
    let (st, mut statics) = vr_charge_line(10.0);
    statics[0].melee[0].versatile_attack = true;
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        &statics,
        &st,
        &vr_charge(),
        &small_board(),
        Seams { movement: true, rules_epoch: epoch, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .expect("the charge resolves");
}

#[test]
fn trace_child() {
    let Ok(case) = std::env::var("NML_TRACE_CASE") else { return };
    let epoch = std::env::var("NML_TRACE_EPOCH")
        .ok()
        .and_then(|e| e.parse().ok())
        .unwrap_or(E73);
    match case.as_str() {
        "utility" => utility_case(epoch),
        "regen" => regen_case(epoch),
        "fortified" => fortified_case(epoch),
        "hit-and-run" => hit_and_run_case(epoch),
        "bounding" => bounding_case(epoch),
        "versatile" => versatile_case(epoch),
        other => panic!("unknown trace case {other}"),
    }
}

// ---------------------------------------------------------------- RED tests --

#[test]
fn utility_grant_live_emits_one_arm_at_73() {
    assert_arm("utility", E73, "utility-grant-live");
}

#[test]
fn regen_boost_live_emits_one_arm_at_73() {
    assert_arm("regen", E73, "regen-boost-live");
}

#[test]
fn fortified_grant_live_emits_one_arm_at_73() {
    assert_arm("fortified", E73, "fortified-grant-live");
}

#[test]
fn hit_and_run_emits_one_arm_at_73() {
    assert_arm("hit-and-run", E73, "hit-and-run");
}

#[test]
fn bounding_emits_one_arm_at_73() {
    assert_arm("bounding", E73, "bounding");
}

#[test]
fn versatile_attack_emits_one_arm_at_73() {
    assert_arm("versatile", E73, "versatile-attack");
}

#[test]
fn the_utility_arm_is_absent_at_72() {
    assert_no_arm("utility", E72, "utility-grant-live");
}
