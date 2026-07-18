use std::{thread, time::Duration};

use arboard::Clipboard;
use enigo::{
    Direction::{Click, Press, Release},
    Enigo, Key, Keyboard, Settings,
};

#[derive(Clone, Debug)]
pub(crate) struct InsertionOutcome {
    pub status: &'static str,
    pub method: &'static str,
}

pub(crate) fn insert_with_clipboard(
    text: &str,
    paste_automatically: bool,
    restore_clipboard: bool,
) -> Result<InsertionOutcome, String> {
    let mut clipboard = Clipboard::new().map_err(|error| error.to_string())?;
    let previous_text = restore_clipboard
        .then(|| clipboard.get_text().ok())
        .flatten();
    clipboard
        .set_text(text.to_owned())
        .map_err(|error| error.to_string())?;

    if !paste_automatically {
        return Ok(InsertionOutcome {
            status: "copied",
            method: "clipboard",
        });
    }

    // Never attempt synthetic keyboard input without Accessibility approval.
    // On macOS that failed attempt can trigger another application's TCC prompt
    // when Swar was launched from an IDE or terminal.
    if !automatic_paste_is_available() {
        return Ok(InsertionOutcome {
            status: "copied_fallback",
            method: "clipboard",
        });
    }

    let paste_result = paste_shortcut();
    if paste_result.is_ok() && restore_clipboard {
        thread::sleep(Duration::from_millis(120));
        if let Some(previous_text) = previous_text {
            let _ = clipboard.set_text(previous_text);
        }
    }

    match paste_result {
        Ok(()) => Ok(InsertionOutcome {
            status: "inserted",
            method: "clipboard_paste",
        }),
        Err(_) => Ok(InsertionOutcome {
            status: "copied_fallback",
            method: "clipboard",
        }),
    }
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

    enigo
        .key(modifier, Press)
        .map_err(|error| error.to_string())?;
    let click_result = enigo
        .key(Key::Unicode('v'), Click)
        .map_err(|error| error.to_string());
    let release_result = enigo
        .key(modifier, Release)
        .map_err(|error| error.to_string());
    click_result.and(release_result)
}
