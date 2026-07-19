use std::collections::HashSet;

/// Coordinates recording ownership independently from post-processing work.
///
/// Only one session may capture audio. Once that session enters finalisation,
/// its recording slot is released so a fast user may begin another recording
/// while the previous session completes transcription and insertion.
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
        self.recording_session = None;
        self.post_processing_sessions.insert(session_id.to_owned());
        Ok(())
    }

    pub fn cancel_recording(&mut self, session_id: &str) -> Result<(), String> {
        if self.recording_session.as_deref() != Some(session_id) {
            return Err("the requested dictation session is not recording".to_owned());
        }
        self.recording_session = None;
        Ok(())
    }

    pub fn complete(&mut self, session_id: &str) -> Result<(), String> {
        if self.post_processing_sessions.remove(session_id) {
            Ok(())
        } else {
            Err("the requested dictation session is not being processed".to_owned())
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
    fn releases_the_recording_slot_during_post_processing() {
        let mut coordinator = DictationCoordinator::default();
        coordinator.reserve_recording("one").expect("first capture");
        coordinator
            .begin_post_processing("one")
            .expect("first finalisation");
        coordinator
            .reserve_recording("two")
            .expect("pipelined capture");
        assert_eq!(coordinator.active_recording(), Some("two"));
        coordinator.complete("one").expect("first completion");
    }

    #[test]
    fn prevents_two_simultaneous_recordings() {
        let mut coordinator = DictationCoordinator::default();
        coordinator.reserve_recording("one").expect("first capture");
        assert!(coordinator.reserve_recording("two").is_err());
    }
}
