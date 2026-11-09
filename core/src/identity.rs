//! A person's identity: two key pairs made on the device.
//!
//! - An Ed25519 signing key. This is who the person is.
//! - An X-Wing encryption key. X-Wing joins X25519 with ML-KEM-768, so what
//!   is sealed to it stays private unless both are broken. ML-KEM is the
//!   part a quantum computer is not known to break.
//!
//! The signing key signs the encryption key, so nobody can pair someone's
//! identity with a key of their own.
//!
//! There is no account and no server. The secret half never leaves the
//! device.

use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hpke::kem::XWing;
use hpke::{Deserializable, Kem, Serializable};
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::error::{CoreError, Result};
use crate::seal::random_bytes;
use crate::words::{code_words, unix_now, window_of};

pub(crate) type EncryptionPrivate = <XWing as Kem>::PrivateKey;
pub(crate) type EncryptionPublic = <XWing as Kem>::PublicKey;

pub const SIGNING_LEN: usize = 32;
pub const ENCRYPTION_LEN: usize = 1216;
pub const SIGNATURE_LEN: usize = 64;
const SECRET_LEN: usize = 32;

/// Separates this signature from any other use of the signing key.
const BINDING_CONTEXT: &[u8] = b"dnet identity binding v1";
/// The only encoding of a public identity so far.
const PUBLIC_FORMAT: u8 = 1;

/// The private half. Wiped from memory when dropped.
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct IdentitySecret {
    signing: [u8; SECRET_LEN],
    encryption: [u8; SECRET_LEN],
}

impl IdentitySecret {
    /// Makes a new identity from the operating system's random source.
    pub fn generate() -> Result<Self> {
        Ok(Self {
            signing: *random_bytes()?,
            encryption: *random_bytes()?,
        })
    }

    /// The bytes to keep in encrypted storage.
    pub fn to_bytes(&self) -> Zeroizing<Vec<u8>> {
        let mut bytes = Zeroizing::new(Vec::with_capacity(2 * SECRET_LEN));
        bytes.extend_from_slice(&self.signing);
        bytes.extend_from_slice(&self.encryption);
        bytes
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        if bytes.len() != 2 * SECRET_LEN {
            return Err(CoreError::Corrupt(
                "identity secret has the wrong length".into(),
            ));
        }
        let (signing, encryption) = bytes.split_at(SECRET_LEN);
        Ok(Self {
            signing: signing.try_into().expect("length checked"),
            encryption: encryption.try_into().expect("length checked"),
        })
    }

    pub(crate) fn encryption_private(&self) -> EncryptionPrivate {
        EncryptionPrivate::from_bytes(&self.encryption)
            .expect("an X-Wing private key is any 32 bytes")
    }

    /// The public signing key on its own. Cheap, unlike [`Self::public`].
    pub fn signing_public(&self) -> [u8; SIGNING_LEN] {
        SigningKey::from_bytes(&self.signing)
            .verifying_key()
            .to_bytes()
    }

    pub(crate) fn sign(&self, message: &[u8]) -> [u8; SIGNATURE_LEN] {
        SigningKey::from_bytes(&self.signing)
            .sign(message)
            .to_bytes()
    }

    /// The half that is safe to show to anyone.
    pub fn public(&self) -> PublicIdentity {
        let signing_key = self.signing_public().to_vec();
        let encryption_key = XWing::sk_to_pk(&self.encryption_private())
            .to_bytes()
            .to_vec();
        let signature = self
            .sign(&binding_message(&signing_key, &encryption_key))
            .to_vec();
        PublicIdentity {
            signing_key,
            encryption_key,
            signature,
        }
    }
}

/// What other people learn about someone: two public keys and the
/// signature that ties them together.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PublicIdentity {
    pub signing_key: Vec<u8>,
    pub encryption_key: Vec<u8>,
    pub signature: Vec<u8>,
}

fn identity_hash(signing_key: &[u8], encryption_key: &[u8]) -> [u8; 32] {
    // Both fields have a fixed length, checked before this is called, so
    // joining them cannot be read two ways.
    let mut hasher = Sha256::new();
    hasher.update(b"dnet identity v1");
    hasher.update(signing_key);
    hasher.update(encryption_key);
    hasher.finalize().into()
}

fn binding_message(signing_key: &[u8], encryption_key: &[u8]) -> Vec<u8> {
    let mut message = BINDING_CONTEXT.to_vec();
    message.extend_from_slice(&identity_hash(signing_key, encryption_key));
    message
}

/// Checks an Ed25519 signature the strict way, which also rejects the weak
/// keys and malleable signatures that plain verification lets through.
pub(crate) fn verify_signature(signing_key: &[u8], message: &[u8], signature: &[u8]) -> Result<()> {
    let invalid = || CoreError::Invalid("a signature does not verify".into());
    let key: [u8; SIGNING_LEN] = signing_key.try_into().map_err(|_| invalid())?;
    let signature: [u8; SIGNATURE_LEN] = signature.try_into().map_err(|_| invalid())?;
    VerifyingKey::from_bytes(&key)
        .map_err(|_| invalid())?
        .verify_strict(message, &Signature::from_bytes(&signature))
        .map_err(|_| invalid())
}

impl PublicIdentity {
    fn check_lengths(&self) -> Result<()> {
        if self.signing_key.len() != SIGNING_LEN
            || self.encryption_key.len() != ENCRYPTION_LEN
            || self.signature.len() != SIGNATURE_LEN
        {
            return Err(CoreError::Invalid(
                "public identity has a field of the wrong length".into(),
            ));
        }
        Ok(())
    }

    /// Checks that the signing key really vouches for the encryption key.
    /// Always call this on an identity received from someone else.
    pub fn verify(&self) -> Result<()> {
        self.check_lengths()?;
        verify_signature(
            &self.signing_key,
            &binding_message(&self.signing_key, &self.encryption_key),
            &self.signature,
        )
        .map_err(|_| CoreError::Invalid("public identity does not verify".into()))?;
        // Also make sure the key is one the cipher will accept.
        self.encryption_public().map(|_| ())
    }

    pub(crate) fn encryption_public(&self) -> Result<EncryptionPublic> {
        EncryptionPublic::from_bytes(&self.encryption_key).map_err(|_| {
            CoreError::Invalid("public identity has an unusable encryption key".into())
        })
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = vec![PUBLIC_FORMAT];
        bytes.extend_from_slice(&self.signing_key);
        bytes.extend_from_slice(&self.encryption_key);
        bytes.extend_from_slice(&self.signature);
        bytes
    }

    /// Decodes without verifying. Call [`PublicIdentity::verify`] next.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        let expected = 1 + SIGNING_LEN + ENCRYPTION_LEN + SIGNATURE_LEN;
        if bytes.len() != expected || bytes[0] != PUBLIC_FORMAT {
            return Err(CoreError::Invalid("not a public identity".into()));
        }
        let (signing_key, rest) = bytes[1..].split_at(SIGNING_LEN);
        let (encryption_key, signature) = rest.split_at(ENCRYPTION_LEN);
        Ok(Self {
            signing_key: signing_key.to_vec(),
            encryption_key: encryption_key.to_vec(),
            signature: signature.to_vec(),
        })
    }

    /// A hash of both public keys. Two identities with the same hash are
    /// the same identity.
    pub fn hash(&self) -> [u8; 32] {
        identity_hash(&self.signing_key, &self.encryption_key)
    }

    /// Sixteen hex digits in four groups, such as `7F3A C21E 9B04 D55A`.
    ///
    /// This is a label for people to glance at. It is 64 bits, which is too
    /// short to prove who someone is. Verifying a person uses the word
    /// comparison, not this.
    pub fn fingerprint(&self) -> String {
        let hash = self.hash();
        hash[..8]
            .chunks(2)
            .map(|pair| format!("{:02X}{:02X}", pair[0], pair[1]))
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Three words, such as `heron copper lantern`, for the ten minutes
    /// now. See [`code_words`]; they change with the time.
    ///
    /// Easy to say aloud so two people can find each other nearby. They
    /// are far too short to be a secret or a proof, and are used as
    /// neither.
    pub fn spoken_code(&self) -> String {
        self.spoken_code_at(window_of(unix_now()))
    }

    /// The three words for one ten-minute window.
    pub fn spoken_code_at(&self, window: u64) -> String {
        code_words(&self.signing_key, window)
    }
}

// The stamp: proof that work went into making an identity.
//
// Making an identity is free, so a program could make thousands and ask
// everyone in range to chat with each. The stamp makes each identity cost a
// few seconds of a phone's time. Other devices check it before they let a
// stranger's chat request in, so identities made in bulk cost in bulk.
//
// It is sixteen numbers. Each, hashed with the identity's signing key and
// its place, gives a hash that starts with at least `bits` zero bits. A
// device finds them by trying numbers in turn; anyone checks them with
// sixteen hashes. Sixteen small finds rather than one big one keeps the wait
// much the same from one identity to the next, and says how far along it is.
//
// It costs a program on a big computer less than it costs a phone. It is a
// price on bulk, not a wall.

/// How many numbers a stamp holds.
pub const STAMP_PARTS: usize = 16;

/// The zero bits each number must give, and the least a device accepts.
/// About sixteen million tries in all: a few seconds on a phone.
///
/// The tests run on a debug build, which is many times slower and makes
/// hundreds of identities, so a debug build asks for a token amount. A
/// release build will not take a debug build's stamps.
pub const STAMP_BITS: u8 = if cfg!(debug_assertions) { 8 } else { 20 };

/// A stamp's length in bytes: the bits it was made for, then the numbers.
pub const STAMP_LEN: usize = 1 + 4 * STAMP_PARTS;

const STAMP_CONTEXT: &[u8] = b"dnet stamp v1";

/// How many zero bits the hash of one try starts with.
fn stamp_zeros(start: &Sha256, part: u8, nonce: u32) -> u32 {
    let mut hasher = start.clone();
    hasher.update([part]);
    hasher.update(nonce.to_be_bytes());
    let hash = hasher.finalize();
    u32::from_be_bytes(hash[..4].try_into().expect("a digest is 32 bytes")).leading_zeros()
}

/// The hasher with everything a stamp's tries share already in it. The
/// whole message fits one block of SHA-256, so each try is one block.
fn stamp_start(signing_key: &[u8]) -> Sha256 {
    let mut hasher = Sha256::new();
    hasher.update(STAMP_CONTEXT);
    hasher.update(signing_key);
    hasher
}

/// Tries `tries` numbers for one part of a stamp, from `from` on. Returns
/// the first that has `bits` zero bits, if one does.
pub fn search_stamp(signing_key: &[u8], part: u8, from: u32, tries: u32, bits: u8) -> Option<u32> {
    let start = stamp_start(signing_key);
    let bits = u32::from(bits);
    (from..=from.saturating_add(tries.saturating_sub(1)))
        .take(tries as usize)
        .find(|&nonce| stamp_zeros(&start, part, nonce) >= bits)
}

/// The stamp as bytes, from the numbers found.
pub fn encode_stamp(bits: u8, nonces: &[u32; STAMP_PARTS]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(STAMP_LEN);
    bytes.push(bits);
    for nonce in nonces {
        bytes.extend_from_slice(&nonce.to_be_bytes());
    }
    bytes
}

/// A whole stamp, made in one go. Blocks until it is done: the app makes
/// its own a slice at a time instead (see `proof::stamp_work`).
pub fn make_stamp(signing_key: &[u8], bits: u8) -> Vec<u8> {
    let mut nonces = [0u32; STAMP_PARTS];
    for (part, nonce) in nonces.iter_mut().enumerate() {
        *nonce = search_stamp(signing_key, part as u8, 0, u32::MAX, bits)
            .expect("2^32 numbers hold a find for any bits a stamp asks");
    }
    encode_stamp(bits, &nonces)
}

/// Whether `stamp` is a sound stamp for `signing_key`, made for at least
/// `least_bits`.
pub fn check_stamp(signing_key: &[u8], stamp: &[u8], least_bits: u8) -> bool {
    if signing_key.len() != SIGNING_LEN || stamp.len() != STAMP_LEN || stamp[0] < least_bits {
        return false;
    }
    // A stamp claiming more than a hash can hold is not one.
    if stamp[0] > 32 {
        return false;
    }
    let start = stamp_start(signing_key);
    let bits = u32::from(stamp[0]);
    stamp[1..].chunks(4).enumerate().all(|(part, nonce)| {
        let nonce = u32::from_be_bytes(nonce.try_into().expect("chunks of four"));
        stamp_zeros(&start, part as u8, nonce) >= bits
    })
}

#[cfg(test)]
mod stamp_tests {
    use super::*;

    const KEY: [u8; SIGNING_LEN] = [7; SIGNING_LEN];

    fn make(key: &[u8], bits: u8) -> Vec<u8> {
        make_stamp(key, bits)
    }

    #[test]
    fn a_stamp_that_was_made_checks() {
        let stamp = make(&KEY, 6);
        assert_eq!(stamp.len(), STAMP_LEN);
        assert!(check_stamp(&KEY, &stamp, 6));
    }

    #[test]
    fn a_stamp_is_for_one_key_only() {
        let stamp = make(&KEY, 10);
        // Another key would need its own work. One chance in 2^160 that
        // these numbers happen to do for it too.
        assert!(!check_stamp(&[8; SIGNING_LEN], &stamp, 10));
    }

    #[test]
    fn a_stamp_made_for_fewer_bits_is_not_enough() {
        let stamp = make(&KEY, 4);
        assert!(!check_stamp(&KEY, &stamp, 5));
    }

    #[test]
    fn a_stamp_that_overstates_its_bits_fails() {
        let mut stamp = make(&KEY, 4);
        stamp[0] = 30;
        assert!(!check_stamp(&KEY, &stamp, 4));
    }

    #[test]
    fn a_changed_number_breaks_the_stamp() {
        let mut stamp = make(&KEY, 12);
        stamp[5] ^= 1;
        assert!(!check_stamp(&KEY, &stamp, 12));
    }

    #[test]
    fn nonsense_is_not_a_stamp() {
        assert!(!check_stamp(&KEY, &[], 0));
        assert!(!check_stamp(&KEY, &[0; STAMP_LEN - 1], 0));
        assert!(!check_stamp(&[1, 2, 3], &make(&KEY, 1), 0));
    }

    #[test]
    fn a_search_stops_where_it_was_told() {
        // Twelve bits is far more than one try is likely to give.
        assert!(search_stamp(&KEY, 0, 0, 0, 12).is_none());
        let found = search_stamp(&KEY, 0, 0, u32::MAX, 12).expect("found");
        assert_eq!(search_stamp(&KEY, 0, found, 1, 12), Some(found));
        // The numbers run out at the top rather than wrapping round.
        assert!(search_stamp(&KEY, 0, u32::MAX, 5, 32).is_none());
    }
}
