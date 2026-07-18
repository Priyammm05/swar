use std::{thread, time::Duration};

use flutter_rust_bridge::frb;

use crate::frb_generated::StreamSink;

const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Returns the version of the native Swar core.
#[frb(sync)]
pub fn get_core_version() -> String {
    CORE_VERSION.to_owned()
}

/// Emits a short counter stream from a Rust worker thread.
pub fn stream_demo_events(sink: StreamSink<u32>) {
    thread::spawn(move || {
        for value in 1..=5 {
            if sink.add(value).is_err() {
                break;
            }
            thread::sleep(Duration::from_millis(250));
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_workspace_version() {
        assert_eq!(get_core_version(), "0.1.0");
    }
}
