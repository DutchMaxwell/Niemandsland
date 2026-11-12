//! One-core P3: the finished English battle-log line the core writes and the
//! table only shows. Nothing writes one yet; `Tray::say` is the sink.

/// `BattleLog.Category` (battle_log.gd:17) one to one: `as i64` = 0 / 1 / 2.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Category { General, Combat, Movement }

/// One line: the rule that wrote it, its category, its side, the text, an optional detail.
#[derive(Debug, Clone, PartialEq)]
pub struct LogLine {
    pub rule: &'static str,
    pub category: Category,
    pub side: i64,
    pub text: String,
    pub detail: Option<String>,
}
