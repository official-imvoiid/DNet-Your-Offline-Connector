//! Bytes as hexadecimal text, for the JSON the app and the core exchange.

use crate::error::{CoreError, Result};

pub fn encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn decode(text: &str) -> Result<Vec<u8>> {
    let invalid = || CoreError::Invalid("not hexadecimal".into());
    if !text.len().is_multiple_of(2) || !text.is_ascii() {
        return Err(invalid());
    }
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).map_err(|_| invalid()))
        .collect()
}

/// Decodes text that must be exactly `N` bytes.
pub fn decode_exact<const N: usize>(text: &str) -> Result<[u8; N]> {
    decode(text)?
        .try_into()
        .map_err(|_| CoreError::Invalid(format!("expected {N} bytes of hexadecimal")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bytes_survive_the_round_trip() {
        let bytes = [0u8, 1, 15, 16, 255];
        assert_eq!(encode(&bytes), "00010f10ff");
        assert_eq!(decode("00010f10ff").unwrap(), bytes);
    }

    #[test]
    fn odd_lengths_and_other_characters_are_refused() {
        assert!(decode("abc").is_err());
        assert!(decode("zz").is_err());
        assert!(decode("é0").is_err());
    }

    #[test]
    fn the_exact_length_is_enforced() {
        assert!(decode_exact::<2>("0102").is_ok());
        assert!(decode_exact::<2>("01").is_err());
    }
}
