//! Sealing bytes with AES-256-GCM. The cipher is from the `aes-gcm` crate;
//! nothing here is a home-made primitive.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use zeroize::Zeroizing;

use crate::error::{CoreError, Result};

const NONCE_LEN: usize = 12;

/// Fills a buffer from the operating system's random source.
pub fn random_bytes<const N: usize>() -> Result<Zeroizing<[u8; N]>> {
    let mut bytes = Zeroizing::new([0u8; N]);
    getrandom::fill(bytes.as_mut_slice()).map_err(|_| CoreError::Random)?;
    Ok(bytes)
}

/// Encrypts `plaintext` and returns the nonce followed by the ciphertext.
///
/// `context` is not stored. The same context must be given to [`open`], so
/// sealed bytes moved to a different place fail to open.
pub fn seal(key: &[u8; 32], context: &[u8], plaintext: &[u8]) -> Result<Vec<u8>> {
    // A fresh random nonce per record. With 96 bits, a repeat stays
    // negligible for the number of records one device will ever write.
    let nonce = random_bytes::<NONCE_LEN>()?;
    let cipher = Aes256Gcm::new(&Key::<Aes256Gcm>::from(*key));
    let ciphertext = cipher
        .encrypt(
            &Nonce::from(*nonce),
            Payload {
                msg: plaintext,
                aad: context,
            },
        )
        .map_err(|_| CoreError::Storage("encryption failed".into()))?;
    let mut sealed = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    sealed.extend_from_slice(nonce.as_slice());
    sealed.extend_from_slice(&ciphertext);
    Ok(sealed)
}

/// Reverses [`seal`]. Fails with [`CoreError::WrongKey`] if the key or the
/// context is wrong or the bytes were altered. The cipher cannot tell those
/// apart, and neither should an attacker.
pub fn open(key: &[u8; 32], context: &[u8], sealed: &[u8]) -> Result<Zeroizing<Vec<u8>>> {
    if sealed.len() < NONCE_LEN {
        return Err(CoreError::WrongKey);
    }
    let (nonce, ciphertext) = sealed.split_at(NONCE_LEN);
    let nonce: [u8; NONCE_LEN] = nonce.try_into().expect("split at the nonce length");
    let cipher = Aes256Gcm::new(&Key::<Aes256Gcm>::from(*key));
    cipher
        .decrypt(
            &Nonce::from(nonce),
            Payload {
                msg: ciphertext,
                aad: context,
            },
        )
        .map(Zeroizing::new)
        .map_err(|_| CoreError::WrongKey)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn what_is_sealed_opens_again() {
        let sealed = seal(&[7; 32], b"place", b"hello").unwrap();
        assert_eq!(
            open(&[7; 32], b"place", &sealed).unwrap().as_slice(),
            b"hello"
        );
    }

    #[test]
    fn sealing_twice_gives_different_bytes() {
        assert_ne!(
            seal(&[7; 32], b"place", b"hello").unwrap(),
            seal(&[7; 32], b"place", b"hello").unwrap()
        );
    }

    #[test]
    fn another_key_does_not_open_it() {
        let sealed = seal(&[7; 32], b"place", b"hello").unwrap();
        assert!(matches!(
            open(&[8; 32], b"place", &sealed),
            Err(CoreError::WrongKey)
        ));
    }

    #[test]
    fn it_does_not_open_in_another_place() {
        let sealed = seal(&[7; 32], b"place", b"hello").unwrap();
        assert!(matches!(
            open(&[7; 32], b"elsewhere", &sealed),
            Err(CoreError::WrongKey)
        ));
    }

    #[test]
    fn a_changed_byte_is_noticed() {
        let mut sealed = seal(&[7; 32], b"place", b"hello").unwrap();
        let last = sealed.len() - 1;
        sealed[last] ^= 1;
        assert!(matches!(
            open(&[7; 32], b"place", &sealed),
            Err(CoreError::WrongKey)
        ));
    }

    #[test]
    fn too_few_bytes_are_refused() {
        assert!(matches!(
            open(&[7; 32], b"place", &[1, 2, 3]),
            Err(CoreError::WrongKey)
        ));
    }
}
