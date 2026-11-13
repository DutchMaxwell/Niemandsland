//! One-core P3 (N3 b): the round end and the round begin of a plain game in the table's wording. Plain missions only
//! (O7): a mission with markers (relics, destructible or secret markers) stays table code until its family moves.

use std::rc::Rc;

use serde_json::{json, Value};

use crate::logline::{Category, LogLine};
use crate::mission::{playout_seize, vp_of, vp_score_end, vp_score_round};
use crate::rollout::cross_round;
use crate::score::control_gap_in;
use crate::state::State;
use crate::unit::UnitStatic;
use crate::{CONTROL_EPS, OBJECTIVE_CONTROL_IN};

/// What the table words a round end with that the State does not hold: each side's label (`_solo_player_label`), the
/// rules cite of the seize-lock reason (`OPRApiClient.rules_cite`), and per roster key the rule that placed a unit this
/// round ("Spawn" / "Split", the unit's `origin`); a unit that arrived this round and is not listed came from Ambush.
#[derive(Default)]
pub struct RoundWords {
    pub labels: Vec<(i64, String)>,
    pub cite: String,
    pub placed_by: Vec<(String, String)>,
}

/// `_solo_player_label` (main.gd): the label the table gave `pid`, else "P<n>".
fn label_of(labels: &[(i64, String)], pid: i64) -> String {
    labels.iter().find(|(p, _)| *p == pid).map_or_else(|| format!("P{pid}"), |(_, l)| l.clone())
}

fn general(rule: &'static str, text: String) -> LogLine {
    LogLine { rule, category: Category::General, side: 0, text, detail: None }
}

/// `_solo_auto_seize`'s `locked_near` for objective `i`: each unit that arrived this round, is neither Shaken nor an
/// Aircraft and has a base edge within 3" of it says why it cannot seize or contest, joined by "; " ("" = none).
fn lock_reasons(state: &State, i: usize, words: &RoundWords) -> String {
    let op = state.objectives[i].pos;
    let mut out: Vec<String> = Vec::new();
    for k in 0..state.units() {
        if state.alive[k] <= 0 || state.shaken[k] || state.aircraft[k] || state.ambush_arrived_round[k] != state.round
            || control_gap_in(state, k, op) > OBJECTIVE_CONTROL_IN + CONTROL_EPS
        {
            continue;
        }
        let (name, cite) = (&state.profile(k).name, &words.cite);
        out.push(match words.placed_by.iter().find(|(key, _)| key == state.key(k)) {
            Some((_, rule)) => format!("{name} was placed by {rule} this round and cannot seize or contest ({cite})"),
            None => format!("{name} arrived from Ambush this round and cannot seize or contest ({cite})"),
        });
    }
    out.join("; ")
}

/// The table's round end, `_solo_auto_seize` + `_solo_book_mission_vp` (main.gd), for a plain mission: the seize of
/// `imagined_round_end` from the final positions (its carry and destroy steps need markers), one line per objective
/// whose owner changed (with the lock reason of a unit near it that arrived this round), one line per other objective
/// with such a unit, then the round's VP when the mission scores per round - with the game-end bonus after the
/// last round, as `_solo_book_mission_vp(final)` books it. Writes the owners into `state.objectives` and the ledger
/// into `state.vp` / `state.vp_memo`. `Err` = refused, nothing written: a mission with markers is not ported (O7).
pub fn end_round(state: &mut State, words: &RoundWords) -> Result<Vec<LogLine>, &'static str> {
    if !state.markers_meta.is_empty() {
        return Err("unported: mission markers");
    }
    let before: Vec<i64> = state.objectives.iter().map(|o| o.owner).collect();
    let mut owners = before.clone();
    playout_seize(state, &mut owners);
    let near: Vec<String> = (0..owners.len()).map(|i| lock_reasons(state, i, words)).collect();
    let mut lines = Vec::new();
    for (i, (&was, &now)) in before.iter().zip(&owners).enumerate() {
        if now == was {
            continue;
        }
        let why = if near[i].is_empty() { String::new() } else { format!(" — {}", near[i]) };
        let text = if now == 0 {
            format!("Objective {} contested — goes neutral{why}", i + 1)
        } else {
            format!("Objective {} seized by {}{why}", i + 1, label_of(&words.labels, now))
        };
        lines.push(general("objective_seize", text));
    }
    for (i, why) in near.iter().enumerate().filter(|(i, why)| !why.is_empty() && before[*i] == owners[*i]) {
        lines.push(general("objective_seize", format!("Objective {}: {why}", i + 1)));
    }
    if &*state.scoring == "round_vp" {
        let mut vp = vp_of(state.vp.as_deref());
        let mut memo = state.vp_memo.as_deref().and_then(Value::as_object).cloned().unwrap_or_default();
        let flavour = state.vp_flavour.as_deref().cloned().unwrap_or(Value::Null);
        vp_score_round(&owners, &mut vp, &flavour, &mut memo, &state.markers_meta);
        if state.round >= state.rounds_total {
            vp_score_end(&owners, &mut vp, &flavour);
        }
        state.vp = Some(Rc::new(json!([vp[0], vp[1]])));
        state.vp_memo = Some(Rc::new(Value::Object(memo)));
        let text = format!("Mission VP after round {}: P1 {} — P2 {}", state.round, vp[0], vp[1]);
        lines.push(general("mission_vp", text));
    }
    Ok(lines)
}

/// The table's round begin (`_solo_end_round` after `advance_round()`, main.gd): `cross_round` - the next round, every
/// unit refreshed, the opener - and "Round %d begins". `finished_first` = the side that finished activating first last
/// round (it did NOT take the last activation): it opens, unless it has no unit left on the table and the other side
/// has one (`ai_opens_next_round`, GF and AoF). With no unit on either side it stays the opener (the table names the
/// human side there; nothing can activate in that round). `None` = `cross_round`'s head count.
pub fn begin_round(statics: &[UnitStatic], state: &mut State, finished_first: Option<i64>) -> (i64, Vec<LogLine>) {
    let mut opener = cross_round(statics, state, finished_first);
    let has = |side: i64| (0..state.units()).any(|k| state.player[k] == side && state.alive[k] > 0 && !state.dormant[k]);
    if finished_first.is_some() && !has(opener) && has(3 - opener) {
        opener = 3 - opener;
    }
    (opener, vec![general("round_begin", format!("Round {} begins", state.round))])
}

#[cfg(test)]
mod tests {
    use super::{begin_round, end_round, RoundWords};
    use crate::state::{Marker, Objective, State};
    use crate::unit::UnitStatic;
    use crate::IN2M;
    use serde_json::json;
    use std::rc::Rc;

    /// `four_unit_line` as a round-VP game at 2 - 3 VP: side 1 = a (0") and ah (2"), side 2 = bh (9") and b (12"),
    /// every base 1" in radius. Objective 1 at -3" (a's base edge 2" off, side 2 at least 11"); objective 2 at
    /// `obj2` inches, owned by `owner2`.
    fn board(round: i64, obj2: f64, owner2: i64) -> State {
        let mut st = crate::sim::tests::four_unit_line();
        st.player = vec![1, 1, 2, 2];
        (st.round, st.rounds_total, st.scoring, st.vp) = (round, 4, Rc::from("round_vp"), Some(Rc::new(json!([2, 3]))));
        st.objectives = vec![Objective { pos: [-3.0 * IN2M, 0.0, 0.0], owner: 0 }, Objective { pos: [obj2 * IN2M, 0.0, 0.0], owner: owner2 }];
        st
    }

    fn run(st: &mut State) -> (Vec<i64>, Vec<String>) {
        let words = RoundWords { labels: vec![(1, "P1 (Alpha)".into()), (2, "P2 (Beta)".into())], ..RoundWords::default() };
        let lines = end_round(st, &words).expect("a plain mission is ported");
        (st.objectives.iter().map(|o| o.owner).collect(), lines.into_iter().map(|l| l.text).collect())
    }

    /// Side 1 alone within 3" of objective 1, nobody near objective 2: [1, 0], one seize line and the VP line.
    #[test]
    fn a_plain_round_end_seizes_and_books_the_round_vp_in_the_tables_words() {
        let (owners, text) = run(&mut board(2, 30.0, 0));
        assert_eq!(owners, [1, 0]);
        assert_eq!(text, ["Objective 1 seized by P1 (Alpha)", "Mission VP after round 2: P1 3 — P2 3"]);
    }

    /// The last round: objective 2 at 5.5" has ah and bh within 3" (contested, side 2 loses it), and the game-end
    /// majority bonus goes to side 1 on top of its round VP. A mission with a marker is refused and left as it was.
    #[test]
    fn the_last_round_pays_the_end_bonus_and_a_marker_mission_is_refused() {
        let (owners, text) = run(&mut board(4, 5.5, 2));
        assert_eq!(owners, [1, 0]);
        assert_eq!(text, ["Objective 1 seized by P1 (Alpha)", "Objective 2 contested — goes neutral", "Mission VP after round 4: P1 4 — P2 3"]);
        let mut st = board(2, 30.0, 0);
        st.markers_meta.push(serde_json::from_str::<Marker>("{}").unwrap());
        assert_eq!(end_round(&mut st, &RoundWords::default()), Err("unported: mission markers"));
        assert_eq!((st.objectives[0].owner, st.vp.as_deref()), (0, Some(&json!([2, 3]))));
    }

    /// A unit that arrived this round cannot seize or contest, and the lines say why: ah (placed by Spawn) stands near
    /// both objectives, bh (from Ambush) near objective 2. Objective 1 goes to a, its line carries ah's reason;
    /// objective 2 keeps its owner (nobody else near) and gets a line of its own naming both, in capture order. A Shaken
    /// arrival is not named, as on the table.
    #[test]
    fn a_unit_that_arrived_this_round_is_named_in_the_seize_lines() {
        let words = RoundWords { labels: vec![(1, "P1 (Alpha)".into())], cite: "GF 3.5".into(), placed_by: vec![("ah".into(), "Spawn".into())] };
        let spawn = "u was placed by Spawn this round and cannot seize or contest (GF 3.5)";
        let ambush = "; u arrived from Ambush this round and cannot seize or contest (GF 3.5)";
        for (bh_shaken, tail) in [(false, ambush), (true, "")] {
            let mut st = board(2, 5.5, 2);
            (st.scoring, st.objectives[0].pos, st.ambush_arrived_round) = (Rc::from(""), [IN2M, 0.0, 0.0], vec![-1, 2, -1, 2]);
            st.shaken[3] = bh_shaken;
            let lines = end_round(&mut st, &words).expect("a plain mission is ported");
            assert_eq!(st.objectives.iter().map(|o| o.owner).collect::<Vec<_>>(), [1, 2]);
            let want = [format!("Objective 1 seized by P1 (Alpha) — {spawn}"), format!("Objective 2: {spawn}{tail}")];
            assert_eq!(lines.into_iter().map(|l| l.text).collect::<Vec<_>>(), want);
        }
    }

    /// Round 2 ends with every unit activated; side 2 finished first and opens round 3, every unit is fresh. With side
    /// 1's units all dead, side 1 finishing first still hands the opening to side 2, the side with units left.
    #[test]
    fn the_side_that_finished_first_opens_the_next_round_unless_it_has_no_unit_left() {
        let statics = [UnitStatic::default()];
        let mut st = board(2, 30.0, 0);
        st.activated = vec![true; 4];
        let (opener, lines) = begin_round(&statics, &mut st, Some(2));
        assert_eq!((opener, st.round, st.activated.clone()), (2, 3, vec![false; 4]));
        assert_eq!(lines.into_iter().map(|l| l.text).collect::<Vec<_>>(), ["Round 3 begins"]);
        let mut st = board(2, 30.0, 0);
        st.alive = vec![0, 0, 1, 1];
        assert_eq!(begin_round(&statics, &mut st, Some(1)).0, 2);
        st.alive = vec![1, 1, 1, 1];
        assert_eq!(begin_round(&statics, &mut st, Some(1)).0, 1);
    }
}
