use std::{sync::Mutex, thread, time::Duration};

use arboard::Clipboard;
use enigo::{
    Direction::{Click, Press, Release},
    Enigo, Key, Keyboard, Settings,
};

static CLIPBOARD_OWNERSHIP: Mutex<ClipboardOwnership> = Mutex::new(ClipboardOwnership::empty());

#[derive(Clone, Debug)]
pub(crate) struct InsertionOutcome {
    pub status: &'static str,
    pub method: &'static str,
}

trait ClipboardAdapter {
    fn read_text(&mut self) -> Option<String>;
    fn write_text(&mut self, text: &str) -> Result<(), String>;
}

trait PasteAdapter {
    fn is_available(&self) -> bool;
    fn paste(&mut self) -> Result<(), String>;
}

#[derive(Clone, Debug)]
struct ClipboardOwnership {
    session_id: Option<String>,
    inserted_text: Option<String>,
}

impl ClipboardOwnership {
    const fn empty() -> Self {
        Self {
            session_id: None,
            inserted_text: None,
        }
    }

    fn claim(&mut self, session_id: &str, text: &str) {
        self.session_id = Some(session_id.to_owned());
        self.inserted_text = Some(text.to_owned());
    }

    fn still_owns(&self, session_id: &str, current_text: Option<&str>) -> bool {
        self.session_id.as_deref() == Some(session_id)
            && self.inserted_text.as_deref() == current_text
    }

    fn release(&mut self, session_id: &str) {
        if self.session_id.as_deref() == Some(session_id) {
            self.session_id = None;
            self.inserted_text = None;
        }
    }
}

struct SystemClipboard(Clipboard);

impl ClipboardAdapter for SystemClipboard {
    fn read_text(&mut self) -> Option<String> {
        self.0.get_text().ok()
    }

    fn write_text(&mut self, text: &str) -> Result<(), String> {
        self.0
            .set_text(text.to_owned())
            .map_err(|error| error.to_string())
    }
}

struct SystemPaste;

impl PasteAdapter for SystemPaste {
    fn is_available(&self) -> bool {
        automatic_paste_is_available()
    }

    fn paste(&mut self) -> Result<(), String> {
        paste_shortcut()
    }
}

pub(crate) fn insert_with_clipboard(
    session_id: &str,
    text: &str,
    paste_automatically: bool,
    restore_clipboard: bool,
) -> Result<InsertionOutcome, String> {
    let clipboard = Clipboard::new().map_err(|error| error.to_string())?;
    insert_with_adapters(
        session_id,
        text,
        paste_automatically,
        restore_clipboard,
        &mut SystemClipboard(clipboard),
        &mut SystemPaste,
        &CLIPBOARD_OWNERSHIP,
        Duration::from_millis(120),
    )
}

#[allow(clippy::too_many_arguments)]
fn insert_with_adapters<C: ClipboardAdapter, P: PasteAdapter>(
    session_id: &str,
    text: &str,
    paste_automatically: bool,
    restore_clipboard: bool,
    clipboard: &mut C,
    paste: &mut P,
    ownership: &Mutex<ClipboardOwnership>,
    restoration_delay: Duration,
) -> Result<InsertionOutcome, String> {
    let previous_text = restore_clipboard.then(|| clipboard.read_text()).flatten();
    clipboard.write_text(text)?;
    ownership
        .lock()
        .map_err(|_| "clipboard ownership lock poisoned".to_owned())?
        .claim(session_id, text);

    if !paste_automatically {
        return Ok(InsertionOutcome {
            status: "copied",
            method: "clipboard",
        });
    }

    if !paste.is_available() {
        return Ok(InsertionOutcome {
            status: "copied_fallback",
            method: "clipboard",
        });
    }

    if paste.paste().is_err() {
        return Ok(InsertionOutcome {
            status: "copied_fallback",
            method: "clipboard",
        });
    }

    if restore_clipboard {
        if !restoration_delay.is_zero() {
            thread::sleep(restoration_delay);
        }
        let current_text = clipboard.read_text();
        let still_owned = ownership
            .lock()
            .map_err(|_| "clipboard ownership lock poisoned".to_owned())?
            .still_owns(session_id, current_text.as_deref());
        if still_owned {
            if let Some(previous_text) = previous_text {
                clipboard.write_text(&previous_text)?;
            }
            ownership
                .lock()
                .map_err(|_| "clipboard ownership lock poisoned".to_owned())?
                .release(session_id);
        }
    }

    Ok(InsertionOutcome {
        status: "inserted",
        method: "clipboard_paste",
    })
}

#[cfg(target_os = "macos")]
fn automatic_paste_is_available() -> bool {
    #[link(name = "ApplicationServices", kind = "framework")]
    unsafe extern "C" {
        fn AXIsProcessTrusted() -> bool;
    }
    // SAFETY: AXIsProcessTrusted takes no arguments and has no ownership effects.
    unsafe { AXIsProcessTrusted() }
}

#[cfg(not(target_os = "macos"))]
fn automatic_paste_is_available() -> bool {
    true
}

fn paste_shortcut() -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default()).map_err(|error| error.to_string())?;
    #[cfg(target_os = "macos")]
    let modifier = Key::Meta;
    #[cfg(not(target_os = "macos"))]
    let modifier = Key::Control;
    #[cfg(target_os = "macos")]
    let paste_key = Key::Other(9);
    #[cfg(not(target_os = "macos"))]
    let paste_key = Key::Unicode('v');

    enigo
        .key(modifier, Press)
        .map_err(|error| error.to_string())?;
    let click_result = enigo
        .key(paste_key, Click)
        .map_err(|error| error.to_string());
    let release_result = enigo
        .key(modifier, Release)
        .map_err(|error| error.to_string());
    click_result.and(release_result)
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex as SharedMutex};

    use super::*;

    struct FakeClipboard(Arc<SharedMutex<Option<String>>>);

    impl ClipboardAdapter for FakeClipboard {
        fn read_text(&mut self) -> Option<String> {
            self.0.lock().expect("fake clipboard lock").clone()
        }

        fn write_text(&mut self, text: &str) -> Result<(), String> {
            *self.0.lock().expect("fake clipboard lock") = Some(text.to_owned());
            Ok(())
        }
    }

    struct FakePaste {
        available: bool,
        result: Result<(), String>,
        change_clipboard_to: Option<(Arc<SharedMutex<Option<String>>>, String)>,
    }

    impl PasteAdapter for FakePaste {
        fn is_available(&self) -> bool {
            self.available
        }

        fn paste(&mut self) -> Result<(), String> {
            if let Some((clipboard, text)) = &self.change_clipboard_to {
                *clipboard.lock().expect("fake clipboard lock") = Some(text.clone());
            }
            self.result.clone()
        }
    }

    fn ownership() -> Mutex<ClipboardOwnership> {
        Mutex::new(ClipboardOwnership::empty())
    }

    #[test]
    fn restores_the_previous_clipboard_only_while_the_session_owns_it() {
        let shared = Arc::new(SharedMutex::new(Some("before".to_owned())));
        let mut clipboard = FakeClipboard(shared.clone());
        let mut paste = FakePaste {
            available: true,
            result: Ok(()),
            change_clipboard_to: None,
        };
        let outcome = insert_with_adapters(
            "one",
            "dictated",
            true,
            true,
            &mut clipboard,
            &mut paste,
            &ownership(),
            Duration::ZERO,
        )
        .expect("insertion succeeds");

        assert_eq!(outcome.status, "inserted");
        assert_eq!(
            shared.lock().expect("fake clipboard lock").as_deref(),
            Some("before")
        );
    }

    #[test]
    fn preserves_a_newer_user_clipboard_change() {
        let shared = Arc::new(SharedMutex::new(Some("before".to_owned())));
        let mut clipboard = FakeClipboard(shared.clone());
        let mut paste = FakePaste {
            available: true,
            result: Ok(()),
            change_clipboard_to: Some((shared.clone(), "user copied this".to_owned())),
        };
        insert_with_adapters(
            "one",
            "dictated",
            true,
            true,
            &mut clipboard,
            &mut paste,
            &ownership(),
            Duration::ZERO,
        )
        .expect("insertion succeeds");

        assert_eq!(
            shared.lock().expect("fake clipboard lock").as_deref(),
            Some("user copied this")
        );
    }

    #[test]
    fn unavailable_platform_insertion_keeps_text_copied() {
        let shared = Arc::new(SharedMutex::new(Some("before".to_owned())));
        let mut clipboard = FakeClipboard(shared.clone());
        let mut paste = FakePaste {
            available: false,
            result: Ok(()),
            change_clipboard_to: None,
        };
        let outcome = insert_with_adapters(
            "one",
            "dictated",
            true,
            true,
            &mut clipboard,
            &mut paste,
            &ownership(),
            Duration::ZERO,
        )
        .expect("fallback succeeds");

        assert_eq!(outcome.status, "copied_fallback");
        assert_eq!(
            shared.lock().expect("fake clipboard lock").as_deref(),
            Some("dictated")
        );
    }
}
