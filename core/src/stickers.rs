//! The user's own stickers, and how they keep them arranged.
//!
//! Each sticker of the user's own is a small picture, kept whole as one
//! record under a random id. An index lists the ids, so they can be
//! counted and tidied without opening every picture. The book says how
//! the stickers are arranged into packs, which are favourites, and what
//! the emoji picker remembers: the app writes it and the core keeps it,
//! sealed like every other record. Nothing here is sent anywhere; a
//! sticker travels only when the user sends it, as any sticker does.

use serde_json::{json, Value};

use crate::chat::Sticker;
use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::seal::random_bytes;
use crate::vault::Vault;

const PICTURES: &str = "sticker";
const INDEX: (&str, &[u8]) = ("sticker_book", b"pictures");
const BOOK: (&str, &[u8]) = ("sticker_book", b"book");
/// The most stickers of their own a user keeps.
pub const MAX_PICTURES: usize = 1000;
/// The largest book, as JSON.
const MAX_BOOK_BYTES: usize = 128 * 1024;
const ID_BYTES: usize = 16;

fn invalid(what: &str) -> CoreError {
    CoreError::Invalid(what.to_string())
}

fn index(vault: &Vault) -> Result<Vec<String>> {
    match vault.get(INDEX.0, INDEX.1)? {
        None => Ok(Vec::new()),
        Some(bytes) => serde_json::from_slice(&bytes)
            .map_err(|_| CoreError::Corrupt("the sticker index is unreadable".into())),
    }
}

fn picture_id(id: &str) -> Result<[u8; ID_BYTES]> {
    hexcode::decode_exact::<ID_BYTES>(id).map_err(|_| invalid("that is not a sticker id"))
}

/// The book as the app last wrote it, or null, and the id of every
/// picture kept.
pub fn book(vault: &Vault) -> Result<Value> {
    let book = match vault.get(BOOK.0, BOOK.1)? {
        None => Value::Null,
        Some(bytes) => serde_json::from_slice(&bytes)
            .map_err(|_| CoreError::Corrupt("the sticker book is unreadable".into()))?,
    };
    Ok(json!({ "book": book, "pictures": index(vault)? }))
}

/// Keeps the app's book in place of the last one.
pub fn save_book(vault: &Vault, book: &Value) -> Result<()> {
    if !book.is_object() {
        return Err(invalid("a sticker book is an object"));
    }
    let bytes = serde_json::to_vec(book).expect("a JSON value always encodes");
    if bytes.len() > MAX_BOOK_BYTES {
        return Err(invalid("the sticker book is too big"));
    }
    vault.put(BOOK.0, BOOK.1, &bytes)
}

/// Keeps `image`, a picture as hex, and gives back its new id.
pub fn keep(vault: &Vault, image: &str) -> Result<Value> {
    let sound = Sticker {
        name: String::new(),
        image: image.to_string(),
    }
    .sound();
    if !sound {
        return Err(invalid("a sticker is one small picture"));
    }
    let mut ids = index(vault)?;
    if ids.len() >= MAX_PICTURES {
        return Err(invalid("there is no room for another sticker"));
    }
    let bytes = hexcode::decode(image)?;
    let id = hexcode::encode(random_bytes::<ID_BYTES>()?.as_slice());
    ids.push(id.clone());
    let list = serde_json::to_vec(&ids).expect("a list of ids always encodes");
    vault.batch(|batch| {
        batch.put(PICTURES, &picture_id(&id)?, &bytes)?;
        batch.put(INDEX.0, INDEX.1, &list)
    })?;
    Ok(json!({ "id": id }))
}

/// The picture kept as `id`, as hex, or null if there is none.
pub fn picture(vault: &Vault, id: &str) -> Result<Value> {
    Ok(match vault.get(PICTURES, &picture_id(id)?)? {
        Some(bytes) => json!({ "image": hexcode::encode(&bytes) }),
        None => Value::Null,
    })
}

/// Forgets the picture kept as `id`. Forgetting one that is not kept
/// does nothing.
pub fn drop(vault: &Vault, id: &str) -> Result<()> {
    let key = picture_id(id)?;
    let mut ids = index(vault)?;
    ids.retain(|kept| kept != id);
    let list = serde_json::to_vec(&ids).expect("a list of ids always encodes");
    vault.batch(|batch| {
        batch.delete(PICTURES, &key)?;
        batch.put(INDEX.0, INDEX.1, &list)
    })
}
