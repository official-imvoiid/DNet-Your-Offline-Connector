//! Keeping the master key safe while the app is closed.
//!
//! The master key unlocks the vault, so it cannot sit on disk as it is.
//!
//! - On Windows the core wraps it with DPAPI, which ties it to the signed-in
//!   Windows account. Another account on the same PC cannot unwrap it.
//! - On Android the app wraps it with a key held in the Android Keystore and
//!   hands the unwrapped key to the core. The core never stores it there.

use std::path::{Path, PathBuf};

use zeroize::Zeroizing;

use crate::error::{CoreError, Result};

const FILE_NAME: &str = "master.key";

fn file(dir: &Path) -> PathBuf {
    dir.join(FILE_NAME)
}

/// Removes the wrapped key, if this platform keeps one.
pub fn destroy(dir: &Path) -> Result<()> {
    match std::fs::remove_file(file(dir)) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

/// Returns the master key for `dir`, making and wrapping a new one on first
/// use.
#[cfg(windows)]
pub fn load_or_create(dir: &Path) -> Result<Zeroizing<[u8; 32]>> {
    std::fs::create_dir_all(dir)?;
    let path = file(dir);
    if path.exists() {
        let key = dpapi::unprotect(&std::fs::read(&path)?)?;
        let key: [u8; 32] = key
            .as_slice()
            .try_into()
            .map_err(|_| CoreError::KeyGuard("the stored key has the wrong length".into()))?;
        return Ok(Zeroizing::new(key));
    }
    let key = crate::seal::random_bytes::<32>()?;
    // Written to a temporary name and renamed, so a crash cannot leave half
    // a key file behind.
    let temporary = dir.join(format!("{FILE_NAME}.new"));
    std::fs::write(&temporary, dpapi::protect(key.as_slice())?)?;
    std::fs::rename(&temporary, &path)?;
    Ok(key)
}

#[cfg(not(windows))]
pub fn load_or_create(_dir: &Path) -> Result<Zeroizing<[u8; 32]>> {
    Err(CoreError::KeyGuard(
        "on this platform the app must supply the master key".into(),
    ))
}

#[cfg(windows)]
mod dpapi {
    use windows::core::w;
    use windows::Win32::Foundation::{LocalFree, HLOCAL};
    use windows::Win32::Security::Cryptography::{
        CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };
    use zeroize::Zeroizing;

    use crate::error::{CoreError, Result};

    /// Mixed into the wrapping, so another program's DPAPI blob is not
    /// accepted as a DNet key.
    const PURPOSE: &[u8] = b"dnet master key v1";

    fn blob(bytes: &[u8]) -> CRYPT_INTEGER_BLOB {
        CRYPT_INTEGER_BLOB {
            cbData: bytes.len() as u32,
            pbData: bytes.as_ptr() as *mut u8,
        }
    }

    /// Copies a blob Windows allocated, then frees it.
    unsafe fn take(output: CRYPT_INTEGER_BLOB) -> Zeroizing<Vec<u8>> {
        let bytes = std::slice::from_raw_parts(output.pbData, output.cbData as usize);
        let copy = Zeroizing::new(bytes.to_vec());
        std::ptr::write_bytes(output.pbData, 0, output.cbData as usize);
        LocalFree(Some(HLOCAL(output.pbData.cast())));
        copy
    }

    pub fn protect(plain: &[u8]) -> Result<Vec<u8>> {
        let mut output = CRYPT_INTEGER_BLOB::default();
        // SAFETY: the input blobs point at slices that outlive the call,
        // and `output` is filled by Windows and freed in `take`.
        unsafe {
            CryptProtectData(
                &blob(plain),
                w!("DNet"),
                Some(&blob(PURPOSE)),
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
            .map_err(|e| CoreError::KeyGuard(e.message()))?;
            Ok(take(output).to_vec())
        }
    }

    pub fn unprotect(wrapped: &[u8]) -> Result<Zeroizing<Vec<u8>>> {
        let mut output = CRYPT_INTEGER_BLOB::default();
        // SAFETY: as in `protect`.
        unsafe {
            CryptUnprotectData(
                &blob(wrapped),
                None,
                Some(&blob(PURPOSE)),
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
            .map_err(|e| CoreError::KeyGuard(e.message()))?;
            Ok(take(output))
        }
    }
}

#[cfg(all(test, windows))]
mod tests {
    use super::*;

    #[test]
    fn the_key_is_the_same_each_time_it_is_loaded() {
        let dir = tempfile::tempdir().unwrap();
        let first = load_or_create(dir.path()).unwrap();
        let second = load_or_create(dir.path()).unwrap();
        assert_eq!(*first, *second);
    }

    #[test]
    fn the_key_file_does_not_contain_the_key() {
        let dir = tempfile::tempdir().unwrap();
        let key = load_or_create(dir.path()).unwrap();
        let on_disk = std::fs::read(file(dir.path())).unwrap();
        assert!(!on_disk.windows(32).any(|w| w == key.as_slice()));
    }

    #[test]
    fn a_damaged_key_file_is_an_error_not_a_new_key() {
        let dir = tempfile::tempdir().unwrap();
        load_or_create(dir.path()).unwrap();
        std::fs::write(file(dir.path()), b"not a wrapped key").unwrap();
        assert!(matches!(
            load_or_create(dir.path()),
            Err(CoreError::KeyGuard(_))
        ));
    }

    #[test]
    fn destroying_the_key_means_the_next_one_is_new() {
        let dir = tempfile::tempdir().unwrap();
        let first = load_or_create(dir.path()).unwrap();
        destroy(dir.path()).unwrap();
        let second = load_or_create(dir.path()).unwrap();
        assert_ne!(*first, *second);
    }
}
