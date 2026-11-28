//! One-core P3: what a volley's landing did to a unit, as data the table
//! replays. Nothing builds one yet; `Tray::land` is the sink.

/// One model a landing touched. `slot` is its identity: the index it had in its unit's model list when the activation
/// was captured, whatever earlier landings removed since (P4.0-1; the unit is `Landing::unit`). `at` is its position
/// BEFORE the landing (a landing never edits a survivor's position): the table's cross-check of `slot`, no longer its key.
#[derive(Debug, Clone, PartialEq)]
pub struct LandedModel {
    pub at: [f64; 3],
    pub slot: usize,
    pub wounds_left: i64,
    pub dead: bool,
}

/// One landing on one unit: the unit index and the models it touched. `loss_line`: the core said this
/// landing's casualty line itself ("X loses ..." / "X destroyed", a volley's landing, step 25), so the
/// table's removal funnel must not say it again (step 27); a Dangerous landing says none (false).
#[derive(Debug, Clone, PartialEq)]
pub struct Landing {
    pub unit: usize,
    pub models: Vec<LandedModel>,
    pub loss_line: bool,
    /// H-8 (Plan H): a pre-attack beat MOVED the unit (Mind Control's push): its living models' positions after the move, in
    /// capture slot order with the dead left out. The table moves them before any later landing (whose `at` is post-move).
    /// Empty for every wound / casualty landing.
    pub moved_to: Vec<[f64; 3]>,
}

/// LANDING-INVARIANT: the table lands a unit's wounds and losses ONLY from the step landings (the activation's final delta
/// carries none), so the landings replayed onto the activation's start must give the core's end state. Replays them per unit
/// by capture slot (a landing names each model by the slot it had at the start: its wounds left, or dead) and returns one line
/// per unit whose living models or wound total then differ from `end` - a landing the core never emitted. Empty = covered.
pub fn landing_gaps(start: &crate::state::State, end: &crate::state::State, landings: &[Landing]) -> Vec<String> {
    let mut out = Vec::new();
    for u in 0..start.wounds.len().min(end.wounds.len()) {
        let mut slots: Vec<Option<i64>> = start.wounds[u].iter().map(|&w| Some(w)).collect();
        for m in landings.iter().filter(|l| l.unit == u).flat_map(|l| &l.models) {
            if let Some(s) = slots.get_mut(m.slot) {
                *s = if m.dead { None } else { Some(m.wounds_left) };
            }
        }
        let landed = (slots.iter().flatten().count(), slots.iter().flatten().sum::<i64>());
        let core = (end.wounds[u].len(), end.wounds[u].iter().sum::<i64>());
        if landed != core {
            let key = end.roster.keys.get(u).cloned().unwrap_or_default();
            out.push(format!("{key}: the landings leave {} models / {} wounds, the core ends at {} / {}", landed.0, landed.1, core.0, core.1));
        }
    }
    out
}
