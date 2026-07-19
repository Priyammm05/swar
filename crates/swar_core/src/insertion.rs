use std::{sync::Mutex, thread, time::Duration};

use arboard::Clipboard;
#[cfg(not(target_os = "macos"))]
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

trait DirectInsertionAdapter {
    fn insert(&mut self, text: &str) -> Result<(), String>;
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

struct SystemDirectInsertion;

impl PasteAdapter for SystemPaste {
    fn is_available(&self) -> bool {
        automatic_paste_is_available()
    }

    fn paste(&mut self) -> Result<(), String> {
        paste_shortcut()
    }
}

impl DirectInsertionAdapter for SystemDirectInsertion {
    fn insert(&mut self, text: &str) -> Result<(), String> {
        direct_insert(text)
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
        &mut SystemDirectInsertion,
        &mut SystemPaste,
        &CLIPBOARD_OWNERSHIP,
        Duration::from_millis(60),
        Duration::from_millis(350),
    )
}

#[allow(clippy::too_many_arguments)]
fn insert_with_adapters<C: ClipboardAdapter, D: DirectInsertionAdapter, P: PasteAdapter>(
    session_id: &str,
    text: &str,
    paste_automatically: bool,
    restore_clipboard: bool,
    clipboard: &mut C,
    direct: &mut D,
    paste: &mut P,
    ownership: &Mutex<ClipboardOwnership>,
    pasteboard_settle_delay: Duration,
    restoration_delay: Duration,
) -> Result<InsertionOutcome, String> {
    if paste_automatically && direct.insert(text).is_ok() {
        return Ok(InsertionOutcome {
            status: "inserted",
            method: "native_direct",
        });
    }
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

    // macOS and Electron-backed text fields may observe the pasteboard on a
    // later run-loop turn. Give the new owner a brief moment to publish before
    // dispatching Command+V.
    if !pasteboard_settle_delay.is_zero() {
        thread::sleep(pasteboard_settle_delay);
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
fn direct_insert(text: &str) -> Result<(), String> {
    use std::{ffi::c_void, ptr};

    type AXUIElementRef = *const c_void;
    type CFTypeRef = *const c_void;
    type CFStringRef = *const c_void;
    #[link(name = "ApplicationServices", kind = "framework")]
    unsafe extern "C" {
        fn AXIsProcessTrusted() -> bool;
        fn AXUIElementCreateSystemWide() -> AXUIElementRef;
        fn AXUIElementCopyAttributeValue(
            element: AXUIElementRef,
            attribute: CFStringRef,
            value: *mut CFTypeRef,
        ) -> i32;
        fn AXUIElementSetAttributeValue(
            element: AXUIElementRef,
            attribute: CFStringRef,
            value: CFTypeRef,
        ) -> i32;
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        fn CFStringCreateWithBytes(
            allocator: *const c_void,
            bytes: *const u8,
            count: isize,
            encoding: u32,
            external_representation: bool,
        ) -> CFStringRef;
        fn CFRelease(value: CFTypeRef);
    }

    const UTF8: u32 = 0x0800_0100;
    // SAFETY: every CoreFoundation object created or copied here is released on
    // all paths after use, and the UTF-8 byte slice remains valid for the call.
    unsafe {
        if !AXIsProcessTrusted() {
            return Err("accessibility insertion is unavailable".to_owned());
        }
        let system = AXUIElementCreateSystemWide();
        if system.is_null() {
            return Err("the system accessibility element is unavailable".to_owned());
        }
        let focused_attribute =
            CFStringCreateWithBytes(ptr::null(), b"AXFocusedUIElement".as_ptr(), 18, UTF8, false);
        let selected_text_attribute =
            CFStringCreateWithBytes(ptr::null(), b"AXSelectedText".as_ptr(), 14, UTF8, false);
        if focused_attribute.is_null() || selected_text_attribute.is_null() {
            if !focused_attribute.is_null() {
                CFRelease(focused_attribute);
            }
            if !selected_text_attribute.is_null() {
                CFRelease(selected_text_attribute);
            }
            CFRelease(system);
            return Err("accessibility attributes are unavailable".to_owned());
        }
        let mut focused: CFTypeRef = ptr::null();
        let focused_result = AXUIElementCopyAttributeValue(system, focused_attribute, &mut focused);
        if focused_result != 0 || focused.is_null() {
            CFRelease(focused_attribute);
            CFRelease(selected_text_attribute);
            CFRelease(system);
            return Err("the focused text control is unavailable".to_owned());
        }
        let value = CFStringCreateWithBytes(
            ptr::null(),
            text.as_bytes().as_ptr(),
            text.len() as isize,
            UTF8,
            false,
        );
        if value.is_null() {
            CFRelease(focused_attribute);
            CFRelease(selected_text_attribute);
            CFRelease(focused);
            CFRelease(system);
            return Err("the dictated text could not be encoded".to_owned());
        }
        let result = AXUIElementSetAttributeValue(focused, selected_text_attribute, value);
        CFRelease(value);
        CFRelease(focused_attribute);
        CFRelease(selected_text_attribute);
        CFRelease(focused);
        CFRelease(system);
        (result == 0)
            .then_some(())
            .ok_or_else(|| "the focused control rejected direct insertion".to_owned())
    }
}

#[cfg(target_os = "windows")]
fn direct_insert(text: &str) -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default()).map_err(|error| error.to_string())?;
    enigo.text(text).map_err(|error| error.to_string())
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn direct_insert(_text: &str) -> Result<(), String> {
    Err("native direct insertion is unavailable".to_owned())
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

#[cfg(target_os = "macos")]
fn paste_shortcut() -> Result<(), String> {
    use std::ffi::c_void;

    type CFTypeRef = *const c_void;
    type CGEventSourceRef = *const c_void;
    type CGEventRef = *const c_void;

    #[link(name = "ApplicationServices", kind = "framework")]
    unsafe extern "C" {
        fn CGEventSourceCreate(state_id: i32) -> CGEventSourceRef;
        fn CGEventCreateKeyboardEvent(
            source: CGEventSourceRef,
            virtual_key: u16,
            key_down: bool,
        ) -> CGEventRef;
        fn CGEventSetFlags(event: CGEventRef, flags: u64);
        fn CGEventPost(tap: u32, event: CGEventRef);
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        fn CFRelease(value: CFTypeRef);
    }

    const PRIVATE_EVENT_SOURCE: i32 = -1;
    const HID_EVENT_TAP: u32 = 0;
    const V_KEY_CODE: u16 = 9;
    const COMMAND_FLAG: u64 = 1 << 20;

    // A private event source prevents a physically held Option shortcut from
    // leaking into the synthetic paste chord as Command+Option+V.
    unsafe {
        let source = CGEventSourceCreate(PRIVATE_EVENT_SOURCE);
        if source.is_null() {
            return Err("the macOS keyboard event source is unavailable".to_owned());
        }
        let key_down = CGEventCreateKeyboardEvent(source, V_KEY_CODE, true);
        let key_up = CGEventCreateKeyboardEvent(source, V_KEY_CODE, false);
        if key_down.is_null() || key_up.is_null() {
            if !key_down.is_null() {
                CFRelease(key_down);
            }
            if !key_up.is_null() {
                CFRelease(key_up);
            }
            CFRelease(source);
            return Err("the macOS paste events could not be created".to_owned());
        }
        CGEventSetFlags(key_down, COMMAND_FLAG);
        CGEventSetFlags(key_up, COMMAND_FLAG);
        CGEventPost(HID_EVENT_TAP, key_down);
        thread::sleep(Duration::from_millis(12));
        CGEventPost(HID_EVENT_TAP, key_up);
        CFRelease(key_down);
        CFRelease(key_up);
        CFRelease(source);
    }
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn paste_shortcut() -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default()).map_err(|error| error.to_string())?;
    let modifier = Key::Control;
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

    struct FakeDirectInsertion(Result<(), String>);

    impl DirectInsertionAdapter for FakeDirectInsertion {
        fn insert(&mut self, _text: &str) -> Result<(), String> {
            self.0.clone()
        }
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
            &mut FakeDirectInsertion(Err("unavailable".to_owned())),
            &mut paste,
            &ownership(),
            Duration::ZERO,
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
            &mut FakeDirectInsertion(Err("unavailable".to_owned())),
            &mut paste,
            &ownership(),
            Duration::ZERO,
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
            &mut FakeDirectInsertion(Err("unavailable".to_owned())),
            &mut paste,
            &ownership(),
            Duration::ZERO,
            Duration::ZERO,
        )
        .expect("fallback succeeds");

        assert_eq!(outcome.status, "copied_fallback");
        assert_eq!(
            shared.lock().expect("fake clipboard lock").as_deref(),
            Some("dictated")
        );
    }

    #[test]
    fn direct_insertion_does_not_touch_the_clipboard() {
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
            &mut FakeDirectInsertion(Ok(())),
            &mut paste,
            &ownership(),
            Duration::ZERO,
            Duration::ZERO,
        )
        .expect("direct insertion succeeds");
        assert_eq!(outcome.method, "native_direct");
        assert_eq!(
            shared.lock().expect("fake clipboard lock").as_deref(),
            Some("before")
        );
    }
}
