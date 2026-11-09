//! Files posted in a space's channels, as this device keeps them.
//!
//! A channel's history is shared by every member, but its files are not
//! copied to everyone. A post says what a file is: its name, size, kind
//! and SHA-256. The file itself is kept by whoever posted it and by anyone
//! who has fetched it, in this device's own folder, and a member who wants
//! it fetches it in pieces from any member in range who holds it. Pieces
//! come in order, so a fetch that is cut off carries on from where it got
//! to, from whoever is met next.
//!
//! The SHA-256 is checked when the last piece arrives. A file that does
//! not match is thrown away, never shown.
//!
//! Like a file from a contact, a kept file is an ordinary file in the
//! app's own folder, not inside the encrypted vault.

use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::error::{CoreError, Result};
use crate::file::{free_path, safe_name};
use crate::hexcode;
use crate::seal::random_bytes;
use crate::vault::Vault;

const SHELF: &str = "space_file";
/// How much of a file goes in one piece.
pub(crate) const PIECE: u64 = 32 * 1024;
/// How many pieces one answer carries. The asker asks again for more.
pub(crate) const PER_ANSWER: u64 = 4;
/// The largest file a channel takes. Over Bluetooth even this is slow.
pub(crate) const MAX_SIZE: u64 = 25 * 1024 * 1024;
const PART: &str = ".part";

fn invalid(what: &str) -> CoreError {
    CoreError::Invalid(what.to_string())
}

fn storage(error: std::io::Error) -> CoreError {
    CoreError::Storage(error.to_string())
}

/// How many pieces a file of `size` bytes comes in.
pub(crate) fn pieces_of(size: u64) -> u64 {
    size.div_ceil(PIECE)
}

/// What this device knows about one file.
#[derive(Clone, Default, Serialize, Deserialize)]
pub(crate) struct Kept {
    pub size: u64,
    /// Pieces held, in order.
    pub have: u64,
    /// The whole file is here and matched its SHA-256.
    pub done: bool,
    /// The user asked for it and it is not here yet.
    pub wanted: bool,
    /// The spaces whose posts carry it.
    pub spaces: Vec<String>,
}

/// What came of some pieces arriving.
#[derive(PartialEq, Eq, Debug)]
pub(crate) enum Taken {
    /// Not asked for, or not the pieces that were next. Nothing changed.
    Ignored,
    /// Kept. Ask for more from here.
    More(u64),
    /// The last piece came and the file matched.
    Done,
    /// The last piece came and the file did not match. It was thrown away.
    Failed,
}

pub(crate) struct Shelf<'a> {
    pub vault: &'a Vault,
    pub dir: &'a Path,
}

impl Shelf<'_> {
    fn key(sha: &str) -> Result<[u8; 32]> {
        hexcode::decode_exact::<32>(sha).map_err(|_| invalid("that is not a file"))
    }

    pub fn get(&self, sha: &str) -> Result<Option<Kept>> {
        match self.vault.get(SHELF, &Self::key(sha)?)? {
            None => Ok(None),
            Some(bytes) => serde_json::from_slice(&bytes)
                .map(Some)
                .map_err(|_| CoreError::Corrupt("a kept file's record is unreadable".into())),
        }
    }

    fn put(&self, sha: &str, kept: &Kept) -> Result<()> {
        let bytes = serde_json::to_vec(kept).expect("a kept file's record is plain data");
        self.vault.put(SHELF, &Self::key(sha)?, &bytes)
    }

    fn all(&self) -> Result<Vec<(String, Kept)>> {
        self.vault
            .list(SHELF)?
            .into_iter()
            .map(|(sha, bytes)| {
                let kept = serde_json::from_slice(&bytes)
                    .map_err(|_| CoreError::Corrupt("a kept file's record is unreadable".into()))?;
                Ok((hexcode::encode(&sha), kept))
            })
            .collect()
    }

    /// Where the whole file is, once it is here.
    pub fn path(&self, sha: &str) -> PathBuf {
        self.dir.join(sha)
    }

    fn part(&self, sha: &str) -> PathBuf {
        self.dir.join(format!("{sha}{PART}"))
    }

    /// Takes in a file the user posts in `space`: copies it into this
    /// device's folder, working out its SHA-256 on the way. The user's own
    /// file is not changed. Returns the SHA-256 and the size.
    pub fn add_own(&self, path: &Path, space: &str) -> Result<(String, u64)> {
        let size = fs::metadata(path)
            .ok()
            .filter(|meta| meta.is_file())
            .ok_or_else(|| invalid("that file cannot be read"))?
            .len();
        if size == 0 || size > MAX_SIZE {
            return Err(invalid("a file in a channel is from 1 byte to 25 MB"));
        }
        fs::create_dir_all(self.dir).map_err(storage)?;
        let copying = self.dir.join(format!(
            "{}.in",
            hexcode::encode(random_bytes::<8>()?.as_slice())
        ));
        let copied = (|| -> std::io::Result<(Sha256, u64)> {
            let mut from = File::open(path)?;
            let mut to = File::create(&copying)?;
            let mut hasher = Sha256::new();
            let mut buffer = vec![0u8; 64 * 1024];
            let mut total = 0;
            loop {
                let read = from.read(&mut buffer)?;
                if read == 0 {
                    break;
                }
                hasher.update(&buffer[..read]);
                to.write_all(&buffer[..read])?;
                total += read as u64;
            }
            to.sync_all()?;
            Ok((hasher, total))
        })();
        let (hasher, copied_size) = match copied {
            Ok(done) => done,
            Err(error) => {
                let _ = fs::remove_file(&copying);
                return Err(storage(error));
            }
        };
        // It changed while being read: not the file the user chose.
        if copied_size != size {
            let _ = fs::remove_file(&copying);
            return Err(invalid("the file changed while it was being read"));
        }
        let sha = hexcode::encode(hasher.finalize().as_slice());
        fs::rename(&copying, self.path(&sha)).map_err(storage)?;
        let mut kept = self.get(&sha)?.unwrap_or_default();
        kept.size = size;
        kept.have = pieces_of(size);
        kept.done = true;
        kept.wanted = false;
        if !kept.spaces.iter().any(|s| s == space) {
            kept.spaces.push(space.to_string());
        }
        self.put(&sha, &kept)?;
        Ok((sha, size))
    }

    /// Notes that the user wants a file a post in `space` carries. Returns
    /// the piece to ask for next, or None if it is here already.
    pub fn want(&self, sha: &str, size: u64, space: &str) -> Result<Option<u64>> {
        if size == 0 || size > MAX_SIZE {
            return Err(invalid("that is not a file a channel can carry"));
        }
        let mut kept = self.get(sha)?.unwrap_or(Kept {
            size,
            ..Kept::default()
        });
        if !kept.spaces.iter().any(|s| s == space) {
            kept.spaces.push(space.to_string());
        }
        if kept.done {
            self.put(sha, &kept)?;
            return Ok(None);
        }
        kept.wanted = true;
        self.put(sha, &kept)?;
        Ok(Some(kept.have))
    }

    /// Files the user is waiting for, with the piece to ask for next.
    pub fn waiting(&self) -> Result<Vec<(String, Kept)>> {
        Ok(self
            .all()?
            .into_iter()
            .filter(|(_, kept)| kept.wanted && !kept.done)
            .collect())
    }

    /// Up to [`PER_ANSWER`] pieces from `from` on, of a whole file this
    /// device holds for `space`. Nothing for a file it does not hold, or
    /// one that is not this space's.
    pub fn serve(&self, sha: &str, space: &str, from: u64) -> Result<Vec<Vec<u8>>> {
        let Some(kept) = self.get(sha)? else {
            return Ok(Vec::new());
        };
        if !kept.done || !kept.spaces.iter().any(|s| s == space) {
            return Ok(Vec::new());
        }
        let total = pieces_of(kept.size);
        let mut pieces = Vec::new();
        let Ok(mut file) = File::open(self.path(sha)) else {
            return Ok(Vec::new());
        };
        for index in from..total.min(from.saturating_add(PER_ANSWER)) {
            let start = index * PIECE;
            let length = PIECE.min(kept.size - start);
            let mut piece = vec![0u8; length as usize];
            file.seek(SeekFrom::Start(start)).map_err(storage)?;
            file.read_exact(&mut piece).map_err(storage)?;
            pieces.push(piece);
        }
        Ok(pieces)
    }

    /// Keeps pieces that arrived for a file the user is waiting for, if
    /// they are the next ones and the right size.
    pub fn take(&self, sha: &str, from: u64, pieces: &[Vec<u8>]) -> Result<Taken> {
        let Some(mut kept) = self.get(sha)? else {
            return Ok(Taken::Ignored);
        };
        let total = pieces_of(kept.size);
        if !kept.wanted
            || kept.done
            || from != kept.have
            || pieces.is_empty()
            || pieces.len() as u64 > PER_ANSWER
            || from + pieces.len() as u64 > total
        {
            return Ok(Taken::Ignored);
        }
        let sizes_right = pieces.iter().enumerate().all(|(n, piece)| {
            let index = from + n as u64;
            piece.len() as u64 == PIECE.min(kept.size - index * PIECE)
        });
        if !sizes_right {
            return Ok(Taken::Ignored);
        }
        fs::create_dir_all(self.dir).map_err(storage)?;
        let mut file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(false)
            .open(self.part(sha))
            .map_err(storage)?;
        file.seek(SeekFrom::Start(from * PIECE)).map_err(storage)?;
        for piece in pieces {
            file.write_all(piece).map_err(storage)?;
        }
        file.sync_all().map_err(storage)?;
        drop(file);
        kept.have = from + pieces.len() as u64;
        if kept.have < total {
            self.put(sha, &kept)?;
            return Ok(Taken::More(kept.have));
        }
        // All here: it must be the file the post named.
        let matches = (|| -> std::io::Result<bool> {
            let mut hasher = Sha256::new();
            let mut part = File::open(self.part(sha))?.take(kept.size);
            let mut buffer = vec![0u8; 64 * 1024];
            loop {
                let read = part.read(&mut buffer)?;
                if read == 0 {
                    break;
                }
                hasher.update(&buffer[..read]);
            }
            Ok(hexcode::encode(hasher.finalize().as_slice()) == sha)
        })()
        .map_err(storage)?;
        if !matches {
            let _ = fs::remove_file(self.part(sha));
            kept.have = 0;
            self.put(sha, &kept)?;
            return Ok(Taken::Failed);
        }
        fs::rename(self.part(sha), self.path(sha)).map_err(storage)?;
        kept.done = true;
        kept.wanted = false;
        self.put(sha, &kept)?;
        Ok(Taken::Done)
    }

    /// Lets go of every file of `space` whose SHA-256 is not in `keep`:
    /// the space no longer shows a post carrying it. A file no space
    /// needs is deleted from the device.
    pub fn sweep(&self, space: &str, keep: &HashSet<String>) -> Result<()> {
        for (sha, mut kept) in self.all()? {
            if !kept.spaces.iter().any(|s| s == space) || keep.contains(&sha) {
                continue;
            }
            kept.spaces.retain(|s| s != space);
            if kept.spaces.is_empty() {
                let _ = fs::remove_file(self.path(&sha));
                let _ = fs::remove_file(self.part(&sha));
                self.vault.delete(SHELF, &Self::key(&sha)?)?;
            } else {
                self.put(&sha, &kept)?;
            }
        }
        Ok(())
    }

    /// Copies a whole file to `dir` for the user, under a safe form of
    /// `name` that does not replace anything already there.
    pub fn save_copy(&self, sha: &str, name: &str, dir: &Path) -> Result<PathBuf> {
        if !self.get(sha)?.is_some_and(|kept| kept.done) {
            return Err(invalid("that file is not on this device yet"));
        }
        fs::create_dir_all(dir).map_err(storage)?;
        let to = free_path(dir, &safe_name(name));
        fs::copy(self.path(sha), &to).map_err(storage)?;
        Ok(to)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shelf_in(dir: &Path) -> (Vault, PathBuf) {
        let vault = Vault::open(dir, &[7u8; 32]).unwrap();
        (vault, dir.join("files"))
    }

    fn sha_of(bytes: &[u8]) -> String {
        hexcode::encode(Sha256::digest(bytes).as_slice())
    }

    #[test]
    fn pieces_that_do_not_make_the_file_named_are_thrown_away() {
        let home = tempfile::tempdir().unwrap();
        let (vault, dir) = shelf_in(home.path());
        let shelf = Shelf {
            vault: &vault,
            dir: &dir,
        };
        let real = vec![1u8; 40_000];
        let sha = sha_of(&real);
        assert_eq!(shelf.want(&sha, 40_000, "space").unwrap(), Some(0));

        // Two pieces of the right sizes, but not the right bytes.
        let fake = vec![
            vec![2u8; PIECE as usize],
            vec![2u8; 40_000 - PIECE as usize],
        ];
        assert_eq!(shelf.take(&sha, 0, &fake).unwrap(), Taken::Failed);
        let kept = shelf.get(&sha).unwrap().unwrap();
        assert_eq!((kept.have, kept.done, kept.wanted), (0, false, true));
        assert!(!shelf.path(&sha).exists());
        assert!(!shelf.part(&sha).exists());

        // The real ones are taken.
        let pieces = vec![
            real[..PIECE as usize].to_vec(),
            real[PIECE as usize..].to_vec(),
        ];
        assert_eq!(shelf.take(&sha, 0, &pieces).unwrap(), Taken::Done);
        assert_eq!(fs::read(shelf.path(&sha)).unwrap(), real);
    }

    #[test]
    fn pieces_out_of_turn_or_of_the_wrong_size_change_nothing() {
        let home = tempfile::tempdir().unwrap();
        let (vault, dir) = shelf_in(home.path());
        let shelf = Shelf {
            vault: &vault,
            dir: &dir,
        };
        let real = vec![1u8; 3 * PIECE as usize];
        let sha = sha_of(&real);
        let piece = |n: usize| real[n * PIECE as usize..(n + 1) * PIECE as usize].to_vec();
        // Not asked for.
        assert_eq!(shelf.take(&sha, 0, &[piece(0)]).unwrap(), Taken::Ignored);
        shelf.want(&sha, real.len() as u64, "space").unwrap();
        assert_eq!(shelf.take(&sha, 1, &[piece(1)]).unwrap(), Taken::Ignored);
        assert_eq!(
            shelf.take(&sha, 0, &[vec![1u8; 10]]).unwrap(),
            Taken::Ignored
        );
        assert_eq!(shelf.take(&sha, 0, &[piece(0)]).unwrap(), Taken::More(1));
        assert_eq!(shelf.take(&sha, 0, &[piece(0)]).unwrap(), Taken::Ignored);
        assert_eq!(shelf.get(&sha).unwrap().unwrap().have, 1);
    }

    #[test]
    fn a_file_is_served_only_for_a_space_it_was_posted_in_and_only_when_whole() {
        let home = tempfile::tempdir().unwrap();
        let (vault, dir) = shelf_in(home.path());
        let shelf = Shelf {
            vault: &vault,
            dir: &dir,
        };
        let original = home.path().join("map.gpx");
        fs::write(&original, vec![3u8; 50_000]).unwrap();
        let (sha, size) = shelf.add_own(&original, "ours").unwrap();
        assert_eq!(size, 50_000);
        assert_eq!(shelf.serve(&sha, "ours", 0).unwrap().len(), 2);
        assert!(shelf.serve(&sha, "theirs", 0).unwrap().is_empty());

        let wanted = sha_of(&[9u8; 10]);
        shelf.want(&wanted, 10, "ours").unwrap();
        assert!(shelf.serve(&wanted, "ours", 0).unwrap().is_empty());
    }
}
