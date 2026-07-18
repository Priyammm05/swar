use crate::storage;

#[derive(Clone, Debug)]
pub struct StoredDictation {
    pub id: String,
    pub created_at_ms: i64,
    pub raw_text: String,
    pub final_text: String,
    pub language: String,
    pub writing_mode: String,
    pub source_application: String,
    pub word_count: u32,
    pub audio_duration_ms: u64,
    pub speech_duration_ms: u64,
    pub processing_duration_ms: u64,
    pub insertion_status: String,
}

#[derive(Clone, Debug)]
pub struct HistoryPage {
    pub total_count: u32,
    pub records: Vec<StoredDictation>,
}

#[derive(Clone, Debug, Default)]
pub struct InsightsSnapshot {
    pub total_words: u64,
    pub total_dictations: u64,
    pub total_speech_duration_ms: u64,
    pub average_words_per_minute: f64,
    pub current_streak_days: u32,
    pub longest_streak_days: u32,
}

/// Initializes Swar's private SQLite store under the OS application-support directory.
pub fn initialize_local_store() -> Result<String, String> {
    storage::initialize_default_store()
}

/// Returns one bounded history page. Search is executed by SQLite FTS, never in Dart.
pub fn load_history_page(
    search_text: String,
    offset: u32,
    limit: u32,
) -> Result<HistoryPage, String> {
    storage::load_history_page(&search_text, offset, limit.min(100))
}

/// Returns pre-aggregated local insights without exposing transcript text.
pub fn load_insights_snapshot() -> Result<InsightsSnapshot, String> {
    storage::load_insights_snapshot()
}

/// Deletes local history and metrics. Model files and personal settings are untouched.
pub fn clear_local_history() -> Result<(), String> {
    storage::clear_history()
}
