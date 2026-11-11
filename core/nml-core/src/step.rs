//! One-core Phase 0 spike: the step API over the existing tray resolvers.
//!
//! The table owns the dice; the core owns the rules. A resolver runs on a
//! `Tray::supplied` with every face group the table has rolled so far. When the
//! tray runs dry, the core answers `NeedRoll` with the first missing roll's
//! kind, count, target and owner; the table rolls it (physically or seeded) and
//! asks again with one more group. Resolvers are pure in their faces, so
//! re-running from the start is exact — no resolver had to change.

use crate::dice::{Roll, ShootResult, Tray};

/// What the core needs next for one exchange.
#[derive(Debug)]
pub enum Step<T> {
    /// Roll `faces` dice and call again with them appended (`count` is the
    /// rules count; `faces` can differ below `EPOCH_67_MARKERS_BURSTS`).
    NeedRoll { index: usize, faces: usize, kind: &'static str, count: i64, target: i64, owner: String },
    /// A supplied group had the wrong number of faces.
    BadFaces { index: usize, wanted: usize, got: usize },
    /// The exchange is resolved on exactly the supplied faces.
    Done(T),
}

/// Run `resolve` on the supplied faces; `rolls` reads the roll records off its
/// result (in draw order) so a starved roll can be described.
pub fn step_with<T>(
    supplied: &[Vec<u8>],
    resolve: impl FnOnce(&mut Tray) -> T,
    rolls: impl Fn(&T) -> &[Roll],
) -> Step<T> {
    let mut tray = Tray::supplied(supplied.to_vec());
    let out = resolve(&mut tray);
    let feed = tray.feed().expect("supplied tray");
    if let Some((index, wanted, got)) = feed.mismatch {
        return Step::BadFaces { index, wanted, got };
    }
    match feed.starved_at {
        None => Step::Done(out),
        Some((index, faces)) => match rolls(&out).get(index) {
            Some(r) => Step::NeedRoll { index, faces, kind: r.kind, count: r.count, target: r.target, owner: r.owner.clone() },
            None => Step::BadFaces { index, wanted: 0, got: 0 },
        },
    }
}

/// `step_with` for any resolver that reports a `ShootResult`.
pub fn shoot_step(supplied: &[Vec<u8>], resolve: impl FnOnce(&mut Tray) -> ShootResult) -> Step<ShootResult> {
    step_with(supplied, resolve, |r| &r.rolls)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dice::resolve_shooting_with_tray;
    use crate::unit::{Ctx, ShootProfile};

    /// The driver loop: roll each `NeedRoll` from a seeded tray, feed it back.
    /// Must equal one straight seeded run, roll for roll and wound for wound.
    #[test]
    fn stepped_volley_equals_seeded_volley() {
        let prof = ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ap: 1, ..Default::default() };
        let att = Ctx { quality: 4, ..Default::default() };
        let def = Ctx { defense: 4, models: 10, tough: 1, ..Default::default() };
        for seed in 0..1000i64 {
            let run = |t: &mut Tray| resolve_shooting_with_tray(&[prof.clone()], &[0], &[10], &att, &def, 12.0, t);
            let want = run(&mut Tray::seeded(seed));
            let mut dice = Tray::seeded(seed);
            let mut faces: Vec<Vec<u8>> = Vec::new();
            let got = loop {
                match shoot_step(&faces, run) {
                    Step::NeedRoll { faces: n, .. } => faces.push(dice.roll(n)),
                    Step::Done(r) => break r,
                    Step::BadFaces { index, wanted, got } => panic!("seed {seed}: roll {index} wanted {wanted} got {got}"),
                }
            };
            assert!(!want.rolls.is_empty(), "seed {seed}: the volley must roll");
            assert_eq!(got.wounds, want.wounds, "seed {seed}");
            assert_eq!(got.rolls, want.rolls, "seed {seed}");
            assert_eq!(got.log, want.log, "seed {seed}");
        }
    }
}
