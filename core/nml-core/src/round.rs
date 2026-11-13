//! One-core P3 (N3 b): the round end and the round begin of a plain game in the table's wording. Plain missions only
//! (O7): a mission with markers (relics, destructible or secret markers) stays table code until its family moves.

use std::rc::Rc;

use serde_json::{json, Value};

use crate::logline::{Category, LogLine};
use crate::mission::{playout_seize, vp_of, vp_score_end, vp_score_round};
use crate::rollout::cross_round;
use crate::state::State;
use crate::unit::UnitStatic;

/// `_solo_player_label` (main.gd): the label the table gave `pid`, else "P<n>".
fn label_of(labels: &[(i64, String)], pid: i64) -> String {
    labels.iter().find(|(p, _)| *p == pid).map_or_else(|| format!("P{pid}"), |(_, l)| l.clone())
}

fn general(rule: &'static str, text: String) -> LogLine {
    LogLine { rule, category: Category::General, side: 0, text, detail: None }
}

/// The table's round end, `_solo_auto_seize` + `_solo_book_mission_vp` (main.gd), for a plain mission: the seize of
/// `imagined_round_end` from the final positions (its carry and destroy steps need markers), one line per objective
/// whose owner changed, then the round's VP when the mission scores per round - with the game-end bonus after the
/// last round, as `_solo_book_mission_vp(final)` books it. Writes the owners into `state.objectives` and the ledger
/// into `state.vp` / `state.vp_memo`. `Err` = refused, nothing written: a mission with markers is not ported (O7).
pub fn end_round(state: &mut State, labels: &[(i64, String)]) -> Result<Vec<LogLine>, &'static str> {
    if !state.markers_meta.is_empty() {
        return Err("unported: mission markers");
    }
    let before: Vec<i64> = state.objectives.iter().map(|o| o.owner).collect();
    let mut owners = before.clone();
    playout_seize(state, &mut owners);
    let mut lines = Vec::new();
    for (i, (&was, &now)) in before.iter().zip(&owners).enumerate() {
        if now == was {
            continue;
        }
        let text = if now == 0 {
            format!("Objective {} contested — goes neutral", i + 1)
        } else {
            format!("Objective {} seized by {}", i + 1, label_of(labels, now))
        };
        lines.push(general("objective_seize", text));
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
    use super::{begin_round, end_round};
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
        let labels = [(1, "P1 (Alpha)".to_string()), (2, "P2 (Beta)".to_string())];
        let lines = end_round(st, &labels).expect("a plain mission is ported");
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
        assert_eq!(end_round(&mut st, &[]), Err("unported: mission markers"));
        assert_eq!((st.objectives[0].owner, st.vp.as_deref()), (0, Some(&json!([2, 3]))));
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
