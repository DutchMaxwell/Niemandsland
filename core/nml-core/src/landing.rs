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

/// One landing on one unit: the unit index and the models it touched.
#[derive(Debug, Clone, PartialEq)]
pub struct Landing {
    pub unit: usize,
    pub models: Vec<LandedModel>,
}
