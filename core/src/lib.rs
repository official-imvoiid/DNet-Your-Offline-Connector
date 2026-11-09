//! Identity, encryption and storage for DNet.
//!
//! This crate has no user interface and no radio code. The Flutter app
//! talks to it through the two C functions at the bottom of this file.

pub mod api;
mod call;
mod chat;
mod codec;
pub mod envelope;
pub mod error;
mod file;
mod hexcode;
pub mod identity;
pub mod keyguard;
mod link;
mod lock;
pub mod photo;
mod place;
mod proof;
mod relay;
pub mod sas;
pub mod seal;
mod shelf;
mod space;
mod stickers;
pub mod vault;
pub mod words;

use std::collections::BTreeMap;
use std::sync::Mutex;

use serde_json::{json, Value};

/// The cores in this process, by number. The app uses number 0 and nothing
/// else. Tests that play several people give each their own.
static CORES: Mutex<BTreeMap<u64, api::Core>> = Mutex::new(BTreeMap::new());

/// Answers one JSON request with one JSON reply. This is the whole of what
/// the app can ask the core to do; see [`api`].
///
/// A request may carry `"core": n` to say which core it is for.
pub fn call(request: &[u8]) -> Vec<u8> {
    let reply = match serde_json::from_slice::<Value>(request) {
        Err(e) => json!({ "err": { "code": "invalid", "message": format!("not JSON: {e}") } }),
        Ok(mut request) => {
            let core = request
                .as_object_mut()
                .and_then(|fields| fields.remove("core"))
                .and_then(|n| n.as_u64())
                .unwrap_or(0);
            // A poisoned lock means an earlier request panicked. The state
            // itself is still sound, so carry on with it.
            let mut cores = CORES
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            cores.entry(core).or_default().handle(request)
        }
    };
    serde_json::to_vec(&reply).expect("a JSON value always encodes")
}

/// The C entry point for [`call`].
///
/// Returns a buffer and writes its length to `reply_len`. The caller must
/// give the buffer back to [`dnet_free`] with that same length.
///
/// # Safety
/// `request` must point to `request_len` readable bytes and `reply_len` to a
/// writable `usize`.
#[no_mangle]
pub unsafe extern "C" fn dnet_call(
    request: *const u8,
    request_len: usize,
    reply_len: *mut usize,
) -> *mut u8 {
    let request = if request.is_null() {
        &[][..]
    } else {
        std::slice::from_raw_parts(request, request_len)
    };
    let reply = call(request).into_boxed_slice();
    *reply_len = reply.len();
    Box::into_raw(reply).cast()
}

/// Frees a buffer returned by [`dnet_call`].
///
/// # Safety
/// `buffer` and `len` must be exactly what one [`dnet_call`] returned, and
/// must not have been freed already.
#[no_mangle]
pub unsafe extern "C" fn dnet_free(buffer: *mut u8, len: usize) {
    if !buffer.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
            buffer, len,
        )));
    }
}
