//! The app lock: a passcode asked for when the app opens.
//!
//! This is a lock on the app's screen, for someone who picks up the device
//! while it is unlocked. It is not what encrypts the data. The vault is
//! sealed with its own key, which the device keeps; this passcode plays no
//! part in that.
//!
//! The passcode itself is never stored. What is stored is the result of
//! running it through Argon2id with a random salt, which cannot be turned
//! back into the passcode and is slow to guess against. The hashing is the
//! `argon2` crate's; nothing here is a home-made primitive.

use argon2::Argon2;
use serde::{Deserialize, Serialize};

use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::seal::random_bytes;
use crate::vault::Vault;

const LOCK: (&str, &[u8]) = ("lock", b"passcode");
const MIN_CHARS: usize = 4;
const MAX_CHARS: usize = 64;
/// How many wrong passcodes in a row erase everything, if the user chose
/// that.
pub(crate) const ERASE_AFTER: u32 = 10;

#[derive(Serialize, Deserialize)]
struct Stored {
    salt: String,
    hash: String,
    /// Wrong passcodes since the last right one. Kept on disk so that
    /// closing the app is not a way to get more tries.
    wrong: u32,
}

fn hash(passcode: &str, salt: &[u8]) -> Result<[u8; 32]> {
    let mut out = [0u8; 32];
    Argon2::default()
        .hash_password_into(passcode.as_bytes(), salt, &mut out)
        .map_err(|_| CoreError::Invalid("that passcode cannot be used".into()))?;
    Ok(out)
}

fn load(vault: &Vault) -> Result<Option<Stored>> {
    match vault.get(LOCK.0, LOCK.1)? {
        None => Ok(None),
        Some(bytes) => serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(|_| CoreError::Corrupt("the saved passcode is unreadable".into())),
    }
}

fn save(vault: &Vault, stored: &Stored) -> Result<()> {
    vault.put(
        LOCK.0,
        LOCK.1,
        &serde_json::to_vec(stored).expect("a passcode record is plain data"),
    )
}

fn matches(stored: &Stored, passcode: &str) -> Result<bool> {
    Ok(hexcode::encode(&hash(passcode, &hexcode::decode(&stored.salt)?)?) == stored.hash)
}

/// Whether a passcode is set, and how many wrong ones there have been.
pub(crate) fn state(vault: &Vault) -> Result<(bool, u32)> {
    Ok(load(vault)?.map_or((false, 0), |stored| (true, stored.wrong)))
}

/// Sets the passcode. If one is set already, `current` must be it.
pub(crate) fn set(vault: &Vault, passcode: &str, current: Option<&str>) -> Result<()> {
    let length = passcode.trim().chars().count();
    if length < MIN_CHARS || passcode.chars().count() > MAX_CHARS {
        return Err(CoreError::Invalid(
            "a passcode must be between 4 and 64 characters".into(),
        ));
    }
    if let Some(stored) = load(vault)? {
        if !matches(&stored, current.unwrap_or_default())? {
            return Err(CoreError::WrongKey);
        }
    }
    let salt = random_bytes::<16>()?;
    save(
        vault,
        &Stored {
            salt: hexcode::encode(salt.as_slice()),
            hash: hexcode::encode(&hash(passcode, salt.as_slice())?),
            wrong: 0,
        },
    )
}

/// Removes the passcode. Needs the passcode.
pub(crate) fn clear(vault: &Vault, passcode: &str) -> Result<()> {
    match load(vault)? {
        None => Ok(()),
        Some(stored) if matches(&stored, passcode)? => vault.delete(LOCK.0, LOCK.1),
        Some(_) => Err(CoreError::WrongKey),
    }
}

/// Tries a passcode. Returns whether it was right and how many wrong ones
/// there have now been in a row.
pub(crate) fn check(vault: &Vault, passcode: &str) -> Result<(bool, u32)> {
    let Some(mut stored) = load(vault)? else {
        return Ok((true, 0));
    };
    let right = matches(&stored, passcode)?;
    stored.wrong = if right {
        0
    } else {
        stored.wrong.saturating_add(1)
    };
    save(vault, &stored)?;
    Ok((right, stored.wrong))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_passcode_itself_is_never_written_down() {
        let dir = tempfile::tempdir().unwrap();
        let vault = Vault::open(dir.path(), &[7u8; 32]).unwrap();
        set(&vault, "correct horse", None).unwrap();
        let stored = String::from_utf8(vault.get(LOCK.0, LOCK.1).unwrap().unwrap()).unwrap();
        assert!(!stored.contains("correct horse"));
        assert!(!stored.contains(&hexcode::encode(b"correct horse")));
    }

    #[test]
    fn the_same_passcode_is_stored_differently_each_time() {
        let dir = tempfile::tempdir().unwrap();
        let vault = Vault::open(dir.path(), &[7u8; 32]).unwrap();
        set(&vault, "2468", None).unwrap();
        let first = vault.get(LOCK.0, LOCK.1).unwrap().unwrap();
        set(&vault, "2468", Some("2468")).unwrap();
        assert_ne!(
            first,
            vault.get(LOCK.0, LOCK.1).unwrap().unwrap(),
            "a fresh salt each time"
        );
        assert!(check(&vault, "2468").unwrap().0);
    }
}
