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

use nml_core::state::{Profiles, Roster};
use nml_core::unit::UnitStatic;
use nml_core::{reply_threat, resolve, score, Action, Registries, Seams};

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

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NmlCore {
    #[allow(dead_code)]
    base: Base<RefCounted>,
    slab: Vec<Option<Slot>>,
    free: Vec<usize>,
    cache: RosterCache,
    reg: Option<Registries>,
    repo_root: Option<String>,
    seams: Option<Seams>,
    last_error: String,
    dropped: Vec<String>,
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
    #[func]
    fn set_seams(&mut self, spacing: bool, cast: bool) {
        self.seams = Some(Seams { spacing, cast });
    }

    #[func]
    fn seams(&mut self) -> VarDictionary {
        let s = self.seams_now();
        let mut d = VarDictionary::new();
        d.set("spacing", s.spacing);
        d.set("cast", s.cast);
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

    fn seams_now(&mut self) -> Seams {
        if self.seams.is_none() {
            // battle_sim.gd:25-42 — "1" or "on", anything else is off.
            let on = |k: &str| {
                matches!(std::env::var(k).unwrap_or_default().as_str(), "1" | "on")
            };
            self.seams = Some(Seams {
                spacing: on("NML_SIM_SPACING"),
                cast: on("NML_SIM_CAST"),
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
        v.try_to::<VarArray>().ok().map(|a| {
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
    }
}
