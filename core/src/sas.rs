//! The four words two people compare to check nobody is in the middle.
//!
//! The words come from both people's identities and from a random number
//! each of them picks. The exchange has three steps, and the order matters:
//!
//! 1. The one who starts picks a number and sends only a commitment to it.
//! 2. The other picks a number and sends it.
//! 3. The first then reveals theirs.
//!
//! Because the first number is fixed before the second is seen, and the
//! second is sent before the first is revealed, nobody can try numbers until
//! the words come out the way they want. Someone in the middle gets one
//! guess, with about one chance in four billion.

use sha2::{Digest, Sha256};

use crate::error::{CoreError, Result};
use crate::words::WORDS;

pub type Nonce = [u8; 32];
pub type Words = [&'static str; 4];

/// The commitment the starter sends in step 1.
pub fn commitment(nonce: &Nonce) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"dnet verify commitment v1");
    hasher.update(nonce);
    hasher.finalize().into()
}

/// The words both people see. `starter` and `other` are the hashes of the
/// two identities, in the order of who began.
pub fn words(
    starter: &[u8; 32],
    other: &[u8; 32],
    starter_nonce: &Nonce,
    other_nonce: &Nonce,
) -> Words {
    let mut hasher = Sha256::new();
    hasher.update(b"dnet verify words v1");
    hasher.update(starter);
    hasher.update(other);
    hasher.update(starter_nonce);
    hasher.update(other_nonce);
    let hash = hasher.finalize();
    [
        WORDS[hash[0] as usize],
        WORDS[hash[1] as usize],
        WORDS[hash[2] as usize],
        WORDS[hash[3] as usize],
    ]
}

/// Checks a revealed number against the commitment received earlier.
pub fn check_reveal(commit: &[u8; 32], revealed: &Nonce) -> Result<()> {
    // Not secret data, so a plain comparison is fine.
    if &commitment(revealed) == commit {
        Ok(())
    } else {
        Err(CoreError::Invalid(
            "the revealed number does not match the commitment".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ASHA: [u8; 32] = [1; 32];
    const MIRA: [u8; 32] = [2; 32];

    #[test]
    fn the_number_that_was_committed_to_is_accepted() {
        let nonce = [7; 32];
        assert!(check_reveal(&commitment(&nonce), &nonce).is_ok());
    }

    #[test]
    fn any_other_number_is_refused() {
        let commit = commitment(&[7; 32]);
        let mut other = [7; 32];
        other[31] = 8;
        assert!(check_reveal(&commit, &other).is_err());
    }

    #[test]
    fn a_commitment_does_not_give_the_number_away() {
        let nonce = [7; 32];
        assert_ne!(commitment(&nonce), nonce);
    }

    #[test]
    fn the_words_depend_on_both_numbers() {
        let base = words(&ASHA, &MIRA, &[1; 32], &[2; 32]);
        assert_ne!(base, words(&ASHA, &MIRA, &[9; 32], &[2; 32]));
        assert_ne!(base, words(&ASHA, &MIRA, &[1; 32], &[9; 32]));
    }

    #[test]
    fn the_words_depend_on_both_identities() {
        let base = words(&ASHA, &MIRA, &[1; 32], &[2; 32]);
        assert_ne!(base, words(&[3; 32], &MIRA, &[1; 32], &[2; 32]));
        assert_ne!(base, words(&ASHA, &[3; 32], &[1; 32], &[2; 32]));
    }

    #[test]
    fn who_started_matters() {
        assert_ne!(
            words(&ASHA, &MIRA, &[1; 32], &[2; 32]),
            words(&MIRA, &ASHA, &[1; 32], &[2; 32])
        );
    }
}
