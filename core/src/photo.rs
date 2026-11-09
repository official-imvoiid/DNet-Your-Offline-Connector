//! Taking out of a picture what the camera wrote into it besides the
//! picture itself.
//!
//! A phone's camera notes where a photo was taken, when, and on what
//! device, and stores that inside the file. Anyone sent the file can read
//! it. [`clean`] returns a copy with those notes gone and the picture
//! untouched: it is not opened, redrawn or squeezed again, only copied
//! piece by piece with the notes left out.
//!
//! It knows two kinds of picture, JPEG and PNG, which is what phone
//! cameras and screenshots make. Anything else it says it cannot clean,
//! and the app tells the user so rather than send it as if it were clean.
//!
//! Nothing here is trusted: a file can be cut short or lie about its own
//! lengths. Every read is checked, and a file that does not hold together
//! is refused, never guessed at.

const PNG: &[u8] = b"\x89PNG\r\n\x1a\n";

/// A copy of a JPEG or PNG with the camera's notes taken out, or `None`
/// if `bytes` is neither, or is broken.
pub fn clean(bytes: &[u8]) -> Option<Vec<u8>> {
    if bytes.starts_with(&[0xFF, 0xD8]) {
        clean_jpeg(bytes)
    } else if bytes.starts_with(PNG) {
        clean_png(bytes)
    } else {
        None
    }
}

/// A JPEG is a run of pieces, each starting with FF and a number that
/// says what it is. The picture is in some of them. The notes are in
/// others, and those are the ones left out:
///
/// - E1: what the camera wrote (Exif), and the same again in another
///   form (XMP). Both can hold the position.
/// - E2: kept only if it is the colour profile. Its other use points to
///   more pictures stuck on after this one.
/// - E3 to ED and EF: other programs' notes, captions and keywords.
/// - FE: a comment.
///
/// One thing the camera wrote is needed to show the photo properly: which
/// way up it was held. That one number is read out and written back in a
/// fresh, empty note with nothing else in it.
///
/// Whatever follows the end of the picture is dropped. Some phones put a
/// short film there.
fn clean_jpeg(bytes: &[u8]) -> Option<Vec<u8>> {
    let mut kept: Vec<&[u8]> = Vec::new();
    let mut way_up = None;
    let mut at = 2;
    loop {
        if *bytes.get(at)? != 0xFF {
            return None;
        }
        // More than one FF before the number is padding.
        let mut number_at = at + 1;
        while *bytes.get(number_at)? == 0xFF {
            number_at += 1;
        }
        let number = bytes[number_at];
        at = number_at + 1;
        match number {
            // The end of the picture.
            0xD9 => break,
            // These few stand alone, with nothing after them.
            0x01 | 0xD0..=0xD7 => {
                kept.push(&bytes[number_at - 1..at]);
                continue;
            }
            // Neither can be where a piece starts.
            0x00 | 0xD8 => return None,
            _ => {}
        }
        // Every other piece says how long it is, counting those two bytes.
        let length = u16::from_be_bytes([*bytes.get(at)?, *bytes.get(at + 1)?]) as usize;
        if length < 2 {
            return None;
        }
        let end = at.checked_add(length)?;
        let inside = bytes.get(at + 2..end)?;
        let whole = &bytes[number_at - 1..end];
        match number {
            0xE1 => {
                if let Some(notes) = inside.strip_prefix(b"Exif\0\0") {
                    way_up = way_up.or_else(|| way_up_in(notes));
                }
            }
            0xE2 => {
                if inside.starts_with(b"ICC_PROFILE\0") {
                    kept.push(whole);
                }
            }
            0xE3..=0xED | 0xEF | 0xFE => {}
            _ => kept.push(whole),
        }
        at = end;

        if number == 0xDA {
            // After this piece comes the picture's own data, which has no
            // length written down. It runs until the next FF that starts
            // a piece. An FF followed by 00 is an FF that is part of the
            // data, and FF D0 to FF D7 are marks inside it.
            let data_from = at;
            loop {
                if *bytes.get(at)? != 0xFF {
                    at += 1;
                    continue;
                }
                match *bytes.get(at + 1)? {
                    0x00 | 0xD0..=0xD7 => at += 2,
                    0xFF => at += 1,
                    _ => break,
                }
            }
            kept.push(&bytes[data_from..at]);
        }
    }

    let mut out = vec![0xFF, 0xD8];
    let mut kept = kept.into_iter().peekable();
    // The piece that says "this is a JPEG" stays first if there is one.
    if kept.peek().is_some_and(|piece| piece.get(1) == Some(&0xE0)) {
        out.extend_from_slice(kept.next()?);
    }
    if let Some(way_up) = way_up {
        out.extend(way_up_note(way_up));
    }
    for piece in kept {
        out.extend_from_slice(piece);
    }
    out.extend_from_slice(&[0xFF, 0xD9]);
    Some(out)
}

/// Finds which way up the camera was held, in what it wrote: a number
/// from 2 to 8. 1 means the ordinary way, which needs no note.
fn way_up_in(notes: &[u8]) -> Option<u16> {
    // The notes say at the start which order their bytes are in.
    let little = match notes.get(..2)? {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let two = |from: usize, plus: usize| -> Option<u16> {
        let at = from.checked_add(plus)?;
        let pair: [u8; 2] = notes.get(at..at.checked_add(2)?)?.try_into().ok()?;
        Some(if little {
            u16::from_le_bytes(pair)
        } else {
            u16::from_be_bytes(pair)
        })
    };
    let four = |from: usize, plus: usize| -> Option<u32> {
        let at = from.checked_add(plus)?;
        let quad: [u8; 4] = notes.get(at..at.checked_add(4)?)?.try_into().ok()?;
        Some(if little {
            u32::from_le_bytes(quad)
        } else {
            u32::from_be_bytes(quad)
        })
    };
    if two(0, 2)? != 42 {
        return None;
    }
    // A list of entries, twelve bytes each: what it is, what kind of
    // number, how many, and the number itself.
    let list = usize::try_from(four(0, 4)?).ok()?;
    for index in 0..usize::from(two(list, 0)?) {
        let entry = list.checked_add(2)?.checked_add(index.checked_mul(12)?)?;
        if two(entry, 0)? == 0x0112 && two(entry, 2)? == 3 && four(entry, 4)? == 1 {
            return two(entry, 8).filter(|way| (2..=8).contains(way));
        }
    }
    None
}

/// A note holding which way up the photo is, and nothing else.
fn way_up_note(way_up: u16) -> Vec<u8> {
    let mut note = b"Exif\0\0MM\0\x2A\0\0\0\x08\0\x01\x01\x12\0\x03\0\0\0\x01".to_vec();
    note.extend_from_slice(&way_up.to_be_bytes());
    note.extend_from_slice(&[0; 6]);
    let mut piece = vec![0xFF, 0xE1];
    piece.extend_from_slice(&((note.len() + 2) as u16).to_be_bytes());
    piece.extend(note);
    piece
}

/// A PNG is a run of chunks, each with a four-letter name. The ones that
/// hold notes, not picture, are left out: what a camera wrote (eXIf),
/// text of any kind (tEXt, zTXt, iTXt) and when it was last changed
/// (tIME). Whatever follows the last chunk is dropped.
fn clean_png(bytes: &[u8]) -> Option<Vec<u8>> {
    let mut out = PNG.to_vec();
    let mut at = PNG.len();
    loop {
        let length: [u8; 4] = bytes.get(at..at.checked_add(4)?)?.try_into().ok()?;
        let name = bytes.get(at + 4..at + 8)?;
        // The length, the name, what it holds, and a four-byte check.
        let end = at
            .checked_add(12)?
            .checked_add(usize::try_from(u32::from_be_bytes(length)).ok()?)?;
        let whole = bytes.get(at..end)?;
        if !matches!(name, b"eXIf" | b"tEXt" | b"zTXt" | b"iTXt" | b"tIME") {
            out.extend_from_slice(whole);
        }
        if name == b"IEND" {
            return Some(out);
        }
        at = end;
    }
}
