use std::fmt;

/// Domain state for one dictation session.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DictationState {
    Idle,
    Preparing,
    Recording,
    Finalising,
    Transcribing,
    Cleaning,
    Enhancing,
    Inserting,
    CopiedFallback,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DictationTransition {
    pub previous: DictationState,
    pub current: DictationState,
    pub reason: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InvalidDictationTransition {
    pub from: DictationState,
    pub to: DictationState,
}

impl fmt::Display for InvalidDictationTransition {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "invalid dictation transition: {:?} -> {:?}",
            self.from, self.to
        )
    }
}

impl std::error::Error for InvalidDictationTransition {}

/// Domain state machine. It has no Flutter, audio, model, or storage dependency.
#[derive(Clone, Debug)]
pub struct DictationStateMachine {
    state: DictationState,
}

impl Default for DictationStateMachine {
    fn default() -> Self {
        Self::new()
    }
}

impl DictationStateMachine {
    pub fn new() -> Self {
        Self {
            state: DictationState::Idle,
        }
    }

    #[cfg(test)]
    pub fn state(&self) -> DictationState {
        self.state
    }

    pub fn transition(
        &mut self,
        next: DictationState,
        reason: impl Into<String>,
    ) -> Result<DictationTransition, InvalidDictationTransition> {
        if !Self::allows(self.state, next) {
            return Err(InvalidDictationTransition {
                from: self.state,
                to: next,
            });
        }
        let transition = DictationTransition {
            previous: self.state,
            current: next,
            reason: reason.into(),
        };
        self.state = next;
        Ok(transition)
    }

    fn allows(from: DictationState, to: DictationState) -> bool {
        use DictationState as S;
        matches!(
            (from, to),
            (S::Idle, S::Preparing)
                | (S::Preparing, S::Recording)
                | (S::Recording, S::Finalising)
                | (S::Finalising, S::Transcribing)
                | (S::Transcribing, S::Cleaning)
                | (S::Cleaning, S::Enhancing)
                | (S::Cleaning, S::Inserting)
                | (S::Enhancing, S::Inserting)
                | (S::Inserting, S::CopiedFallback)
                | (S::Inserting, S::Completed)
                | (S::CopiedFallback, S::Completed)
                | (S::CopiedFallback, S::Failed)
                | (S::Completed, S::Idle)
                | (S::Cancelled, S::Idle)
                | (S::Failed, S::Idle)
                | (S::Preparing, S::Cancelled)
                | (S::Recording, S::Cancelled)
                | (S::Finalising, S::Cancelled)
                | (S::Preparing, S::Failed)
                | (S::Recording, S::Failed)
                | (S::Finalising, S::Failed)
                | (S::Transcribing, S::Failed)
                | (S::Cleaning, S::Failed)
                | (S::Enhancing, S::Failed)
                | (S::Inserting, S::Failed)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_the_complete_clean_dictation_path() {
        let mut machine = DictationStateMachine::new();
        let path = [
            DictationState::Preparing,
            DictationState::Recording,
            DictationState::Finalising,
            DictationState::Transcribing,
            DictationState::Cleaning,
            DictationState::Inserting,
            DictationState::Completed,
            DictationState::Idle,
        ];
        for state in path {
            machine.transition(state, "test").expect("valid transition");
        }
        assert_eq!(machine.state(), DictationState::Idle);
    }

    #[test]
    fn accepts_enhancement_and_clipboard_fallback_paths() {
        let mut machine = DictationStateMachine::new();
        for state in [
            DictationState::Preparing,
            DictationState::Recording,
            DictationState::Finalising,
            DictationState::Transcribing,
            DictationState::Cleaning,
            DictationState::Enhancing,
            DictationState::Inserting,
            DictationState::CopiedFallback,
            DictationState::Completed,
        ] {
            machine.transition(state, "test").expect("valid transition");
        }
    }

    #[test]
    fn rejects_skipping_from_recording_directly_to_insertion() {
        let mut machine = DictationStateMachine::new();
        machine
            .transition(DictationState::Preparing, "shortcut")
            .expect("preparing");
        machine
            .transition(DictationState::Recording, "audio ready")
            .expect("recording");
        let error = machine
            .transition(DictationState::Inserting, "invalid shortcut")
            .expect_err("must reject skipped work");
        assert_eq!(error.from, DictationState::Recording);
        assert_eq!(error.to, DictationState::Inserting);
    }

    #[test]
    fn permits_cancellation_only_before_post_processing() {
        let mut machine = DictationStateMachine::new();
        machine
            .transition(DictationState::Preparing, "shortcut")
            .expect("preparing");
        machine
            .transition(DictationState::Cancelled, "user")
            .expect("cancelled");
        machine
            .transition(DictationState::Idle, "released")
            .expect("idle");
    }
}
