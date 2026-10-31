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

/// LEGACY REPLAY ONLY — a repo root whose `assets/solo/spells_mechanics_{gf,aof}.json` are the frozen rules 3.5
/// copies in `fixtures/spells_v35/`, every other entry a symlink into the real repo.
///
/// The in-repo act fixtures carry GD-recorded expectations (EV, scored lists) made with the 3.5 spell lists. Rules
/// 3.6 re-exported those two maps (DAT-13b), so a replay that reads them measures the data change, not the search
/// loop the fixtures pin. The replay tests hand THIS root to `build_act_statics` / `Registries`; the game and the
/// loader never see it (no env lookup, no loader argument). Phase R re-records the fixtures on 3.6 data and drops
/// this pin.
#[cfg(unix)]
pub fn pinned_spells_root(repo: &str) -> String {
    static ROOT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    ROOT.get_or_init(|| build_pinned_spells_root(repo)).clone()
}

#[cfg(unix)]
fn build_pinned_spells_root(repo: &str) -> String {
    use std::os::unix::fs::symlink;
    use std::path::Path;
    let repo = Path::new(repo).canonicalize().expect("repo root");
    let root = std::env::temp_dir().join(format!("nml_pinned_spells_root_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("assets/solo")).expect("pinned root");
    for e in std::fs::read_dir(&repo).expect("repo entries") {
        let e = e.expect("entry");
        if e.file_name() != "assets" {
            symlink(e.path(), root.join(e.file_name())).expect("link");
        }
    }
    for e in std::fs::read_dir(repo.join("assets")).expect("assets entries") {
        let e = e.expect("entry");
        if e.file_name() != "solo" {
            symlink(e.path(), root.join("assets").join(e.file_name())).expect("link");
        }
    }
    let frozen = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/spells_v35");
    for e in std::fs::read_dir(repo.join("assets/solo")).expect("solo entries") {
        let e = e.expect("entry");
        let name = e.file_name();
        let target = root.join("assets/solo").join(&name);
        let pinned = frozen.join(&name);
        if pinned.is_file() {
            std::fs::copy(&pinned, &target).expect("copy frozen map");
        } else {
            symlink(e.path(), target).expect("link");
        }
    }
    root.to_string_lossy().into_owned()
}
