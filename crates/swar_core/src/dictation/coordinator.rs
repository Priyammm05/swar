use std::collections::HashSet;

/// Coordinates recording ownership independently from post-processing work.
///
/// Only one session may own the dictation pipeline. The slot remains reserved
/// through transcription, cleanup, insertion, and the history transaction so
/// a shortcut press can never overlap or reorder user-visible output.
#[derive(Default)]
pub struct DictationCoordinator {
    recording_session: Option<String>,
    post_processing_sessions: HashSet<String>,
}

impl DictationCoordinator {
    pub fn reserve_recording(&mut self, session_id: &str) -> Result<(), String> {
        if self.recording_session.is_some() {
            return Err("another dictation session is already recording".to_owned());
        }
        self.recording_session = Some(session_id.to_owned());
        Ok(())
    }

    pub fn begin_post_processing(&mut self, session_id: &str) -> Result<(), String> {
        if self.recording_session.as_deref() != Some(session_id) {
            return Err("the requested dictation session is not recording".to_owned());
        }
        self.post_processing_sessions.insert(session_id.to_owned());
        Ok(())
    }

    /// Releases a session from the pipeline regardless of the phase it is in.
    ///
    /// This is the single release path for both a reserved recording and an
    /// in-flight post-processing session. It is infallible and idempotent so an
    /// RAII guard can call it on any exit path — including a panic between
    /// reservation and completion — and always free the recording slot instead
    /// of wedging every future dictation until the app is relaunched.
    pub fn abandon(&mut self, session_id: &str) {
        self.post_processing_sessions.remove(session_id);
        if self.recording_session.as_deref() == Some(session_id) {
            self.recording_session = None;
        }
    }

    #[cfg(test)]
    fn active_recording(&self) -> Option<&str> {
        self.recording_session.as_deref()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_a_new_recording_until_post_processing_completes() {
        let mut coordinator = DictationCoordinator::default();
        coordinator.reserve_recording("one").expect("first capture");
        coordinator
            .begin_post_processing("one")
            .expect("first finalisation");
        assert!(coordinator.reserve_recording("two").is_err());
        assert_eq!(coordinator.active_recording(), Some("one"));
        coordinator.abandon("one");
        coordinator
            .reserve_recording("two")
            .expect("next capture after completed insertion");
    }

    #[test]
    fn prevents_two_simultaneous_recordings() {
        let mut coordinator = DictationCoordinator::default();
        coordinator.reserve_recording("one").expect("first capture");
        assert!(coordinator.reserve_recording("two").is_err());
    }

    #[test]
    fn abandon_frees_the_slot_from_any_phase() {
        let mut coordinator = DictationCoordinator::default();
        coordinator.reserve_recording("one").expect("reserve");
        coordinator
            .begin_post_processing("one")
            .expect("post-processing");
        // Simulates a panic/early return between reservation and completion.
        coordinator.abandon("one");
        assert_eq!(coordinator.active_recording(), None);
        coordinator
            .reserve_recording("two")
            .expect("a new session must start after an abandoned one");
    }

    #[test]
    fn abandon_is_idempotent_and_ignores_unknown_sessions() {
        let mut coordinator = DictationCoordinator::default();
        coordinator.reserve_recording("one").expect("reserve");
        coordinator.abandon("someone-else");
        assert_eq!(coordinator.active_recording(), Some("one"));
        coordinator.abandon("one");
        coordinator.abandon("one");
        assert_eq!(coordinator.active_recording(), None);
    }
}
