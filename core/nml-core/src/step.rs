//! One-core Phase 0 spike: the step API over the existing tray resolvers.
//!
//! The table owns the dice; the core owns the rules. A resolver runs on a
//! `Tray::supplied` with every face group the table has rolled so far. When the
//! tray runs dry, the core answers `NeedRoll` with the first missing roll's
//! kind, count, target and owner; the table rolls it (physically or seeded) and
//! asks again with one more group. Resolvers are pure in their faces, so
//! re-running from the start is exact — no resolver had to change.

use crate::dice::{Roll, ShootResult, Tray};
use crate::landing::Landing;
use crate::logline::LogLine;

/// What the core needs next for one exchange.
#[derive(Debug)]
pub enum Step<T> {
    /// Roll `faces` dice and call again with them appended (`count` is the
    /// rules count; `faces` can differ below `EPOCH_67_MARKERS_BURSTS`).
    /// `lines` are only those said before the starved draw: after it the
    /// replay runs on filler 1s, so a later line would tell a false story.
    /// `landings` follow the same rule and are cumulative: each `NeedRoll`
    /// repeats the earlier ones, the table skips what it has landed.
    NeedRoll { index: usize, faces: usize, kind: &'static str, count: i64, target: i64, owner: String, lines: Vec<LogLine>, landings: Vec<Landing> },
    /// The core will not answer for this exchange: the draws and the records
    /// disagree (some draw pushed no record, so a feed index no longer names its
    /// roll), or a supplied group had the wrong number of faces. `draws` and
    /// `records` are the tray's draw count and the result's record count. They
    /// differ only for the guard's own refusal; a size or missing-record refusal
    /// comes after the guard has passed, so there they are equal.
    /// Refused rather than a wrong `NeedRoll`.
    Refused { draws: usize, records: usize, reason: String },
    /// The exchange is resolved on exactly the supplied faces; every line said
    /// and every landing made.
    Done(T, Vec<LogLine>, Vec<Landing>),
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
    let records = rolls(&out).len();
    if feed.draws() != records {
        let reason = "tray draws and roll records disagree: a resolver drew dice without a roll record".to_string();
        return Step::Refused { draws: feed.draws(), records, reason };
    }
    if let Some((index, wanted, got)) = feed.mismatch {
        let reason = format!("roll {index}: wanted {wanted} faces, got {got}");
        return Step::Refused { draws: feed.draws(), records, reason };
    }
    match feed.starved_at {
        None => Step::Done(out, tray.all_lines(), tray.all_landings()),
        Some((index, faces)) => match rolls(&out).get(index) {
            Some(r) => {
                let lines = tray.lines_upto(index);
                let landings = tray.landings_upto(index);
                Step::NeedRoll { index, faces, kind: r.kind, count: r.count, target: r.target, owner: r.owner.clone(), lines, landings }
            }
            None => {
                let reason = format!("roll {index}: no roll record for this draw");
                Step::Refused { draws: feed.draws(), records, reason }
            }
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
            let run = |t: &mut Tray| resolve_shooting_with_tray(std::slice::from_ref(&prof), &[0], &[10], &att, &def, 12.0, t);
            let want = run(&mut Tray::seeded(seed));
            let mut dice = Tray::seeded(seed);
            let mut faces: Vec<Vec<u8>> = Vec::new();
            let got = loop {
                match shoot_step(&faces, run) {
                    Step::NeedRoll { faces: n, .. } => faces.push(dice.roll(n)),
                    Step::Done(r, _, _) => break r,
                    Step::Refused { reason, .. } => panic!("seed {seed}: {reason}"),
                }
            };
            assert!(!want.rolls.is_empty(), "seed {seed}: the volley must roll");
            assert_eq!(got.wounds, want.wounds, "seed {seed}");
            assert_eq!(got.rolls, want.rolls, "seed {seed}");
            assert_eq!(got.log, want.log, "seed {seed}");
        }
    }

    /// A planted silent draw (as at the two spotter placement rolls in sim.rs)
    /// shifts every feed index off its record: the step must refuse, never name
    /// the volley's first roll as the one it needs.
    #[test]
    fn silent_draw_is_refused_not_misnamed() {
        let prof = ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ap: 1, ..Default::default() };
        let att = Ctx { quality: 4, ..Default::default() };
        let def = Ctx { defense: 4, models: 10, tough: 1, ..Default::default() };
        let run = |t: &mut Tray| {
            t.roll(1);
            resolve_shooting_with_tray(std::slice::from_ref(&prof), &[0], &[10], &att, &def, 12.0, t)
        };
        let mut faces: Vec<Vec<u8>> = Vec::new();
        for _ in 0..4 {
            match shoot_step(&faces, run) {
                Step::Refused { draws, records, .. } => return assert_eq!(draws, records + 1),
                Step::NeedRoll { index, kind, faces: n, .. } => {
                    eprintln!("NeedRoll {index} names {kind} x{n}, but draw {index} is the silent one");
                    faces.push(vec![6; n]);
                }
                other => panic!("expected Refused, got {other:?}"),
            }
        }
        panic!("a silent draw was never refused");
    }

    /// A supplied group of the wrong size is a `Refused` that names the roll,
    /// the faces it wanted and the faces it got; draws and records still agree.
    #[test]
    fn wrong_face_count_is_refused_with_its_reason() {
        let prof = ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ap: 1, ..Default::default() };
        let att = Ctx { quality: 4, ..Default::default() };
        let def = Ctx { defense: 4, models: 10, tough: 1, ..Default::default() };
        let run = |t: &mut Tray| resolve_shooting_with_tray(std::slice::from_ref(&prof), &[0], &[10], &att, &def, 12.0, t);
        let n = match shoot_step(&[], run) {
            Step::NeedRoll { index: 0, faces, .. } => faces,
            other => panic!("expected NeedRoll for roll 0, got {other:?}"),
        };
        match shoot_step(&[vec![3; n + 1]], run) {
            Step::Refused { draws, records, reason } => {
                assert_eq!(reason, format!("roll 0: wanted {n} faces, got {}", n + 1));
                assert_eq!(draws, records);
            }
            other => panic!("expected Refused, got {other:?}"),
        }
    }

    /// A line said after the starved draw read a filler 1: `NeedRoll` must not
    /// carry it; once the roll is supplied, `Done` carries every line.
    #[test]
    fn need_roll_carries_only_lines_before_the_starve() {
        use crate::logline::Category;
        let line = |text: &str| LogLine { rule: "test", category: Category::Combat, side: 0, text: text.into(), detail: None };
        let run = |t: &mut Tray| {
            t.say(|| line("A"));
            let faces = t.roll(1);
            t.say(|| line("B"));
            vec![Roll { kind: "attack", count: 1, target: 4, faces, owner: "Rifle".into() }]
        };
        match step_with(&[], run, |r| r.as_slice()) {
            Step::NeedRoll { index: 0, lines, .. } => assert_eq!(lines, vec![line("A")]),
            other => panic!("expected NeedRoll for roll 0, got {other:?}"),
        }
        match step_with(&[vec![5]], run, |r| r.as_slice()) {
            Step::Done(_, lines, _) => assert_eq!(lines, vec![line("A"), line("B")]),
            other => panic!("expected Done, got {other:?}"),
        }
    }

    /// A landing made after the starved draw is not true yet: `NeedRoll` must
    /// not carry it; once the roll is supplied, `Done` carries every landing.
    #[test]
    fn need_roll_carries_only_landings_before_the_starve() {
        use crate::landing::LandedModel;
        let landing = |unit: usize| Landing { unit, models: vec![LandedModel { at: [1.0, 0.0, 2.0], wounds_left: 0, dead: true }] };
        let run = |t: &mut Tray| {
            t.land(|| landing(0));
            let faces = t.roll(1);
            t.land(|| landing(1));
            vec![Roll { kind: "attack", count: 1, target: 4, faces, owner: "Rifle".into() }]
        };
        match step_with(&[], run, |r| r.as_slice()) {
            Step::NeedRoll { index: 0, landings, .. } => assert_eq!(landings, vec![landing(0)]),
            other => panic!("expected NeedRoll for roll 0, got {other:?}"),
        }
        match step_with(&[vec![5]], run, |r| r.as_slice()) {
            Step::Done(_, _, landings) => assert_eq!(landings, vec![landing(0), landing(1)]),
            other => panic!("expected Done, got {other:?}"),
        }
    }
}
