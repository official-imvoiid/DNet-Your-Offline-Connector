//! The words used for codes people read aloud. One byte picks one word.

use std::time::{SystemTime, UNIX_EPOCH};

use sha2::{Digest, Sha256};

/// How long one set of code words lasts, in seconds: ten minutes.
pub const CODE_WORDS_LAST: u64 = 600;

/// Separates these words from any other hash of a signing key.
const CODE_WORDS_CONTEXT: &[u8] = b"dnet code words v2";

/// The ten-minute window a moment falls in, counted from 1970.
pub fn window_of(unix_secs: u64) -> u64 {
    unix_secs / CODE_WORDS_LAST
}

/// The time now, in seconds since 1970.
pub fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Three words, such as `heron copper lantern`, for someone's signing key
/// in one ten-minute window.
///
/// Every device that knows the key works out the same words, so people
/// nearby can say them aloud to tell apart two people with the same name.
/// They change every window, so words seen in a screenshot or overheard
/// earlier do not match later. They are not a secret, since anyone with
/// the key can work them out, and at 24 bits they are far too short to
/// prove who someone is. Verifying a person compares other words.
pub fn code_words(signing_key: &[u8], window: u64) -> String {
    // The window is always the last eight bytes, so joining the parts
    // cannot be read two ways. The key is public, so a keyed hash would
    // add nothing.
    let mut hasher = Sha256::new();
    hasher.update(CODE_WORDS_CONTEXT);
    hasher.update(signing_key);
    hasher.update(window.to_be_bytes());
    let hash = hasher.finalize();
    format!(
        "{} {} {}",
        WORDS[hash[0] as usize], WORDS[hash[1] as usize], WORDS[hash[2] as usize]
    )
}

/// Whether `said` are the code words for this key at `unix_secs` or in the
/// window before. Allowing the window before lets a clock a few minutes
/// behind still match. Capitals and extra spaces do not matter.
pub fn code_words_match(signing_key: &[u8], said: &str, unix_secs: u64) -> bool {
    let said = said
        .split_whitespace()
        .map(str::to_lowercase)
        .collect::<Vec<_>>()
        .join(" ");
    let now = window_of(unix_secs);
    [Some(now), now.checked_sub(1)]
        .into_iter()
        .flatten()
        .any(|window| code_words(signing_key, window) == said)
}

/// 256 short, common, distinct words.
pub const WORDS: [&str; 256] = [
    "acorn", "anchor", "ant", "anvil", "apple", "arrow", "ash", "atlas", "axe", "badge", "bark",
    "basket", "bat", "bay", "beach", "bear", "bee", "bell", "bench", "berry", "birch", "bird",
    "blade", "bloom", "boar", "boat", "bolt", "book", "boot", "bottle", "bowl", "box", "branch",
    "brick", "bridge", "brook", "broom", "brush", "bucket", "bull", "bush", "button", "cabin",
    "calf", "candle", "canoe", "canvas", "cart", "cat", "cave", "cedar", "chain", "chair", "chalk",
    "cliff", "clock", "cloud", "coast", "coin", "comb", "compass", "copper", "coral", "cord",
    "crab", "crate", "creek", "crow", "crown", "cup", "dawn", "deer", "delta", "desert", "desk",
    "dew", "dog", "door", "dove", "drum", "duck", "dune", "dusk", "eagle", "eel", "elk", "elm",
    "engine", "fawn", "fence", "fern", "field", "fig", "finch", "fish", "fjord", "flag", "flame",
    "flint", "flood", "flute", "fog", "forest", "fork", "fox", "frog", "frost", "gate", "glade",
    "glass", "glove", "goat", "goose", "grass", "grove", "gulf", "hammer", "harbor", "hare",
    "harp", "hawk", "helmet", "hen", "heron", "hill", "hook", "horn", "horse", "ibis", "ice",
    "island", "ivy", "jar", "kettle", "key", "kite", "knot", "ladder", "lake", "lamb", "lamp",
    "lantern", "lark", "leaf", "lens", "lily", "lion", "lock", "lynx", "map", "maple", "marsh",
    "mask", "meadow", "mirror", "mist", "mole", "moon", "moss", "moth", "mouse", "mule", "nail",
    "needle", "net", "newt", "oak", "oar", "ocean", "olive", "orchid", "otter", "owl", "ox",
    "paddle", "palm", "panda", "peak", "pear", "pebble", "pencil", "piano", "pig", "pillow",
    "pine", "plate", "plum", "pond", "pony", "puma", "quail", "quilt", "radio", "rail", "rain",
    "ram", "raven", "reed", "reef", "ridge", "ring", "river", "robin", "rock", "root", "rope",
    "rose", "rudder", "saddle", "sail", "sand", "scarf", "sea", "seal", "seven", "shark", "sheep",
    "shelf", "shield", "ship", "shore", "silver", "sky", "sled", "snail", "snow", "spoon",
    "spring", "stamp", "star", "stone", "storm", "stove", "stream", "sun", "swan", "table", "tent",
    "thorn", "ticket", "tide", "tiger", "toad", "tower", "train", "tree", "tulip", "valley",
    "vine", "violin", "wagon", "wave", "wheel", "willow", "wolf", "wren",
];

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::SIGNING_LEN;
    use std::collections::HashSet;

    const KEY: [u8; SIGNING_LEN] = [7; SIGNING_LEN];

    #[test]
    fn code_words_are_three_words_from_the_list() {
        let words = code_words(&KEY, 1);
        let parts: Vec<&str> = words.split(' ').collect();
        assert_eq!(parts.len(), 3, "{words}");
        assert!(parts.iter().all(|p| WORDS.contains(p)), "{words}");
    }

    #[test]
    fn code_words_are_the_same_for_the_same_key_and_window() {
        // Each device works them out on its own, from the key alone.
        let other_copy = KEY;
        assert_eq!(
            code_words(&KEY, 2_900_000),
            code_words(&other_copy, 2_900_000)
        );
        // Any moment in the same ten minutes gives the same window.
        assert_eq!(window_of(6_000), window_of(6_599));
        assert_ne!(window_of(6_599), window_of(6_600));
    }

    #[test]
    fn code_words_change_every_window() {
        let windows: HashSet<String> = (0..50).map(|w| code_words(&KEY, w)).collect();
        assert!(windows.len() >= 49, "{} of 50 differ", windows.len());
        assert_ne!(code_words(&KEY, 2_900_000), code_words(&KEY, 2_900_001));
    }

    #[test]
    fn code_words_differ_between_keys() {
        assert_ne!(code_words(&KEY, 5), code_words(&[8; SIGNING_LEN], 5));
    }

    #[test]
    fn the_window_before_matches_and_older_ones_do_not() {
        let now = 1_750_000_000;
        let window = window_of(now);
        assert!(code_words_match(&KEY, &code_words(&KEY, window), now));
        assert!(code_words_match(&KEY, &code_words(&KEY, window - 1), now));
        assert!(!code_words_match(&KEY, &code_words(&KEY, window - 2), now));
        // Said aloud and typed back loosely.
        let loose = format!("  {} ", code_words(&KEY, window).to_uppercase());
        assert!(code_words_match(&KEY, &loose.replace(' ', "  "), now));
        assert!(!code_words_match(&KEY, "", now));
        assert!(code_words_match(&KEY, &code_words(&KEY, 0), 0));
    }

    #[test]
    fn every_word_is_different() {
        let unique: HashSet<&str> = WORDS.iter().copied().collect();
        assert_eq!(unique.len(), WORDS.len());
    }

    #[test]
    fn every_word_is_short_lowercase_letters() {
        for word in WORDS {
            assert!((2..=7).contains(&word.len()), "{word}");
            assert!(word.chars().all(|c| c.is_ascii_lowercase()), "{word}");
        }
    }

    #[test]
    fn the_list_is_in_alphabetical_order() {
        // Sorted, so a duplicate or a misplaced edit is easy to spot.
        assert!(WORDS.windows(2).all(|pair| pair[0] < pair[1]));
    }
}
