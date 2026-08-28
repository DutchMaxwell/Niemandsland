//! Shared helper for the tests that replay an IN-REPO act fixture.

use std::sync::atomic::Ordering;

/// LEGACY REPLAY ONLY — pin `nml_core::unit::LEGACY_NO_COND_AP` for this test
/// binary, so `profile_ev` prices Shatter / Tear / Disintegrate / Melee Slayer /
/// Piercing Assault / Piercing Hunter at their PRINTED AP the way the
/// pre-NML-1103 `BattleSim` did.
///
/// The in-repo fixtures (`acts_25.jsonl`, `acts_arb.jsonl`) were cut before
/// `AiEv.stamp_conditional_ap` reached the sim path, so their recorded search
/// valued those weapons at AP(0) while the TABLE resolved them with the bonus
/// (`main.gd:6319`). Replaying them against the fixed EV measures the fix, not
/// the search loop the fixtures were cut to pin.
///
/// NEITHER READING IS GAME-TRUE FOREVER. Re-recording them is its own job —
/// **ticket NML-1125** — because today's `planner_v0` also carries #420's
/// `hero_fold` and runs past the 25-act cap, which moves the corpus SHAPE as
/// well as its picks. Never set this to make a NEW recording agree with an old
/// one.
///
/// Called from each fixture LOADER, so it is pinned before `UnitStatic::build`
/// runs the stamp, for every test in the binary that touches the corpus.
pub fn pin_legacy_no_cond_ap() {
    nml_core::unit::LEGACY_NO_COND_AP.store(true, Ordering::Relaxed);
}
