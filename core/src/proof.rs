//! What the core keeps as proof: the stamp on the user's own identity, and
//! how each person the user verified was verified.
//!
//! The stamp is worked out a slice at a time, so the app can show how far
//! it has got and stay responsive. The work so far is kept, so a slice cut
//! short by the app closing is not lost.
//!
//! The welcome screen starts the work before the user's name is saved: the
//! key is made as a draft, stamped, and then becomes the identity. That way
//! nobody is shown as present until their stamp is ready.

use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use zeroize::Zeroizing;

use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::identity::{
    check_stamp, encode_stamp, search_stamp, IdentitySecret, STAMP_BITS, STAMP_PARTS,
};
use crate::vault::Vault;

const STAMP: (&str, &[u8]) = ("identity", b"stamp");
const DRAFT: (&str, &[u8]) = ("identity", b"draft");
/// How each person was verified, by their signing key.
const PROOFS: &str = "proofs";

/// Tries one thread makes before it looks at the clock again.
const TRIES_PER_LOOK: u32 = 4096;

/// How long making an identity works on its stamp before it returns, when
/// the stamp was not made ahead. A release build gets a start and the app
/// finishes it. A debug build's stamp is a token amount of work and is
/// always finished here, however busy the machine, so a test never meets
/// a half-made one.
pub const FIRST_SLICE: Duration = if cfg!(debug_assertions) {
    Duration::from_secs(60)
} else {
    Duration::from_millis(250)
};

/// The work on a stamp so far.
#[derive(Serialize, Deserialize)]
struct Work {
    /// The signing key it is for, hex. Work for any other key is thrown
    /// away.
    key: String,
    bits: u8,
    /// The number found for each part, once it is.
    found: Vec<Option<u32>>,
    /// Where the search for each part has got to.
    next: Vec<u32>,
}

impl Work {
    fn new(key: &str) -> Self {
        Self {
            key: key.to_string(),
            bits: STAMP_BITS,
            found: vec![None; STAMP_PARTS],
            next: vec![0; STAMP_PARTS],
        }
    }

    fn done(&self) -> usize {
        self.found.iter().flatten().count()
    }

    fn stamp(&self) -> Option<Vec<u8>> {
        let nonces: Vec<u32> = self.found.iter().copied().collect::<Option<_>>()?;
        Some(encode_stamp(self.bits, &nonces.try_into().ok()?))
    }
}

fn load(vault: &Vault, key: &str) -> Result<Work> {
    let kept = vault
        .get(STAMP.0, STAMP.1)?
        .and_then(|bytes| serde_json::from_slice::<Work>(&bytes).ok())
        .filter(|work| {
            work.key == key
                && work.bits >= STAMP_BITS
                && work.found.len() == STAMP_PARTS
                && work.next.len() == STAMP_PARTS
        });
    Ok(kept.unwrap_or_else(|| Work::new(key)))
}

/// The user's finished stamp, hex, if the work for `signing_key` is done.
pub fn my_stamp(vault: &Vault, signing_key: &[u8]) -> Result<Option<String>> {
    let work = load(vault, &hexcode::encode(signing_key))?;
    Ok(work.stamp().map(|stamp| hexcode::encode(&stamp)))
}

/// Whether a stranger's stamp, as it came in their request, is enough.
pub fn stamp_sound(signing_key: &[u8], stamp: Option<&str>) -> bool {
    stamp
        .and_then(|hex| hexcode::decode(hex).ok())
        .is_some_and(|bytes| check_stamp(signing_key, &bytes, STAMP_BITS))
}

/// Works on the stamp for `signing_key` until it is done, `max_tries`
/// numbers have been tried, or `time` has passed, whichever is first.
///
/// Parts are worked on side by side, one to a thread, up to four threads.
pub fn stamp_work(vault: &Vault, signing_key: &[u8], time: Duration, max_tries: u64) -> Result<Value> {
    let mut work = load(vault, &hexcode::encode(signing_key))?;
    let until = Instant::now() + time;
    let threads = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1)
        .clamp(1, 4);
    let mut tried: u64 = 0;
    while work.done() < STAMP_PARTS && tried < max_tries && Instant::now() < until {
        let open: Vec<usize> = (0..STAMP_PARTS)
            .filter(|&part| work.found[part].is_none())
            .take(threads)
            .collect();
        // Each thread gets its share of what is left to try.
        let share = ((max_tries - tried) / open.len() as u64).clamp(1, u64::from(u32::MAX)) as u32;
        let bits = work.bits;
        let outcomes: Vec<(usize, Option<u32>, u32)> = std::thread::scope(|scope| {
            let running: Vec<_> = open
                .iter()
                .map(|&part| {
                    let from = work.next[part];
                    scope.spawn(move || search_part(signing_key, part, from, share, bits, until))
                })
                .collect();
            running
                .into_iter()
                .zip(&open)
                .map(|(thread, &part)| {
                    let (found, tries) = thread.join().unwrap_or((None, 0));
                    (part, found, tries)
                })
                .collect()
        });
        for (part, found, tries) in outcomes {
            tried += u64::from(tries);
            work.next[part] = work.next[part].saturating_add(tries);
            if found.is_some() {
                work.found[part] = found;
            }
        }
        // Every number for a part tried and none found. With 2^32 numbers
        // and about 2^20 needed this does not happen, but it must not loop.
        if work
            .next
            .iter()
            .zip(&work.found)
            .any(|(next, found)| found.is_none() && *next == u32::MAX)
        {
            return Err(CoreError::Invalid("the stamp could not be made".into()));
        }
    }
    vault.put(
        STAMP.0,
        STAMP.1,
        &serde_json::to_vec(&work).expect("stamp work is plain data"),
    )?;
    Ok(json!({
        "found": work.done(),
        "parts": STAMP_PARTS,
        "done": work.done() == STAMP_PARTS,
    }))
}

/// Searches one part, looking at the clock now and then. Returns what was
/// found, if anything, and how many numbers were tried.
fn search_part(key: &[u8], part: usize, from: u32, tries: u32, bits: u8, until: Instant) -> (Option<u32>, u32) {
    let mut done = 0u32;
    while done < tries {
        let step = TRIES_PER_LOOK.min(tries - done);
        let at = from.saturating_add(done);
        if let Some(found) = search_stamp(key, part as u8, at, step, bits) {
            return (Some(found), found - from + 1);
        }
        done += step;
        if at.saturating_add(step) == u32::MAX || Instant::now() >= until {
            break;
        }
    }
    (None, done)
}

/// The key made ahead of the identity, made now if there is none yet.
pub fn draft(vault: &Vault) -> Result<IdentitySecret> {
    if let Some(bytes) = vault.get(DRAFT.0, DRAFT.1)? {
        return IdentitySecret::from_bytes(&Zeroizing::new(bytes));
    }
    let secret = IdentitySecret::generate()?;
    vault.put(DRAFT.0, DRAFT.1, &secret.to_bytes())?;
    Ok(secret)
}

/// The draft, for becoming the identity. Forgotten here once it is read.
pub fn take_draft(vault: &Vault) -> Result<Option<IdentitySecret>> {
    let Some(bytes) = vault.get(DRAFT.0, DRAFT.1)? else {
        return Ok(None);
    };
    let secret = IdentitySecret::from_bytes(&Zeroizing::new(bytes))?;
    vault.delete(DRAFT.0, DRAFT.1)?;
    Ok(Some(secret))
}

/// The ways a person can be verified. The first two need the other device
/// in the user's hand or in front of their camera; the other two need the
/// user to compare something themselves. None of them trusts the radio.
pub const METHODS: [&str; 4] = ["tap", "qr", "words", "code"];

#[derive(Serialize, Deserialize)]
struct Proof {
    how: String,
    at: u64,
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Notes how a person was, or is about to be, verified. A request made by
/// scanning or tapping is noted when it is sent; it counts once they
/// accept. A later way replaces an earlier one.
pub fn record(vault: &Vault, key: &str, how: &str) -> Result<()> {
    if !METHODS.contains(&how) {
        return Err(CoreError::Invalid(format!("{how} is not a way to verify")));
    }
    let proof = Proof {
        how: how.to_string(),
        at: now(),
    };
    vault.put(
        PROOFS,
        key.as_bytes(),
        &serde_json::to_vec(&proof).expect("a proof is plain data"),
    )
}

/// How a person was verified and when, in seconds since 1970, if noted.
pub fn lookup(vault: &Vault, key: &str) -> Result<Option<(String, u64)>> {
    Ok(vault
        .get(PROOFS, key.as_bytes())?
        .and_then(|bytes| serde_json::from_slice::<Proof>(&bytes).ok())
        .map(|proof| (proof.how, proof.at)))
}
