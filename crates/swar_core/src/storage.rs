use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
};

use directories::ProjectDirs;
use rusqlite::{params, Connection};

use crate::api::history::{HistoryPage, InsightsSnapshot, StoredDictation};

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct StoredVocabularyEntry {
    pub spoken: String,
    pub written: String,
    pub use_count: u32,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct StoredVoiceProfile {
    pub sample_count: u32,
    pub average_sentence_words: f64,
    pub contraction_ratio: f64,
    pub lowercase_start_ratio: f64,
}

static STORE: OnceLock<Mutex<HistoryStore>> = OnceLock::new();

pub(crate) struct NewDictation<'a> {
    pub id: &'a str,
    pub created_at_ms: i64,
    pub raw_text: &'a str,
    pub cleaned_text: &'a str,
    pub final_text: &'a str,
    pub language: &'a str,
    pub writing_mode: &'a str,
    pub source_application: &'a str,
    pub audio_duration_ms: u64,
    pub speech_duration_ms: u64,
    pub processing_duration_ms: u64,
    pub asr_engine: &'a str,
    pub asr_model_id: &'a str,
    pub insertion_status: &'a str,
    pub insertion_method: &'a str,
}

struct HistoryStore {
    connection: Connection,
    path: PathBuf,
}

pub(crate) fn initialize_default_store() -> Result<String, String> {
    let store = store()?;
    let guard = store
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    Ok(guard.path.to_string_lossy().into_owned())
}

pub(crate) fn save_dictation(record: NewDictation<'_>) -> Result<(), String> {
    let store = store()?;
    let guard = store
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard
        .save_dictation(record)
        .map_err(|error| error.to_string())
}

pub(crate) fn load_history_page(
    search_text: &str,
    offset: u32,
    limit: u32,
) -> Result<HistoryPage, String> {
    let store = store()?;
    let guard = store
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard
        .load_history_page(search_text, offset, limit)
        .map_err(|error| error.to_string())
}

pub(crate) fn load_insights_snapshot() -> Result<InsightsSnapshot, String> {
    let store = store()?;
    let guard = store
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard
        .load_insights_snapshot()
        .map_err(|error| error.to_string())
}

pub(crate) fn clear_history() -> Result<(), String> {
    let store = store()?;
    let guard = store
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard.clear().map_err(|error| error.to_string())
}

pub(crate) fn vocabulary_entries() -> Result<Vec<StoredVocabularyEntry>, String> {
    let guard = store()?
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard
        .vocabulary_entries()
        .map_err(|error| error.to_string())
}

pub(crate) fn upsert_vocabulary(spoken: &str, written: &str) -> Result<(), String> {
    let guard = store()?
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard
        .upsert_vocabulary(spoken, written)
        .map_err(|error| error.to_string())
}

pub(crate) fn remove_vocabulary(spoken: &str) -> Result<(), String> {
    let guard = store()?
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard
        .remove_vocabulary(spoken)
        .map_err(|error| error.to_string())
}

pub(crate) fn record_user_edit(original: &str, corrected: &str) -> Result<(), String> {
    let guard = store()?
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard
        .record_user_edit(original, corrected)
        .map_err(|error| error.to_string())
}

pub(crate) fn voice_profile() -> Result<StoredVoiceProfile, String> {
    let guard = store()?
        .lock()
        .map_err(|_| "history store lock poisoned".to_owned())?;
    guard.voice_profile().map_err(|error| error.to_string())
}

fn store() -> Result<&'static Mutex<HistoryStore>, String> {
    if let Some(store) = STORE.get() {
        return Ok(store);
    }

    let path = default_database_path()?;
    let created = HistoryStore::open(&path).map_err(|error| error.to_string())?;
    let _ = STORE.set(Mutex::new(created));
    STORE
        .get()
        .ok_or_else(|| "could not initialize history store".to_owned())
}

fn default_database_path() -> Result<PathBuf, String> {
    let directories = ProjectDirs::from("dev", "Swar", "Swar")
        .ok_or_else(|| "application support directory is unavailable".to_owned())?;
    let directory = directories.data_local_dir();
    fs::create_dir_all(directory).map_err(|error| error.to_string())?;
    Ok(directory.join("swar.sqlite3"))
}

impl HistoryStore {
    fn open(path: &Path) -> rusqlite::Result<Self> {
        let connection = Connection::open(path)?;
        let store = Self {
            connection,
            path: path.to_owned(),
        };
        store.migrate()?;
        Ok(store)
    }

    #[cfg(test)]
    fn open_in_memory() -> rusqlite::Result<Self> {
        let connection = Connection::open_in_memory()?;
        let store = Self {
            connection,
            path: PathBuf::from(":memory:"),
        };
        store.migrate()?;
        Ok(store)
    }

    fn migrate(&self) -> rusqlite::Result<()> {
        self.connection.execute_batch(
            "PRAGMA foreign_keys = ON;
             PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS dictations (
                 id TEXT PRIMARY KEY,
                 created_at INTEGER NOT NULL,
                 updated_at INTEGER NOT NULL,
                 raw_text TEXT NOT NULL,
                 cleaned_text TEXT NOT NULL,
                 final_text TEXT NOT NULL,
                 language_mode TEXT NOT NULL,
                 writing_mode TEXT NOT NULL,
                 source_app_name TEXT NOT NULL,
                 audio_duration_ms INTEGER NOT NULL,
                 speech_duration_ms INTEGER NOT NULL,
                 processing_duration_ms INTEGER NOT NULL,
                 word_count INTEGER NOT NULL,
                 asr_engine TEXT NOT NULL,
                 asr_model_id TEXT NOT NULL,
                 insertion_status TEXT NOT NULL,
                 insertion_method TEXT NOT NULL,
                 is_deleted INTEGER NOT NULL DEFAULT 0
             );
             CREATE VIRTUAL TABLE IF NOT EXISTS dictations_fts USING fts5(
                 final_text,
                 raw_text,
                 source_app_name,
                 content='dictations',
                 content_rowid='rowid'
             );
             CREATE TRIGGER IF NOT EXISTS dictations_ai AFTER INSERT ON dictations BEGIN
                 INSERT INTO dictations_fts(rowid, final_text, raw_text, source_app_name)
                 VALUES (new.rowid, new.final_text, new.raw_text, new.source_app_name);
             END;
             CREATE TRIGGER IF NOT EXISTS dictations_ad AFTER DELETE ON dictations BEGIN
                 INSERT INTO dictations_fts(dictations_fts, rowid, final_text, raw_text, source_app_name)
                 VALUES ('delete', old.rowid, old.final_text, old.raw_text, old.source_app_name);
             END;
             CREATE TRIGGER IF NOT EXISTS dictations_au AFTER UPDATE ON dictations BEGIN
                 INSERT INTO dictations_fts(dictations_fts, rowid, final_text, raw_text, source_app_name)
                 VALUES ('delete', old.rowid, old.final_text, old.raw_text, old.source_app_name);
                 INSERT INTO dictations_fts(rowid, final_text, raw_text, source_app_name)
                 VALUES (new.rowid, new.final_text, new.raw_text, new.source_app_name);
             END;
             CREATE INDEX IF NOT EXISTS dictations_created_at_idx
                 ON dictations(created_at DESC);
             CREATE TABLE IF NOT EXISTS custom_vocabulary (
                 spoken TEXT PRIMARY KEY COLLATE NOCASE,
                 written TEXT NOT NULL,
                 use_count INTEGER NOT NULL DEFAULT 1,
                 updated_at INTEGER NOT NULL
             );
             CREATE TABLE IF NOT EXISTS voice_style_profile (
                 id INTEGER PRIMARY KEY CHECK (id = 1),
                 sample_count INTEGER NOT NULL,
                 average_sentence_words REAL NOT NULL,
                 contraction_ratio REAL NOT NULL,
                 lowercase_start_ratio REAL NOT NULL
             );
             INSERT OR IGNORE INTO voice_style_profile (
                 id, sample_count, average_sentence_words,
                 contraction_ratio, lowercase_start_ratio
             ) VALUES (1, 0, 0, 0, 0);",
        )?;
        Ok(())
    }

    fn save_dictation(&self, record: NewDictation<'_>) -> rusqlite::Result<()> {
        let word_count = record.final_text.split_whitespace().count() as u32;
        self.connection.execute(
            "INSERT OR REPLACE INTO dictations (
                id, created_at, updated_at, raw_text, cleaned_text, final_text,
                language_mode, writing_mode, source_app_name, audio_duration_ms,
                speech_duration_ms, processing_duration_ms, word_count, asr_engine,
                asr_model_id, insertion_status, insertion_method
             ) VALUES (?1, ?2, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11,
                       ?12, ?13, ?14, ?15, ?16)",
            params![
                record.id,
                record.created_at_ms,
                record.raw_text,
                record.cleaned_text,
                record.final_text,
                record.language,
                record.writing_mode,
                record.source_application,
                record.audio_duration_ms,
                record.speech_duration_ms,
                record.processing_duration_ms,
                word_count,
                record.asr_engine,
                record.asr_model_id,
                record.insertion_status,
                record.insertion_method,
            ],
        )?;
        Ok(())
    }

    fn load_history_page(
        &self,
        search_text: &str,
        offset: u32,
        limit: u32,
    ) -> rusqlite::Result<HistoryPage> {
        let trimmed = search_text.trim();
        let total_count: u32 = if trimmed.is_empty() {
            self.connection.query_row(
                "SELECT COUNT(*) FROM dictations
                 WHERE is_deleted = 0
                   AND lower(trim(final_text)) NOT IN ('[blank_audio]', '[blank audio]')",
                [],
                |row| row.get(0),
            )?
        } else {
            self.connection.query_row(
                "SELECT COUNT(*) FROM dictations_fts f
                 JOIN dictations d ON d.rowid = f.rowid
                 WHERE dictations_fts MATCH ?1 AND d.is_deleted = 0
                   AND lower(trim(d.final_text)) NOT IN ('[blank_audio]', '[blank audio]')",
                [fts_query(trimmed)],
                |row| row.get(0),
            )?
        };

        let (sql, query) = if trimmed.is_empty() {
            (
                "SELECT id, created_at, raw_text, final_text, language_mode,
                        writing_mode, source_app_name, word_count, audio_duration_ms,
                        speech_duration_ms, processing_duration_ms, insertion_status
                 FROM dictations WHERE is_deleted = 0
                   AND lower(trim(final_text)) NOT IN ('[blank_audio]', '[blank audio]')
                 ORDER BY created_at DESC LIMIT ?1 OFFSET ?2",
                None,
            )
        } else {
            (
                "SELECT d.id, d.created_at, d.raw_text, d.final_text, d.language_mode,
                        d.writing_mode, d.source_app_name, d.word_count, d.audio_duration_ms,
                        d.speech_duration_ms, d.processing_duration_ms, d.insertion_status
                 FROM dictations_fts f JOIN dictations d ON d.rowid = f.rowid
                 WHERE dictations_fts MATCH ?1 AND d.is_deleted = 0
                   AND lower(trim(d.final_text)) NOT IN ('[blank_audio]', '[blank audio]')
                 ORDER BY d.created_at DESC LIMIT ?2 OFFSET ?3",
                Some(fts_query(trimmed)),
            )
        };

        let mut statement = self.connection.prepare(sql)?;
        let rows = if let Some(query) = query {
            statement.query_map(params![query, limit, offset], map_stored_dictation)?
        } else {
            statement.query_map(params![limit, offset], map_stored_dictation)?
        };
        let records = rows.collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(HistoryPage {
            total_count,
            records,
        })
    }

    fn load_insights_snapshot(&self) -> rusqlite::Result<InsightsSnapshot> {
        let (total_words, total_dictations, speech_ms): (u64, u64, u64) =
            self.connection.query_row(
                "SELECT COALESCE(SUM(word_count), 0), COUNT(*),
                        COALESCE(SUM(speech_duration_ms), 0)
                 FROM dictations WHERE is_deleted = 0
                   AND lower(trim(final_text)) NOT IN ('[blank_audio]', '[blank audio]')",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )?;
        let average_words_per_minute = if speech_ms == 0 {
            0.0
        } else {
            total_words as f64 / (speech_ms as f64 / 60_000.0)
        };
        let streaks = self.streaks()?;
        Ok(InsightsSnapshot {
            total_words,
            total_dictations,
            total_speech_duration_ms: speech_ms,
            average_words_per_minute,
            current_streak_days: streaks.0,
            longest_streak_days: streaks.1,
        })
    }

    fn streaks(&self) -> rusqlite::Result<(u32, u32)> {
        let mut statement = self.connection.prepare(
            "SELECT DISTINCT CAST(julianday(date(
                        created_at / 1000, 'unixepoch', 'localtime'
                    )) AS INTEGER) AS day
             FROM dictations WHERE is_deleted = 0
               AND lower(trim(final_text)) NOT IN ('[blank_audio]', '[blank audio]')
             ORDER BY day DESC",
        )?;
        let days = statement
            .query_map([], |row| row.get::<_, i64>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        if days.is_empty() {
            return Ok((0, 0));
        }

        let today: i64 = self.connection.query_row(
            "SELECT CAST(julianday(date('now', 'localtime')) AS INTEGER)",
            [],
            |row| row.get(0),
        )?;
        let age = today - days[0];
        let mut current = if (0..=1).contains(&age) { 1_u32 } else { 0_u32 };
        let mut longest = 1_u32;
        let mut run = 1_u32;
        for pair in days.windows(2) {
            if pair[0] - pair[1] == 1 {
                run += 1;
                longest = longest.max(run);
            } else {
                run = 1;
            }
        }
        for pair in days.windows(2) {
            if current > 0 && pair[0] - pair[1] == 1 {
                current += 1;
            } else {
                break;
            }
        }
        Ok((current, longest))
    }

    fn clear(&self) -> rusqlite::Result<()> {
        self.connection.execute("DELETE FROM dictations", [])?;
        Ok(())
    }

    fn vocabulary_entries(&self) -> rusqlite::Result<Vec<StoredVocabularyEntry>> {
        let mut statement = self.connection.prepare(
            "SELECT spoken, written, use_count FROM custom_vocabulary
             ORDER BY use_count DESC, spoken ASC",
        )?;
        let entries = statement
            .query_map([], |row| {
                Ok(StoredVocabularyEntry {
                    spoken: row.get(0)?,
                    written: row.get(1)?,
                    use_count: row.get(2)?,
                })
            })?
            .collect();
        entries
    }

    fn upsert_vocabulary(&self, spoken: &str, written: &str) -> rusqlite::Result<()> {
        self.connection.execute(
            "INSERT INTO custom_vocabulary (spoken, written, use_count, updated_at)
             VALUES (?1, ?2, 1, unixepoch('subsec') * 1000)
             ON CONFLICT(spoken) DO UPDATE SET
                 written = excluded.written,
                 use_count = custom_vocabulary.use_count + 1,
                 updated_at = excluded.updated_at",
            params![spoken.trim(), written.trim()],
        )?;
        Ok(())
    }

    fn remove_vocabulary(&self, spoken: &str) -> rusqlite::Result<()> {
        self.connection.execute(
            "DELETE FROM custom_vocabulary WHERE spoken = ?1 COLLATE NOCASE",
            [spoken.trim()],
        )?;
        Ok(())
    }

    fn record_user_edit(&self, original: &str, corrected: &str) -> rusqlite::Result<()> {
        for (spoken, written) in infer_token_replacements(original, corrected) {
            self.upsert_vocabulary(&spoken, &written)?;
        }
        let words = corrected.split_whitespace().count() as f64;
        let tokens = corrected.split_whitespace().collect::<Vec<_>>();
        let contractions = tokens.iter().filter(|token| token.contains('\'')).count() as f64;
        let contraction_ratio = if tokens.is_empty() {
            0.0
        } else {
            contractions / tokens.len() as f64
        };
        let lowercase_start = corrected
            .trim_start()
            .chars()
            .next()
            .is_some_and(|character| character.is_lowercase()) as u8
            as f64;
        self.connection.execute(
            "UPDATE voice_style_profile SET
                 average_sentence_words =
                     ((average_sentence_words * sample_count) + ?1) / (sample_count + 1),
                 contraction_ratio =
                     ((contraction_ratio * sample_count) + ?2) / (sample_count + 1),
                 lowercase_start_ratio =
                     ((lowercase_start_ratio * sample_count) + ?3) / (sample_count + 1),
                 sample_count = sample_count + 1
             WHERE id = 1",
            params![words, contraction_ratio, lowercase_start],
        )?;
        Ok(())
    }

    fn voice_profile(&self) -> rusqlite::Result<StoredVoiceProfile> {
        self.connection.query_row(
            "SELECT sample_count, average_sentence_words,
                    contraction_ratio, lowercase_start_ratio
             FROM voice_style_profile WHERE id = 1",
            [],
            |row| {
                Ok(StoredVoiceProfile {
                    sample_count: row.get(0)?,
                    average_sentence_words: row.get(1)?,
                    contraction_ratio: row.get(2)?,
                    lowercase_start_ratio: row.get(3)?,
                })
            },
        )
    }
}

fn infer_token_replacements(original: &str, corrected: &str) -> Vec<(String, String)> {
    let original = original.split_whitespace().collect::<Vec<_>>();
    let corrected = corrected.split_whitespace().collect::<Vec<_>>();
    if original.len() != corrected.len() || original.len() > 64 {
        return Vec::new();
    }
    original
        .into_iter()
        .zip(corrected)
        .filter_map(|(spoken, written)| {
            let spoken = spoken.trim_matches(|character: char| character.is_ascii_punctuation());
            let written = written.trim_matches(|character: char| character.is_ascii_punctuation());
            (!spoken.is_empty() && !written.is_empty() && !spoken.eq_ignore_ascii_case(written))
                .then(|| (spoken.to_owned(), written.to_owned()))
        })
        .collect()
}

fn map_stored_dictation(row: &rusqlite::Row<'_>) -> rusqlite::Result<StoredDictation> {
    Ok(StoredDictation {
        id: row.get(0)?,
        created_at_ms: row.get(1)?,
        raw_text: row.get(2)?,
        final_text: row.get(3)?,
        language: row.get(4)?,
        writing_mode: row.get(5)?,
        source_application: row.get(6)?,
        word_count: row.get(7)?,
        audio_duration_ms: row.get(8)?,
        speech_duration_ms: row.get(9)?,
        processing_duration_ms: row.get(10)?,
        insertion_status: row.get(11)?,
    })
}

fn fts_query(value: &str) -> String {
    value
        .split_whitespace()
        .map(|token| format!("\"{}\"*", token.replace('"', "\"\"")))
        .collect::<Vec<_>>()
        .join(" AND ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record<'a>(id: &'a str, text: &'a str, created_at_ms: i64) -> NewDictation<'a> {
        NewDictation {
            id,
            created_at_ms,
            raw_text: text,
            cleaned_text: text,
            final_text: text,
            language: "english",
            writing_mode: "clean",
            source_application: "Test",
            audio_duration_ms: 2_000,
            speech_duration_ms: 1_000,
            processing_duration_ms: 200,
            asr_engine: "test",
            asr_model_id: "test",
            insertion_status: "copied",
            insertion_method: "clipboard",
        }
    }

    #[test]
    fn stores_searches_and_aggregates_local_dictations() {
        let store = HistoryStore::open_in_memory().expect("in-memory store");
        store
            .save_dictation(record("one", "Hello Oynix", 1_700_000_000_000))
            .expect("first record");
        store
            .save_dictation(record("two", "Private local voice", 1_700_086_400_000))
            .expect("second record");

        let page = store.load_history_page("Oynix", 0, 10).expect("search");
        assert_eq!(page.total_count, 1);
        assert_eq!(page.records[0].final_text, "Hello Oynix");

        let insights = store.load_insights_snapshot().expect("insights");
        assert_eq!(insights.total_dictations, 2);
        assert_eq!(insights.total_words, 5);
        assert!((insights.average_words_per_minute - 150.0).abs() < f64::EPSILON);
    }

    #[test]
    fn learns_spelling_pairs_and_voice_metrics_from_an_opted_in_edit() {
        let store = HistoryStore::open_in_memory().expect("in-memory store");
        store
            .record_user_edit("hello sewer team", "hello Swar team")
            .expect("edit learned");

        let entries = store.vocabulary_entries().expect("vocabulary");
        assert_eq!(entries[0].spoken, "sewer");
        assert_eq!(entries[0].written, "Swar");
        let profile = store.voice_profile().expect("profile");
        assert_eq!(profile.sample_count, 1);
        assert_eq!(profile.average_sentence_words, 3.0);
        assert_eq!(profile.lowercase_start_ratio, 1.0);
    }
}
