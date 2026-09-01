//! NML-1073 M1-5 — the GDExtension seam.
//!
//! Wraps the pure-Rust rollout node (`nml-core`) as the Godot `RefCounted` class
//! `NmlCore`. Nothing here re-implements a rule: the crate below owns the port,
//! this file owns the marshalling and a handle slab.
//!
//! CONTRACT
//! - `capture_plain(plain)` takes exactly what `BattleSim.state_to_plain(state)`
//!   produces (battle_sim.gd:1255, `with_profile = true`) and returns a handle.
//! - `clone(h)` / `resolve(h, action)` return NEW handles; the source is
//!   untouched, the way `BattleSim.clone_state`/`resolve` leave their input.
//! - `score(h, player, rich)` prices the state; `rich` computes the reply threat
//!   in Rust first (`AiPlanner._policy_step` ai_planner.gd:508-510).
//! - `release(h)` frees a slot; `plain_of(h)` hands the state back in the same
//!   plain form for parity checks.
//! - Handle 0 is never valid. A failed call returns 0 and leaves the reason in
//!   `last_error()`.
//!
//! PLAYER SAFETY (rules of record R1/R2): this library is OPTIONAL. Godot loads
//! it if `core/nml_core.gdextension` (installed from the tracked
//! `core/nml_core.gdextension.in` by `core/install_gdextension.sh`, only when
//! this .so exists) finds it; if it does not, the class simply does not exist
//! and `BattleSim.core_enabled()` is false — the GDScript path runs unchanged. Nothing in the game calls this class unless NML_CORE=1.

use std::rc::Rc;

use godot::prelude::*;

use nml_core::state::{ProfileCache, Profiles, Roster};
use nml_core::terrain::Terrain;
use nml_core::unit::{StaticsCache, UnitStatic};
use nml_core::{
    plan_with_rollout_sig, reply_threat, resolve, score, ActStatics, Action, Knobs, Pick,
    Registries, Seams,
};

mod mvcall;
mod plain;

use plain::Captured;

struct NmlCoreExtension;

#[gdextension]
unsafe impl ExtensionLibrary for NmlCoreExtension {}

/// One live state: the port's `State` plus what `plain_of` needs to write it
/// back in the shape it came in.
struct Slot {
    cap: Captured,
    statics: Rc<Vec<UnitStatic>>,
}

/// The interned per-game closure. Every node of one game carries the same unit
/// keys and the same static profiles, so the profile table, the roster and the
/// derived `UnitStatic` closure are built ONCE and shared by every capture —
/// the same interning `nml_core::io::roster_of` does for the JSONL corpus.
#[derive(Default)]
struct RosterCache {
    /// The unit dictionary keys in capture order. In every corpus and every live
    /// capture the key IS the unit_id, so matching on it identifies the roster.
    keys: Vec<String>,
    profiles: Option<Rc<Profiles>>,
    roster: Option<Rc<Roster>>,
    statics: Option<Rc<Vec<UnitStatic>>>,
}

/// The per-GAME closure the SEARCH needs on top of a single state — the exact
/// three objects `AiActRecorder._header_line` (act_recorder.gd:118-134) writes
/// as line 1 of the act corpus. Set ONCE per game by `set_game_header`; a state
/// whose keys are not in `profiles` is refused rather than defaulted.
struct GameHeader {
    profiles: Rc<Profiles>,
    terrain: Terrain,
    knobs: Knobs,
    /// NML-1073 M2-5b: the header table is the DEPLOYMENT reading. This turns
    /// each activation's own `prof` blocks into the table that activation is
    /// searched on — the header's own `Rc` while nothing has moved, one interned
    /// rebuild per distinct reading after that.
    pcache: ProfileCache,
    /// The roster for the last state seen, interned across activations the way
    /// `io::roster_of` interns it across corpus lines.
    keys: Vec<String>,
    roster: Option<Rc<Roster>>,
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NmlCore {
    #[allow(dead_code)]
    base: Base<RefCounted>,
    slab: Vec<Option<Slot>>,
    free: Vec<usize>,
    cache: RosterCache,
    /// The derived `UnitStatic` closure per profile TABLE — rebuilt only on the
    /// activation where the game's dynamic reading actually changed.
    scache: StaticsCache,
    reg: Option<Registries>,
    repo_root: Option<String>,
    seams: Option<Seams>,
    last_error: String,
    dropped: Vec<String>,
    header: Option<GameHeader>,
}

#[godot_api]
impl NmlCore {
    /// Where `assets/solo/rules_mechanics_<system>.json` and
    /// `spells_mechanics_<system>.json` are read from. Default: `$NML_CORE_REPO`,
    /// else `ProjectSettings.globalize_path("res://")`. Must be set before the
    /// first capture; changing it drops the profile cache.
    #[func]
    fn set_repo_root(&mut self, path: GString) {
        self.repo_root = Some(path.to_string());
        self.reg = None;
        self.cache = RosterCache::default();
    }

    /// The A/B seams `resolve` branches on — `BattleSim.spacing_enabled()` /
    /// `cast_phase_enabled()` (battle_sim.gd:25-42). Default: the same
    /// NML_SIM_SPACING / NML_SIM_CAST environment read the GDScript does.
    ///
    /// The ARITY is fixed: two GDScript callers pass exactly these two
    /// (solo_controller.gd:3103, tools/node_core_check.gd:85). The third seam
    /// (NML-1073 M4-7 `path`) therefore keeps its ENVIRONMENT reading here and
    /// gets `set_seam_path` of its own for a caller that wants to pin it.
    #[func]
    fn set_seams(&mut self, spacing: bool, cast: bool) {
        let path = self.seams_now().path;
        self.seams = Some(Seams {
            spacing,
            cast,
            path,
            hero_attach: false,
            charge_landing: false,
            sighting: false,
            movement: false,
            // D1-B8: inert without a tray — this seat resolves expected values.
            no_dangerous: false,
            // D5-4: inert — this seat never turns `hero_attach` on.
            no_engage_fold: false,
        });
    }

    /// NML-1073 M4-7 — NML_SIM_PATH: the imagined move follows a tier-2
    /// `mv::reach` route instead of a straight line. Default OFF.
    #[func]
    fn set_seam_path(&mut self, path: bool) {
        let s = self.seams_now();
        self.seams = Some(Seams { path, ..s });
    }

    #[func]
    fn seams(&mut self) -> VarDictionary {
        let s = self.seams_now();
        let mut d = VarDictionary::new();
        d.set("spacing", s.spacing);
        d.set("cast", s.cast);
        d.set("path", s.path);
        d
    }

    /// Builds a state from the plain form and returns its handle (0 = failed).
    #[func]
    fn capture_plain(&mut self, plain: VarDictionary) -> i64 {
        self.last_error.clear();
        let keys = plain::unit_keys(&plain);
        if let Err(e) = self.ensure_closure(&plain, &keys) {
            self.last_error = e;
            return 0;
        }
        let profiles = Rc::clone(self.cache.profiles.as_ref().unwrap());
        let roster = Rc::clone(self.cache.roster.as_ref().unwrap());
        let statics = Rc::clone(self.cache.statics.as_ref().unwrap());
        match plain::build_state(&plain, profiles, roster) {
            Ok(cap) => {
                for d in &cap.dropped {
                    if !self.dropped.iter().any(|x| x == d) {
                        self.dropped.push(d.clone());
                    }
                }
                self.push(Slot { cap, statics })
            }
            Err(e) => {
                self.last_error = e;
                0
            }
        }
    }

    /// `BattleSim.clone_state` battle_sim.gd:463-505 — a new handle on a deep
    /// copy; the profile table and the LOS matrix stay shared.
    #[func]
    fn clone(&mut self, h: i64) -> i64 {
        self.last_error.clear();
        let Some(i) = self.index(h) else { return 0 };
        let slot = self.slab[i].as_ref().unwrap();
        let cap = Captured {
            state: slot.cap.state.clone(),
            extras: slot.cap.extras.clone(),
            mask: slot.cap.mask.clone(),
            has_los: slot.cap.has_los,
            dropped: Vec::new(),
        };
        let statics = Rc::clone(&slot.statics);
        self.push(Slot { cap, statics })
    }

    /// `BattleSim.resolve` battle_sim.gd:570-652 on a NEW handle.
    ///
    /// The action is the planner's own dictionary (`kind`, `unit`, `dest`,
    /// `shoot`, `charge`, `patient`; `dest` may be a `Vector3` or an `[x, y, z]`
    /// array). Two OPTIONAL keys stand in for the Callables a plain state cannot
    /// carry — exactly the two the recorder writes into the node corpus:
    /// `cover_dest` (bool, the `terrain_at` answer at the destination,
    /// battle_sim.gd:596-598) and `cast_los` (a `"0101…"` row, the post-move
    /// `_los_clear` answers the cast sub-phase needs, battle_sim.gd:930).
    /// Absent `cover_dest` leaves the mover's cover flag untouched.
    #[func]
    fn resolve(&mut self, h: i64, action: VarDictionary) -> i64 {
        self.last_error.clear();
        let Some(i) = self.index(h) else { return 0 };
        let seams = self.seams_now();
        let act = action_of(&action);
        let cover = action.get("cover_dest").map(|v| plain::flag(&v));
        let cast_los: Option<Vec<bool>> = action
            .get("cast_los")
            .map(|v| plain::text(&v).chars().map(|c| c == '1').collect());
        let (statics, out, extras, mask, has_los) = {
            let slot = self.slab[i].as_ref().unwrap();
            let statics = Rc::clone(&slot.statics);
            let out = resolve(
                &statics,
                &slot.cap.state,
                &act,
                cover,
                seams,
                cast_los.as_deref(),
            );
            (
                statics,
                out,
                slot.cap.extras.clone(),
                slot.cap.mask.clone(),
                slot.cap.has_los,
            )
        };
        match out {
            Ok(state) => self.push(Slot {
                cap: Captured { state, extras, mask, has_los, dropped: Vec::new() },
                statics,
            }),
            Err(u) => {
                self.last_error = format!("{u:?}");
                0
            }
        }
    }

    /// `AiMissionEval.score(state, player[, reply_threat])` ai_mission_eval.gd:344.
    /// `rich` = the leaf that prices the reply threat first (ai_planner.gd:508-510).
    #[func]
    fn score(&mut self, h: i64, player: i64, rich: bool) -> f64 {
        self.last_error.clear();
        let Some(i) = self.index(h) else { return 0.0 };
        let slot = self.slab[i].as_ref().unwrap();
        if rich {
            let inc = reply_threat(&slot.statics, &slot.cap.state, player);
            score(&slot.cap.state, player, &inc)
        } else {
            score(&slot.cap.state, player, nml_core::NO_INCOMING)
        }
    }

    /// NML-1073 M2-5 — the SEARCH seam, half one: the per-GAME closure.
    ///
    /// `header` is exactly the dictionary `AiActRecorder._header_line`
    /// (act_recorder.gd:118-134) writes as line 1 of `acts.jsonl`:
    /// `{"profiles": {unit_key: profile}, "terrain": {...}|null, "knobs": {...}}`.
    /// Call it ONCE per game, before the first `plan_with_rollout`. Returns
    /// false and leaves the reason in `last_error()` when the table is unusable.
    #[func]
    fn set_game_header(&mut self, header: VarDictionary) -> bool {
        self.last_error.clear();
        let profiles = plain::profiles_of_header(&plain::sub_dict(&header, "profiles"));
        if profiles.list.is_empty() {
            self.last_error = "game header carries no \"profiles\"".to_string();
            return false;
        }
        let terrain = match header.get("terrain").and_then(|v| v.try_to::<VarDictionary>().ok()) {
            Some(t) => Terrain::build(&plain::terrain_of(&t)),
            None => Terrain::absent(),
        };
        let knobs = plain::knobs_of(&plain::sub_dict(&header, "knobs"));
        let root = self.root();
        if self.reg.is_none() {
            self.reg = Some(Registries::new(&root));
        }
        let profiles = Rc::new(profiles);
        // The closure for the header's own reading is built here rather than on
        // the first activation, so a broken registry path is a `set_game_header`
        // failure and not a mid-game decline.
        let reg = self.reg.as_mut().unwrap();
        let _ = self.scache.get(reg, &profiles);
        self.header = Some(GameHeader {
            pcache: ProfileCache::new(Rc::clone(&profiles)),
            profiles,
            terrain,
            knobs,
            keys: Vec::new(),
            roster: None,
        });
        true
    }

    /// NML-1073 M2-5 — the SEARCH seam, half two: ONE activation.
    ///
    /// `AiPlanner.plan_with_rollout(state, player)` (ai_planner.gd:118-275) over
    /// the plain state `BattleSim.state_to_plain(state, false)` writes, with the
    /// per-activation class statics (`AiActRecorder.begin`, act_recorder.gd:62-63)
    /// and `AiPlanner._playout_sig(state, player)` (:1345-1347) handed in rather
    /// than guessed.
    ///
    /// Answers either the pick — the SAME dictionary the GDScript returns, minus
    /// `intent` (a battle-log label the caller composes from the live GameUnits),
    /// plus `leaf_state` (the winning rollout's horizon end, plain) and the
    /// search trace — or `{"used": false, "unsupported": "<reason>"}` when the
    /// port declines. It never crashes the game: a panic inside the port is
    /// caught and answered as a decline like any other.
    #[func]
    fn plan_with_rollout(
        &mut self,
        state_plain: VarDictionary,
        player: i64,
        statics: VarDictionary,
        sig: i64,
    ) -> VarDictionary {
        self.last_error.clear();
        let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.plan_inner(&state_plain, player, &statics, sig)
        }));
        let out = match caught {
            Ok(r) => r,
            Err(_) => Err("panic inside the port".to_string()),
        };
        match out {
            Ok(d) => d,
            Err(e) => {
                self.last_error = e.clone();
                let mut d = VarDictionary::new();
                d.set("used", false);
                d.set("unsupported", &GString::from(e.as_str()));
                d
            }
        }
    }

    /// NML-1073 M2-5 diagnostic: what the port actually PARSED out of the game
    /// header, as counts. The GDScript prints the same counts off the dictionary
    /// it sent, so a marshalling gap (a typed Godot array read as empty, a
    /// missing terrain) shows up as a number instead of as a wrong rollout.
    #[func]
    fn header_digest(&mut self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(h) = self.header.as_ref() else {
            d.set("header", false);
            return d;
        };
        d.set("header", true);
        d.set("profiles", h.profiles.list.len() as i64);
        d.set("terrain_valid", h.terrain.is_valid());
        let mut rules = 0i64;
        let mut weapons = 0i64;
        let mut wrules = 0i64;
        let mut grants = 0i64;
        let mut heroes = 0i64;
        let mut wmax = 0i64;
        let mut bands = 0.0f64;
        for p in &h.profiles.list {
            rules += p.special_rules.len() as i64;
            weapons += p.weapons.len() as i64;
            for w in &p.weapons {
                wrules += w.rules.len() as i64;
            }
            grants += p.item_grants.len() as i64;
            heroes += p.attached_hero_rules.iter().map(|r| r.len() as i64).sum::<i64>();
            wmax += p.wounds_max.iter().sum::<i64>();
            bands += p.move_bands.advance + p.move_bands.rush;
        }
        d.set("special_rules", rules);
        d.set("weapons", weapons);
        d.set("weapon_rules", wrules);
        d.set("item_grants", grants);
        d.set("hero_rules", heroes);
        d.set("wounds_max_sum", wmax);
        d.set("move_bands_sum", bands);
        d.set("top_k", h.knobs.top_k);
        d.set("horizon", h.knobs.horizon);
        d.set("seam_spacing", h.knobs.seam_spacing);
        d.set("seam_path", h.knobs.seam_path);
        d.set("statics_builds", self.scache.builds as i64);
        d
    }

    /// NML-1073 M2-5b — how often the port had to REBUILD the per-unit static
    /// closure because an activation's dynamic profile reading differed from the
    /// last one (a hero fell, a spell granted or expired a rule). 1 = the game
    /// header's own build and nothing has moved since.
    #[func]
    fn statics_builds(&self) -> i64 {
        self.scache.builds as i64
    }

    /// NML-1073 M4-6a — the MOVE seam: ONE `MovementPlanner.plan_unit_step`
    /// call (movement_planner.gd:496).
    ///
    /// `call` is the very dictionary `MoveRecorder.begin` receives
    /// (solo_controller.gd:6065) — the caller hands the SAME object to both, so
    /// the corpus a gate replays and the call the game makes are one thing. It
    /// is marshalled into the recorder's own JSON line and read back through
    /// `io::read_moves`, the corpus gate's reader, before the port sees it.
    ///
    /// `fast_planner` / `fast_planner_guard` are `MovementPlanner`'s two class
    /// statics (movement_planner.gd:54-61). They are per-GAME — the recorder
    /// writes them into the corpus HEADER, not into a call line — so they come
    /// in beside the call instead of being guessed. `fast_planner` is NOT always
    /// true in the interactive game (main.gd:2276).
    ///
    /// Answers `{"ok": true, "planned": [Vector2, …], "trails": [[Vector2, …],
    /// …], "flow_order": [int, …]}` or `{"ok": false, "error": "…"}`. A panic
    /// inside the port is caught and answered as a decline like any other — the
    /// seam never takes the game down (rule R1).
    #[func]
    fn plan_unit_step(
        &mut self,
        call: VarDictionary,
        fast_planner: bool,
        fast_planner_guard: i64,
    ) -> VarDictionary {
        self.last_error.clear();
        let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let line = mvcall::call_line(&call);
            let mc = nml_core::mv::entry::read_call_line(&line)?;
            nml_core::mv::entry::plan_unit_step_call(&mc, fast_planner, fast_planner_guard)
        }));
        let out = match caught {
            Ok(r) => r,
            Err(_) => Err("panic inside the port".to_string()),
        };
        match out {
            Ok(p) => mvcall::planned_out(&p),
            Err(e) => {
                self.last_error = e.clone();
                let mut d = VarDictionary::new();
                d.set("ok", false);
                d.set("error", &GString::from(e.as_str()));
                d
            }
        }
    }

    /// NML-1140 step 10a — the doctrine's placement choice for the table: the
    /// SAME dispatcher the twin's `nml_core.doctrine_place` runs (pyo3 seam,
    /// nml-core-py lib.rs:1665-1706) — one implementation, two seams (design 0;
    /// gate 2(ii) asserts the markers across both). Inputs are the pyo3 seam's,
    /// in its order: `terrain` (Dictionary or null -> `Terrain::absent`),
    /// `mode` ("style"|"search"), `armies` = the PAIR `[army_a, army_b]` of
    /// profile dictionaries (unit key -> the `_unit_profile` block), the
    /// ALREADY drawn marker `count` (the seed stream stays the caller's — the
    /// doctrine draws nothing, design 1), the zones object `style` (e.g.
    /// `{"zones": {"1": …, "2": …}}`), and the table dims in inches (72x48,
    /// pyo3's defaults — GDScript passes them explicitly). `armies` and
    /// `style` must be UNTYPED `Array`/`Dictionary` — gdext refuses a typed
    /// `Array[Dictionary]` or `Dictionary[K, V]` at the boundary (plain.rs:125),
    /// so the caller passes plain literals. Answers
    /// `{"mode", "positions": [[x, z] inches, …], "swept"}`; an EMPTY
    /// dictionary with the reason in `last_error()` otherwise — including a
    /// `count` outside 0..=5, refused FIRST like the pyo3 seam (8^count search
    /// blow-up, d3+2 tops out at 5; the step-5 UNSURE, coordinator-approved),
    /// and "random"/unknown mode words, which `doctrine::place` turns into an
    /// Err — never a silent fallback. A panic inside the port is caught like
    /// on every other seam (rule R1).
    #[func]
    fn doctrine_place(
        &mut self,
        terrain: Variant,
        mode: GString,
        armies: VarArray,
        count: i64,
        style: VarDictionary,
        table_w_in: f64,
        table_d_in: f64,
    ) -> VarDictionary {
        self.last_error.clear();
        let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.doctrine_place_inner(&terrain, &mode, &armies, count, &style, table_w_in, table_d_in)
        }));
        let out = match caught {
            Ok(r) => r,
            Err(_) => Err("panic inside the port".to_string()),
        };
        match out {
            Ok(d) => d,
            Err(e) => {
                self.last_error = e.clone();
                VarDictionary::new()
            }
        }
    }

    /// NML-1073 M4-6a GATE B, half one: the canonical JSON the reader produced
    /// out of a live-shaped `plan_unit_step` DICTIONARY. Empty = the call did
    /// not parse; `last_error()` says why.
    #[func]
    fn move_call_roundtrip(&mut self, call: VarDictionary) -> GString {
        self.last_error.clear();
        let line = mvcall::call_line(&call);
        match nml_core::mv::entry::read_call_line(&line) {
            Ok(mc) => GString::from(nml_core::mv::entry::canonical_input(&mc).as_str()),
            Err(e) => {
                self.last_error = e;
                GString::new()
            }
        }
    }

    /// NML-1073 M4-6a GATE B, the input side: one recorded `moves_calls.jsonl`
    /// line rebuilt as the LIVE dictionary the controller would have sent —
    /// `Vector2` positions, a `Vector2i`-keyed terrain grid, nested option
    /// dictionaries. Feeding THAT back through `plan_unit_step`'s own door is
    /// what makes the round-trip a statement about the Variant boundary rather
    /// than about Godot's JSON parser. Empty = the line did not parse.
    #[func]
    fn move_line_to_dict(&mut self, line: GString) -> VarDictionary {
        self.last_error.clear();
        match nml_core::mv::entry::read_call_line(&line.to_string()) {
            Ok(mc) => mvcall::call_dict(&mc),
            Err(e) => {
                self.last_error = e;
                VarDictionary::new()
            }
        }
    }

    /// NML-1073 M4-6a GATE B, half two: the same canonical JSON out of a
    /// RECORDED `moves_calls.jsonl` line. The two strings must be identical —
    /// that, and nothing weaker, is what "the Dictionary marshalling loses
    /// nothing" means.
    #[func]
    fn move_line_canonical(&mut self, line: GString) -> GString {
        self.last_error.clear();
        match nml_core::mv::entry::read_call_line(&line.to_string()) {
            Ok(mc) => GString::from(nml_core::mv::entry::canonical_input(&mc).as_str()),
            Err(e) => {
                self.last_error = e;
                GString::new()
            }
        }
    }

    /// Frees the slot. Releasing an already-free or unknown handle is a no-op.
    #[func]
    fn release(&mut self, h: i64) {
        if let Some(i) = self.index(h) {
            self.slab[i] = None;
            self.free.push(i);
        }
    }

    /// Every live handle at once — the rollout loop's teardown.
    #[func]
    fn release_all(&mut self) {
        for i in 0..self.slab.len() {
            if self.slab[i].is_some() {
                self.slab[i] = None;
                self.free.push(i);
            }
        }
    }

    /// The state back in the plain form, for parity checks — the shape
    /// `BattleSim.state_to_plain(state, false)` writes, key set included.
    #[func]
    fn plain_of(&mut self, h: i64) -> VarDictionary {
        self.last_error.clear();
        let Some(i) = self.index(h) else {
            return VarDictionary::new();
        };
        plain::plain_of(&self.slab[i].as_ref().unwrap().cap)
    }

    /// Why the last call returned 0 / an empty dictionary. Empty = no failure.
    #[func]
    fn last_error(&self) -> GString {
        GString::from(self.last_error.as_str())
    }

    /// Plain-form keys seen but not modelled by the port (`dormant_models`,
    /// `dormant_wounds`). Empty on every corpus recorded so far.
    #[func]
    fn dropped_keys(&self) -> PackedStringArray {
        self.dropped.iter().map(GString::from).collect()
    }

    #[func]
    fn live_handles(&self) -> i64 {
        self.slab.iter().filter(|s| s.is_some()).count() as i64
    }

    // ------------------------------------------------------------ internals --

    /// The body of `plan_with_rollout`, in `Result` form so every decline is one
    /// `?` and the public wrapper owns the marshalling of the failure.
    fn plan_inner(
        &mut self,
        plain: &VarDictionary,
        player: i64,
        statics: &VarDictionary,
        sig: i64,
    ) -> Result<VarDictionary, String> {
        // BEFORE the header borrow: `seams_now` needs `&mut self`, and the path
        // seam has to reach `plan_with_rollout` through the KNOBS, which is
        // where `plan.rs` reads its three seams from.
        let path_seam = self.seams_now().path;
        let keys = plain::unit_keys(plain);
        // NML-1073 M2-5b: the profile table THIS activation reads. The per-unit
        // `prof` blocks the seam stamps carry every field a live game rewrites
        // (a fallen hero's inherited rules above all), so the search is handed
        // the reading of the moment, not the deployment one.
        let effective = {
            let h = self
                .header
                .as_mut()
                .ok_or_else(|| "set_game_header has not been called".to_string())?;
            if h.roster.is_none() || h.keys != keys {
                let r = plain::roster_of_keys(&keys, &h.profiles)?;
                h.keys = keys;
                h.roster = Some(Rc::new(r));
            }
            let dyns = plain::dyn_profiles(plain);
            h.pcache.effective(h.roster.as_ref().unwrap(), &dyns)
        };
        let root = self.root();
        if self.reg.is_none() {
            self.reg = Some(Registries::new(&root));
        }
        let unit_statics = {
            let reg = self.reg.as_mut().unwrap();
            self.scache.get(reg, &effective)
        };
        let h = self.header.as_ref().unwrap();
        let cap = plain::build_state(
            plain,
            Rc::clone(&effective),
            Rc::clone(h.roster.as_ref().unwrap()),
        )?;
        for d in &cap.dropped {
            if !self.dropped.iter().any(|x| x == d) {
                self.dropped.push(d.clone());
            }
        }
        let act = act_statics_of(statics);
        let mut knobs = h.knobs;
        knobs.seam_path = knobs.seam_path || path_seam;
        let pick = plan_with_rollout_sig(
            &cap.state,
            &h.terrain,
            &unit_statics,
            &knobs,
            &act,
            player,
            Some(sig),
        )
        .map_err(|u| format!("{u:?}"))?;
        Ok(pick_out(&pick, &cap, sig))
    }

    /// The body of `doctrine_place` in `Result` form — the marshalling is
    /// `mvcall::flat`, the same Variant -> serde_json reader the move seam
    /// uses (mvcall.rs:33), so the doctrine sees byte-identical Values from
    /// both seams.
    fn doctrine_place_inner(
        &mut self,
        terrain: &Variant,
        mode: &GString,
        armies: &VarArray,
        count: i64,
        style: &VarDictionary,
        table_w_in: f64,
        table_d_in: f64,
    ) -> Result<VarDictionary, String> {
        if count > 5 {
            return Err(format!(
                "count must be <= 5 (d3+2 is the mission ceiling; the search tree is 8^count), got {count}"
            ));
        }
        if count < 0 {
            return Err(format!("count must be >= 0 — a drawn marker count, got {count}"));
        }
        if armies.len() != 2 {
            return Err(format!(
                "armies must be the pair [army_a, army_b] of profile dicts, got {} entries",
                armies.len()
            ));
        }
        let pair: Vec<serde_json::Value> = armies.iter_shared().map(|v| mvcall::flat(&v)).collect();
        let style_value = mvcall::flat(&style.to_variant());
        let t = if terrain.get_type() == VariantType::NIL {
            Terrain::absent()
        } else {
            match terrain.try_to::<VarDictionary>() {
                Ok(d) => Terrain::build(&plain::terrain_of(&d)),
                Err(_) => return Err("terrain must be a Dictionary or null".to_string()),
            }
        };
        let placed = nml_core::doctrine_place(
            mode.to_string().as_str(),
            &pair[0],
            &pair[1],
            &style_value,
            &nml_core::objectives::Cells::from_terrain(&t),
            count as usize,
            table_w_in,
            table_d_in,
        )?;
        let mut out = VarDictionary::new();
        out.set("mode", mode);
        let mut positions = VarArray::new();
        for &(x, z) in &placed.cells {
            let mut cell = VarArray::new();
            cell.push(&x.to_variant());
            cell.push(&z.to_variant());
            positions.push(&cell.to_variant());
        }
        out.set("positions", &positions);
        out.set("swept", placed.swept as i64);
        Ok(out)
    }

    fn seams_now(&mut self) -> Seams {
        if self.seams.is_none() {
            // battle_sim.gd:38-43 — cast: "1"/"on", anything else is off.
            let on = |k: &str| {
                matches!(std::env::var(k).unwrap_or_default().as_str(), "1" | "on")
            };
            // battle_sim.gd:26-31 — spacing (NML-1073 S3): default ON, "0"/"off"
            // (case-insensitive) opts out.
            let spacing_off = |k: &str| {
                matches!(std::env::var(k).unwrap_or_default().to_lowercase().as_str(), "0" | "off")
            };
            self.seams = Some(Seams {
                spacing: !spacing_off("NML_SIM_SPACING"),
                cast: on("NML_SIM_CAST"),
                // NML-1073 M4-7. Read ONCE, here, like its two siblings.
                path: on("NML_SIM_PATH"),
                // NML-1073 M5 D1-B4b/BUG-3. Not read from the environment here:
                // `plan_inner` takes `hero_attach` off the HEADER knobs (which
                // `act_recorder.gd` stamps from `BattleSim.hero_fold_enabled()`),
                // so the seat's own knob decides. This struct only supplies
                // `path` to the planner; the two below are inert for it.
                hero_attach: false,
                // NML-1073 M5 D5-1 — same reasoning: a header knob, not an env one.
                charge_landing: false,
                // NML-1073 M5 D6a-B4, same reasoning: `sighting` rides the
                // HEADER knobs into the tray resolver and is inert here.
                sighting: false,
                // NML-1073 M5 D5-2 — likewise. The in-game `BattleSim` keeps its
                // rigid imagination; only the trainer's header turns this on.
                movement: false,
                // D1-B8: inert without a tray — this seat resolves expected values.
                no_dangerous: false,
                // D5-4: inert — this seat never turns `hero_attach` on.
                no_engage_fold: false,
            });
        }
        self.seams.unwrap()
    }

    fn root(&mut self) -> String {
        if self.repo_root.is_none() {
            let env = std::env::var("NML_CORE_REPO").unwrap_or_default();
            self.repo_root = Some(if env.is_empty() {
                godot::classes::ProjectSettings::singleton()
                    .globalize_path("res://")
                    .to_string()
            } else {
                env
            });
        }
        self.repo_root.clone().unwrap()
    }

    /// Builds (or reuses) the profile table, roster and static closure for the
    /// roster this plain state carries.
    fn ensure_closure(&mut self, plain: &VarDictionary, keys: &[String]) -> Result<(), String> {
        if self.cache.statics.is_some() && self.cache.keys == keys {
            return Ok(());
        }
        let (profiles, roster) = plain::build_roster(plain)?;
        let root = self.root();
        if self.reg.is_none() {
            self.reg = Some(Registries::new(&root));
        }
        let reg = self.reg.as_mut().unwrap();
        let statics: Vec<UnitStatic> =
            profiles.list.iter().map(|p| UnitStatic::build(reg, p)).collect();
        self.cache.keys = keys.to_vec();
        self.cache.profiles = Some(Rc::new(profiles));
        self.cache.roster = Some(Rc::new(roster));
        self.cache.statics = Some(Rc::new(statics));
        Ok(())
    }

    fn push(&mut self, slot: Slot) -> i64 {
        match self.free.pop() {
            Some(i) => {
                self.slab[i] = Some(slot);
                (i + 1) as i64
            }
            None => {
                self.slab.push(Some(slot));
                self.slab.len() as i64
            }
        }
    }

    fn index(&mut self, h: i64) -> Option<usize> {
        let i = (h - 1) as usize;
        if h <= 0 || i >= self.slab.len() || self.slab[i].is_none() {
            self.last_error = format!("handle {h} is not live");
            return None;
        }
        Some(i)
    }
}

/// `AiPlanner._policy_candidates` ai_planner.gd:517-545 — the planner's own
/// action dictionary, read off a Variant.
fn action_of(d: &VarDictionary) -> Action {
    let dest = d.get("dest").and_then(|v| {
        if let Ok(p) = v.try_to::<Vector3>() {
            return Some([p.x as f64, p.y as f64, p.z as f64]);
        }
        Some(plain::any_array(&v)).map(|a| {
            let mut out = [0.0f64; 3];
            for (i, slot) in out.iter_mut().enumerate() {
                if i < a.len() {
                    *slot = plain::num(&a.at(i));
                }
            }
            out
        })
    });
    let opt = |k: &str| -> Option<String> {
        d.get(k).map(|v| plain::text(&v)).filter(|s| !s.is_empty())
    };
    Action {
        kind: d.get("kind").map(|v| plain::int(&v)).unwrap_or(-1),
        unit: d.get("unit").map(|v| plain::text(&v)).unwrap_or_default(),
        dest,
        shoot: opt("shoot"),
        charge: opt("charge"),
        patient: d.get("patient").map(|v| plain::flag(&v)).unwrap_or(false),
        // The live table hands the planner a pooled act; per-weapon aim exists only in
        // the recorded sidecar (NML-1150), so the bridge never carries a split.
        split: None,
    }
}

/// `AiActRecorder.begin`'s `"statics"` object (act_recorder.gd:62-63) read off a
/// Variant. `playout_net` only ever has to answer "empty or not" — a non-empty
/// net is a different brain and the port declines it (`Unsupported::NetPlayout`).
fn act_statics_of(d: &VarDictionary) -> ActStatics {
    let net = d
        .get("playout_net")
        .and_then(|v| v.try_to::<VarDictionary>().ok())
        .map(|n| n.len())
        .unwrap_or(0);
    let mut m = serde_json::Map::new();
    if net > 0 {
        m.insert("net".to_string(), serde_json::Value::Bool(true));
    }
    ActStatics {
        opener_seat: d.get("opener_seat").map(|v| plain::flag(&v)).unwrap_or(false),
        playout_search: d.get("playout_search").map(|v| plain::flag(&v)).unwrap_or(false),
        fit_mode: d.get("fit_mode").map(|v| plain::flag(&v)).unwrap_or(false),
        playout_net: serde_json::Value::Object(m),
    }
}

/// The pick as `AiPlanner.plan_with_rollout` returns it (ai_planner.gd:272-275),
/// plus the two things a Dictionary can carry that the GDScript keeps in class
/// statics: the winning rollout's LEAF (`_last_leaf_state`, :213) and the search
/// TRACE (`AiPlanner.trace`, :97) in its own recorded shape.
fn pick_out(p: &Pick, root: &plain::Captured, sig: i64) -> VarDictionary {
    let mut out = VarDictionary::new();
    out.set("used", true);
    out.set("unit_key", &GString::from(p.unit_key.as_str()));
    out.set("action", &plain::candidate_out(&p.action));
    let mut exp = VarDictionary::new();
    exp.set("before", p.expectation_before);
    exp.set("after", p.expectation_after);
    out.set("expectation", &exp);
    let mut runner = VarDictionary::new();
    if let Some((k, c, s)) = &p.runner_up {
        runner.set("unit_key", &GString::from(k.as_str()));
        runner.set("action", &plain::candidate_out(c));
        runner.set("score", *s);
    }
    out.set("runner_up", &runner);
    out.set("waits", p.waits);
    let mut rolled = VarArray::new();
    for k in &p.rolled_units {
        rolled.push(&GString::from(k.as_str()).to_variant());
    }
    out.set("rolled_units", &rolled);
    match &p.last_leaf {
        Some(leaf) => out.set("leaf_state", &plain::plain_of_derived(leaf, root)),
        None => out.set("leaf_state", &VarDictionary::new()),
    }
    // --- the trace, in `AiPlanner.trace`'s own shape (ai_planner.gd:145-155) ---
    let mut scored = VarArray::new();
    for (idx, unit, kind, sc) in &p.scored {
        let mut r = VarDictionary::new();
        r.set("idx", *idx);
        r.set("unit", &GString::from(unit.as_str()));
        r.set("kind", *kind);
        r.set("score", *sc);
        scored.push(&r.to_variant());
    }
    out.set("scored", &scored);
    let mut pool = VarArray::new();
    for i in &p.pool_idx {
        pool.push(&(*i as i64).to_variant());
    }
    out.set("pool_idx", &pool);
    let mut rs = VarArray::new();
    for (idx, v) in &p.rs {
        let mut r = VarDictionary::new();
        r.set("idx", *idx);
        r.set("rs", *v);
        rs.push(&r.to_variant());
    }
    out.set("rs", &rs);
    out.set("best_idx", p.best_idx);
    out.set("runner_idx", p.runner_idx);
    match &p.arbitration {
        Some(a) => {
            let mut d = VarDictionary::new();
            d.set("sig", sig);
            d.set("n", a.n);
            d.set("sum_b", a.sum_b);
            d.set("sum_r", a.sum_r);
            d.set("swapped", a.swapped);
            out.set("arbitration", &d);
        }
        None => out.set("arbitration", &Variant::nil()),
    }
    out
}
