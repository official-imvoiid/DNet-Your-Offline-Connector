//! Sealed envelopes: how one person sends bytes to another.
//!
//! Only the recipient can open an envelope, and when they do they learn
//! which signing key sent it. Anyone carrying the envelope in between learns
//! neither the content nor the sender.
//!
//! The sealing is HPKE (RFC 9180) from the `hpke` crate, with:
//!
//! - X-Wing as the key encapsulation: X25519 and ML-KEM-768 together.
//! - HKDF-SHA256 to derive keys.
//! - AES-256-GCM to encrypt.
//!
//! The sender's Ed25519 signature goes inside, so it is hidden too.
//!
//! What this does not give: forward secrecy. The recipient's key is long
//! lived, so someone who records envelopes and later steals that key can
//! open them. Fixing that needs a ratchet, which is not built.

use hpke::aead::AesGcm256;
use hpke::kdf::HkdfSha256;
use hpke::kem::XWing;
use hpke::{Deserializable, Kem, OpModeR, OpModeS, Serializable};
use zeroize::Zeroizing;

use crate::error::{CoreError, Result};
use crate::identity::{
    verify_signature, IdentitySecret, PublicIdentity, SIGNATURE_LEN, SIGNING_LEN,
};

/// The only envelope format so far.
const FORMAT: u8 = 1;
const INFO: &[u8] = b"dnet envelope v1";
const SIGNING_CONTEXT: &[u8] = b"dnet envelope signature v1";
/// An X-Wing encapsulated key.
const ENCAPPED_LEN: usize = 1120;
/// AES-GCM's authentication tag.
const TAG_LEN: usize = 16;

type EncappedKey = <XWing as Kem>::EncappedKey;

/// What came out of an envelope.
#[derive(Debug)]
pub struct Opened {
    /// Who sent it. The signature has been checked.
    pub sender_signing_key: [u8; SIGNING_LEN],
    pub payload: Vec<u8>,
}

/// What the sender signs: the content, and who it is for. Naming the
/// recipient stops them passing the signed content on to someone else as if
/// the sender had written it to that person.
fn signed_message(recipient_hash: &[u8; 32], payload: &[u8]) -> Vec<u8> {
    let mut message = Vec::with_capacity(SIGNING_CONTEXT.len() + 32 + payload.len());
    message.extend_from_slice(SIGNING_CONTEXT);
    message.extend_from_slice(recipient_hash);
    message.extend_from_slice(payload);
    message
}

fn not_an_envelope() -> CoreError {
    // One answer for every way an envelope can be wrong, so a sender
    // learns nothing from which check failed.
    CoreError::Invalid("the envelope does not open".into())
}

/// Seals `payload` from `sender` to `recipient`.
pub fn seal(
    sender: &IdentitySecret,
    recipient: &PublicIdentity,
    payload: &[u8],
) -> Result<Vec<u8>> {
    recipient.verify()?;
    let recipient_hash = recipient.hash();

    let mut plaintext = Zeroizing::new(Vec::with_capacity(
        SIGNING_LEN + SIGNATURE_LEN + payload.len(),
    ));
    plaintext.extend_from_slice(&sender.signing_public());
    plaintext.extend_from_slice(&sender.sign(&signed_message(&recipient_hash, payload)));
    plaintext.extend_from_slice(payload);

    let (encapped, ciphertext) = hpke::single_shot_seal::<AesGcm256, HkdfSha256, XWing>(
        &OpModeS::Base,
        &recipient.encryption_public()?,
        INFO,
        &plaintext,
        &recipient_hash,
    )
    .map_err(|_| CoreError::Invalid("the envelope could not be sealed".into()))?;

    let mut envelope = Vec::with_capacity(1 + ENCAPPED_LEN + ciphertext.len());
    envelope.push(FORMAT);
    envelope.extend_from_slice(&encapped.to_bytes());
    envelope.extend_from_slice(&ciphertext);
    Ok(envelope)
}

/// Opens an envelope addressed to `recipient` and checks the signature
/// inside it.
pub fn open(recipient: &IdentitySecret, envelope: &[u8]) -> Result<Opened> {
    if envelope.len() < 1 + ENCAPPED_LEN + SIGNING_LEN + SIGNATURE_LEN + TAG_LEN
        || envelope[0] != FORMAT
    {
        return Err(not_an_envelope());
    }
    let (encapped, ciphertext) = envelope[1..].split_at(ENCAPPED_LEN);
    let encapped = EncappedKey::from_bytes(encapped).map_err(|_| not_an_envelope())?;
    let recipient_hash = recipient.public().hash();

    let plaintext = Zeroizing::new(
        hpke::single_shot_open::<AesGcm256, HkdfSha256, XWing>(
            &OpModeR::Base,
            &recipient.encryption_private(),
            &encapped,
            INFO,
            ciphertext,
            &recipient_hash,
        )
        .map_err(|_| not_an_envelope())?,
    );

    let (sender_key, rest) = plaintext.split_at(SIGNING_LEN);
    let (signature, payload) = rest.split_at(SIGNATURE_LEN);
    verify_signature(
        sender_key,
        &signed_message(&recipient_hash, payload),
        signature,
    )
    .map_err(|_| not_an_envelope())?;
    Ok(Opened {
        sender_signing_key: sender_key.try_into().expect("split at the key length"),
        payload: payload.to_vec(),
    })
}

#[cfg(test)]
mod tests {
    //! Forgeries. These need to build envelopes the honest `seal` never
    //! would, so they live here where the pieces are in reach.

    use super::*;

    fn person() -> IdentitySecret {
        IdentitySecret::generate().unwrap()
    }

    /// Seals whatever it is given, as an attacker who knows the format can.
    fn seal_raw(recipient: &PublicIdentity, plaintext: &[u8]) -> Vec<u8> {
        let (encapped, ciphertext) = hpke::single_shot_seal::<AesGcm256, HkdfSha256, XWing>(
            &OpModeS::Base,
            &recipient.encryption_public().unwrap(),
            INFO,
            plaintext,
            &recipient.hash(),
        )
        .unwrap();
        let mut envelope = vec![FORMAT];
        envelope.extend_from_slice(&encapped.to_bytes());
        envelope.extend_from_slice(&ciphertext);
        envelope
    }

    fn inside(
        named_sender: &IdentitySecret,
        signer: &IdentitySecret,
        signed_for: &PublicIdentity,
        payload: &[u8],
    ) -> Vec<u8> {
        let mut plaintext = named_sender.signing_public().to_vec();
        plaintext.extend_from_slice(&signer.sign(&signed_message(&signed_for.hash(), payload)));
        plaintext.extend_from_slice(payload);
        plaintext
    }

    #[test]
    fn the_forging_helper_makes_envelopes_that_open_when_honest() {
        // Proves the tests below fail for the reason they claim.
        let (eve, mira) = (person(), person());
        let envelope = seal_raw(&mira.public(), &inside(&eve, &eve, &mira.public(), b"hi"));
        assert_eq!(
            open(&mira, &envelope).unwrap().sender_signing_key,
            eve.signing_public()
        );
    }

    #[test]
    fn naming_someone_else_as_the_sender_is_rejected() {
        let (asha, mira, eve) = (person(), person(), person());
        // Eve writes Asha's key where the sender goes and signs it herself.
        let envelope = seal_raw(
            &mira.public(),
            &inside(&asha, &eve, &mira.public(), b"send money"),
        );
        assert!(open(&mira, &envelope).is_err());
    }

    #[test]
    fn content_signed_for_one_person_cannot_be_passed_to_another() {
        let (asha, mira, noor) = (person(), person(), person());
        // Asha really did sign this, but for Mira. Mira re-seals it to Noor.
        let envelope = seal_raw(
            &noor.public(),
            &inside(&asha, &asha, &mira.public(), b"I owe you 500"),
        );
        assert!(open(&noor, &envelope).is_err());
    }
}
