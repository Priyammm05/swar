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

/// One application's share of dictations, for the "Where you dictate" card.
#[derive(Clone, Debug, Default)]
pub struct AppUsage {
    pub name: String,
    pub count: u64,
}

#[derive(Clone, Debug, Default)]
pub struct InsightsSnapshot {
    pub total_words: u64,
    pub total_dictations: u64,
    pub total_speech_duration_ms: u64,
    pub average_words_per_minute: f64,
    pub current_streak_days: u32,
    pub longest_streak_days: u32,
    // --- extended aggregations, all computed from local rows ---
    /// Words in dictations the user later edited (a proxy for "words corrected").
    pub words_corrected: u64,
    /// Sum of custom-vocabulary use counts ("from your dictionary").
    pub dictionary_hits: u64,
    /// Language of the transcript inferred from its script: pure Latin -> English,
    /// pure Devanagari -> Hindi, mixed -> Hinglish. Counts of dictations per class.
    pub language_english: u64,
    pub language_hindi: u64,
    pub language_hinglish: u64,
    /// Top applications by dictation count (already bounded), plus the total
    /// number of distinct applications seen.
    pub app_usage: Vec<AppUsage>,
    pub distinct_app_count: u64,
    /// Per-day dictation counts for the streak heatmap, oldest first, ending today.
    pub daily_activity: Vec<u32>,
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

/// Applies an explicit user correction and optionally feeds the local learning
/// loop. The original audio is never retained.
pub fn correct_dictation(
    id: String,
    corrected_text: String,
    learning_opted_in: bool,
) -> Result<bool, String> {
    storage::correct_dictation(&id, &corrected_text, learning_opted_in)
}
