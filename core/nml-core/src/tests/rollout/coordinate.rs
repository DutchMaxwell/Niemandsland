use super::*;

// ------------------------------------------------ Coordinate (wave 4) ---
//
// THE RULE, verbatim from the book (word-identical in both snapshot books that
// carry it — GF Human Defense Force, AoF Human Empire): "At the end of this
// unit's activation, another friendly unit within 12" that hasn't activated yet
// may be activated immediately. May not be used if this unit was activated via
// Coordinate."
//
// THE FIXTURE. Player 1 fields the carrier `p1_0_a` at the origin, a friend
// `p1_1_b` 0.2 m away (a 6.6" base-edge gap — inside the 12" reach) and a friend
// `p1_2_c` 1.5 m away (57.8" — far outside it). Player 2 fields two plain units
// 30 m off, far enough that no charge and no volley is ever on the menu, so
// every activation is a bare HOLD and the only thing the rollout can vary is WHO
// acts next. The carrier's own hold is the rollout's opening action.
//
// WHY A TAIL CAP. Boundaries are the only states `rollout_traced` hands back,
// and at a boundary every unit is activated — the activation ORDER is invisible
// there. `tail_cap_p1 = 1` truncates the rollout mid-round (`Stop::TailCap`), so
// the returned state shows exactly who moved and who did not. That is what makes
// the hand-off observable at all.

const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force",
    "special_rules":["Coordinate"],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "p1_1_b":{"unit_id":"p1_1_b","name":"B","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "p1_2_c":{"unit_id":"p1_2_c","name":"C","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "p2_0_x":{"unit_id":"p2_0_x","name":"X","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "p2_1_y":{"unit_id":"p2_1_y","name":"Y","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","units":{
  "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],
    "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
    "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
    "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
    "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
  "p1_1_b":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],
    "positions":[[0.2,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
    "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
    "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
    "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
  "p1_2_c":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],
    "positions":[[1.5,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
    "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
    "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
    "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
  "p2_0_x":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
    "positions":[[30.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
    "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
    "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
    "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
  "p2_1_y":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
    "positions":[[30.0,0.0,3.0]],"in_cover":false,"shaken":false,"fatigued":false,
    "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
    "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
    "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

fn hand_off_line(epoch: u32) -> (State, Vec<UnitStatic>) {
    let header = read_act_header(HEADER).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let mut roster = None;
    let st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
    let statics = statics_of(&st, epoch);
    (st, statics)
}

/// One truncated rollout from the carrier's own hold, seen from player 1's seat.
/// `tail_cap_p1` is the per-seat activation cap; the state handed back is the
/// mid-round truncation, which is where the order is readable.
fn truncated(st: &State, statics: &[UnitStatic], epoch: u32, tail_cap_p1: i64) -> State {
    let terrain = Terrain::default();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let knobs = Knobs { tail_cap_p1, ..Knobs::default() };
    let roll = Rollout::new(Policy::new(statics, &terrain, seams), knobs);
    let mut sc = Scratch::default();
    let (ends, _stop) = roll
        .rollout_traced(st, &Candidate::hold("p1_0_a"), 1, 1, &mut sc)
        .expect("the rollout resolves");
    ends.last().expect("a truncation state").clone()
}

/// THE RED. Under plain alternation the carrier's activation ends player 1's
/// turn and the truncation catches player 1 with one unit spent. With the rule,
/// the friend INSIDE the reach is activated immediately off the same turn — two
/// of player 1's units are spent before the opponent has replied once.
#[test]
fn a_bearer_hands_the_next_activation_to_a_friend_in_range() {
    let (st, statics) = hand_off_line(CURRENT_RULES_EPOCH);
    let end = truncated(&st, &statics, CURRENT_RULES_EPOCH, 1);
    assert!(
        end.activated[idx(&st, "p1_1_b")],
        "the friend within 12\" was activated immediately, off the bearer's own activation"
    );
    assert!(
        !end.activated[idx(&st, "p1_2_c")],
        "the friend 57.8\" away is out of the rule's reach and must not be handed anything"
    );
}

/// The RANGE guard on its own: with the only in-reach friend already spent, the
/// bearer has nobody legal to hand to — "another friendly unit WITHIN 12\"" — and
/// the far friend stays where it is. The refusal the table calls "none".
#[test]
fn no_hand_off_when_the_only_friend_in_reach_is_spent() {
    let (mut st, statics) = hand_off_line(CURRENT_RULES_EPOCH);
    let b = idx(&st, "p1_1_b");
    st.activated[b] = true;
    let end = truncated(&st, &statics, CURRENT_RULES_EPOCH, 1);
    assert!(
        !end.activated[idx(&st, "p1_2_c")],
        "nobody within reach: the activation ends and the turn passes, as it always did"
    );
}

/// The epoch gate. A record stamped below `EPOCH_7_TABLE_RULES` replays the
/// alternation it was recorded under, carrier or not — the frozen-constant rule,
/// so no earlier corpus moves.
#[test]
fn an_epoch_6_record_never_hands_off() {
    let (st, statics) = hand_off_line(6);
    let end = truncated(&st, &statics, 6, 1);
    assert!(
        !end.activated[idx(&st, "p1_1_b")],
        "epoch 6 knows no hand-off: byte-identical to today's alternation"
    );
}
