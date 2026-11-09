//! Bluetooth for DNet on Windows.
//!
//! Does the same job as `BleRadio.kt` does on Android: it advertises a
//! service so other DNet devices can find this PC and connect, and it looks
//! for that same service and connects to whoever it finds. Either way the
//! result is a numbered link that frames can be sent on in both directions.
//!
//! This library knows nothing about who is at the other end and cannot read
//! what it carries. Proving identity, cutting messages into frames and all
//! encryption happen in the core. The advertisement holds one fixed number
//! that means "DNet is running here" and nothing about the user.
//!
//! The app talks to it the way it talks to the core: one JSON request in,
//! one JSON reply out. Windows cannot call into the app, so what happens on
//! the radio is queued here and the app collects it with `poll`.
//!
//! Not yet verified on devices.

#![cfg(windows)]

mod ble;
mod camera;
mod call_audio;
mod direct;
mod place;
mod screen;
mod voice;

use std::collections::VecDeque;
use std::sync::{Mutex, MutexGuard};

use serde_json::{json, Value};

/// What has happened on the radio that the app has not collected yet.
static EVENTS: Mutex<VecDeque<Value>> = Mutex::new(VecDeque::new());

/// A lock that carries on after a panic elsewhere. Everything guarded here
/// is still sound if a thread died while holding it.
pub(crate) fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

pub(crate) fn emit(event: Value) {
    lock(&EVENTS).push_back(event);
}

pub(crate) fn to_hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(DIGITS[(byte >> 4) as usize] as char);
        out.push(DIGITS[(byte & 15) as usize] as char);
    }
    out
}

fn from_hex(text: &str) -> Option<Vec<u8>> {
    if !text.len().is_multiple_of(2) || !text.is_ascii() {
        return None;
    }
    (0..text.len()).step_by(2).map(|i| u8::from_str_radix(&text[i..i + 2], 16).ok()).collect()
}

fn handle(request: &Value) -> Result<Value, String> {
    let link = || request["link"].as_u64().map(|n| n as u32).ok_or("which link?".to_string());
    let path = || request["path"].as_str().map(str::to_string).ok_or("which file?".to_string());
    match request["op"].as_str() {
        Some("start") => {
            ble::start();
            Ok(Value::Null)
        }
        Some("stop") => {
            ble::stop();
            lock(&EVENTS).clear();
            Ok(Value::Null)
        }
        Some("send") => {
            let frames = request["frames"].as_array().ok_or("no frames")?;
            let frames: Option<Vec<Vec<u8>>> = frames.iter().map(|f| f.as_str().and_then(from_hex)).collect();
            ble::send(link()?, frames.ok_or("a frame is not hex")?);
            Ok(Value::Null)
        }
        Some("drop") => {
            ble::drop_link(link()?);
            Ok(Value::Null)
        }
        Some("poll") => Ok(Value::Array(lock(&EVENTS).drain(..).collect())),
        Some("open_settings") => {
            ble::open_settings();
            Ok(Value::Null)
        }
        // Voice messages. Each answers whether it worked.
        Some("voice_start") => Ok(json!(voice::start(path()?))),
        Some("voice_stop") => Ok(json!(voice::stop())),
        Some("voice_play") => Ok(json!(voice::play(path()?))),
        Some("voice_stop_playing") => {
            voice::stop_playing();
            Ok(Value::Null)
        }
        // Calls: sound as it is spoken. "call_audio" hands over what the
        // microphone heard and takes what to play, both as hex blocks.
        Some("call_audio_start") => {
            let (mic, speaker) = call_audio::start();
            Ok(json!({ "mic": mic, "speaker": speaker }))
        }
        Some("call_audio") => {
            let play = request["play"].as_array().map_or(&[][..], Vec::as_slice);
            let play: Option<Vec<Vec<u8>>> = play.iter().map(|b| b.as_str().and_then(from_hex)).collect();
            let heard = call_audio::trade(play.ok_or("a block is not hex")?);
            Ok(Value::Array(heard.iter().map(|b| Value::String(to_hex(b))).collect()))
        }
        Some("call_audio_stop") => {
            call_audio::stop();
            Ok(Value::Null)
        }
        // Wi-Fi Direct: a group for one phone to join.
        Some("direct_host") => {
            let text = |key: &str| request[key].as_str().map(str::to_string);
            let (Some(network), Some(pass)) = (text("network"), text("pass")) else {
                return Err("which group?".to_string());
            };
            if !direct::sound(&network, &pass) {
                return Err("that is not a group made for this".to_string());
            }
            direct::host(network, pass);
            Ok(json!(true))
        }
        Some("direct_state") => Ok(direct::state()),
        Some("direct_stop") => {
            direct::stop();
            Ok(Value::Null)
        }
        // The camera, only while the user is reading a code with it. Its
        // pictures are collected with `dnet_radio_frame`.
        Some("camera_count") => Ok(json!(camera::count())),
        Some("camera_start") => {
            camera::start();
            Ok(Value::Null)
        }
        Some("camera_state") => Ok(camera::state()),
        Some("camera_stop") => {
            camera::stop();
            Ok(Value::Null)
        }
        // Sharing the screen or one window in a call, only once the user
        // has picked which. Changed squares are collected with
        // "screen_take".
        Some("screen_sources") => Ok(screen::sources()),
        Some("screen_start") => Ok(json!(screen::start(request["source"].as_str().ok_or("share what?")?))),
        Some("screen_state") => Ok(screen::state()),
        Some("screen_rate") => {
            let number = |key: &str| request[key].as_u64().map(|n| n.min(u32::MAX as u64) as u32);
            screen::rate(number("bytes").ok_or("how fast?")?, number("width").ok_or("how wide?")?);
            Ok(Value::Null)
        }
        Some("screen_refresh") => {
            screen::refresh();
            Ok(Value::Null)
        }
        Some("screen_take") => Ok(screen::take()),
        Some("screen_stop") => {
            screen::stop();
            Ok(Value::Null)
        }
        // Where this PC is, only when the user asks to send it.
        Some("location_start") => {
            place::start();
            Ok(Value::Null)
        }
        Some("location_state") => Ok(place::state()),
        Some("location_stop") => {
            place::stop();
            Ok(Value::Null)
        }
        Some("location_settings") => {
            place::open_settings();
            Ok(Value::Null)
        }
        Some("open_map") => {
            let url = request["url"].as_str().ok_or("which place?")?;
            if !place::sound_map(url) {
                return Err("that is not a map of a place".to_string());
            }
            place::open_map(url.to_string());
            Ok(json!(true))
        }
        _ => Err("not a request the radio knows".to_string()),
    }
}

/// Answers one JSON request with one JSON reply: `{"ok": ...}` or
/// `{"err": {"code": "radio", "message": "..."}}`.
fn call(request: &[u8]) -> Vec<u8> {
    let outcome = serde_json::from_slice::<Value>(request).map_err(|e| format!("not JSON: {e}")).and_then(|r| handle(&r));
    let reply = match outcome {
        Ok(value) => json!({ "ok": value }),
        Err(message) => json!({ "err": { "code": "radio", "message": message } }),
    };
    serde_json::to_vec(&reply).expect("a JSON value always encodes")
}

/// The C entry point. Returns a buffer and writes its length to
/// `reply_len`. The caller must give the buffer back to
/// [`dnet_radio_free`] with that same length.
///
/// # Safety
/// `request` must point to `request_len` readable bytes and `reply_len` to
/// a writable `usize`.
#[no_mangle]
pub unsafe extern "C" fn dnet_radio_call(request: *const u8, request_len: usize, reply_len: *mut usize) -> *mut u8 {
    let request = if request.is_null() { &[][..] } else { std::slice::from_raw_parts(request, request_len) };
    let reply = call(request).into_boxed_slice();
    *reply_len = reply.len();
    Box::into_raw(reply).cast()
}

/// Copies the camera's newest picture, as BGRA pixels, into `out`. Writes
/// its width and height to `size[0]` and `size[1]` and returns its number,
/// which goes up with each picture; 0 if there is none. If `cap` is too
/// small nothing is copied, but the size is still written, so the caller
/// can make room and ask again.
///
/// # Safety
/// `out` must point to `cap` writable bytes and `size` to two writable
/// `u32`s.
#[no_mangle]
pub unsafe extern "C" fn dnet_radio_frame(out: *mut u8, cap: usize, size: *mut u32) -> u64 {
    let kept = lock(&camera::FRAME);
    let Some(frame) = kept.as_ref() else {
        return 0;
    };
    if !size.is_null() {
        *size = frame.width;
        *size.add(1) = frame.height;
    }
    if out.is_null() || cap < frame.pixels.len() {
        return 0;
    }
    std::ptr::copy_nonoverlapping(frame.pixels.as_ptr(), out, frame.pixels.len());
    frame.seq
}

/// Frees a buffer returned by [`dnet_radio_call`].
///
/// # Safety
/// `buffer` and `len` must be exactly what one [`dnet_radio_call`]
/// returned, and must not have been freed already.
#[no_mangle]
pub unsafe extern "C" fn dnet_radio_free(buffer: *mut u8, len: usize) {
    if !buffer.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(buffer, len)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ask(request: Value) -> Value {
        serde_json::from_slice(&call(request.to_string().as_bytes())).unwrap()
    }

    #[test]
    fn hex_goes_there_and_back() {
        let bytes = [0u8, 1, 0x7f, 0x80, 0xff];
        assert_eq!(to_hex(&bytes), "00017f80ff");
        assert_eq!(from_hex("00017f80ff"), Some(bytes.to_vec()));
    }

    #[test]
    fn hex_that_is_not_hex_is_refused() {
        assert_eq!(from_hex("abc"), None);
        assert_eq!(from_hex("zz"), None);
        assert_eq!(from_hex("é1"), None);
    }

    #[test]
    fn rubbish_gets_an_error_reply_not_a_crash() {
        assert_eq!(ask(json!({"op": "dance"}))["err"]["code"], "radio");
        assert_eq!(ask(json!({"op": "send", "link": 1, "frames": ["zz"]}))["err"]["code"], "radio");
        assert_eq!(ask(json!({"op": "send", "frames": []}))["err"]["code"], "radio");
        let not_json: Value = serde_json::from_slice(&call(b"{")).unwrap();
        assert_eq!(not_json["err"]["code"], "radio");
    }

    #[test]
    fn sending_on_a_link_that_does_not_exist_is_quietly_nothing() {
        assert_eq!(ask(json!({"op": "send", "link": 99, "frames": ["00"]}))["ok"], Value::Null);
        assert_eq!(ask(json!({"op": "drop", "link": 99}))["ok"], Value::Null);
    }

    // These do not touch the microphone: nothing is recorded by a test.

    #[test]
    fn a_sound_file_that_is_not_there_is_not_played() {
        let nowhere = std::env::temp_dir().join("dnet-no-such-recording.m4a");
        assert_eq!(ask(json!({"op": "voice_play", "path": nowhere}))["ok"], false);
        assert_eq!(ask(json!({"op": "voice_stop_playing"}))["ok"], Value::Null);
    }

    #[test]
    fn stopping_when_nothing_is_being_recorded_says_so() {
        assert_eq!(ask(json!({"op": "voice_stop"}))["ok"], false);
    }

    #[test]
    fn a_voice_request_with_no_file_named_is_refused() {
        assert_eq!(ask(json!({"op": "voice_start"}))["err"]["code"], "radio");
        assert_eq!(ask(json!({"op": "voice_play"}))["err"]["code"], "radio");
    }

    #[test]
    fn with_no_group_made_the_state_says_so() {
        let state = ask(json!({"op": "direct_state"}));
        assert_eq!(state["ok"]["state"], "off");
        assert_eq!(state["ok"]["members"], json!([]));
    }

    #[test]
    fn a_group_that_is_not_one_the_app_made_is_refused() {
        let pass = "k3J9mQ2xT7vBk3J9mQ2x";
        for request in [
            json!({"op": "direct_host", "network": "DIRECT-dN-a1b2c3d4"}),
            json!({"op": "direct_host", "pass": pass}),
            // Somebody's home Wi-Fi is not a group made for this.
            json!({"op": "direct_host", "network": "HomeWifi", "pass": pass}),
            json!({"op": "direct_host", "network": "DIRECT-dN-a1b2c3d4", "pass": "short"}),
            json!({"op": "direct_host", "network": "DIRECT-dN a b", "pass": pass}),
        ] {
            assert!(ask(request.clone())["err"].is_object(), "{request}");
        }
        // Nothing was started by any of them.
        assert_eq!(ask(json!({"op": "direct_state"}))["ok"]["state"], "off");
    }

    #[test]
    fn giving_up_a_group_that_was_never_made_is_quietly_nothing() {
        assert!(ask(json!({"op": "direct_stop"}))["ok"].is_null());
        assert_eq!(ask(json!({"op": "direct_state"}))["ok"]["state"], "off");
    }

    #[test]
    fn events_are_handed_over_once_and_in_order() {
        // No other test here touches the queue.
        emit(json!({"t": "up", "link": 1, "max": 20}));
        emit(json!({"t": "down", "link": 1}));
        let first = ask(json!({"op": "poll"}));
        assert_eq!(first["ok"], json!([{"t": "up", "link": 1, "max": 20}, {"t": "down", "link": 1}]));
        assert_eq!(ask(json!({"op": "poll"}))["ok"], json!([]));
    }
}
