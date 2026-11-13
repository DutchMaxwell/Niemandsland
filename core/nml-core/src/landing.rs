//! One-core P3: what a volley's landing did to a unit, as data the table
//! replays. Nothing builds one yet; `Tray::land` is the sink.

/// One model a landing touched. `at` is its position BEFORE the landing: a
/// landing never edits a survivor's position, so the exact value is a stable
/// key across removals.
#[derive(Debug, Clone, PartialEq)]
pub struct LandedModel {
    pub at: [f64; 3],
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
}
