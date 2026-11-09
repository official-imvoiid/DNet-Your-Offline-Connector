//! Sending a file to a contact.
//!
//! A file goes as an offer, an answer, and then pieces. Every piece
//! travels in its own sealed envelope, like a message, so nothing that
//! carries it can read it. The receiver says which pieces it holds, and
//! the sender never runs more than a few pieces ahead of that. A transfer
//! that is cut off therefore carries on from where the receiver got to,
//! not from the start.
//!
//! Pieces may arrive in any order, by any link or any device in between:
//! some over Wi-Fi, some over Bluetooth, some passed on by someone else.
//! Each is checked on its own before it is written. The offer carries the
//! root of a hash tree over every piece, and each piece carries the few
//! hashes that tie it to that root, so a piece that is not exactly the one
//! offered at that place is never written. The whole file's SHA-256 is in
//! the offer too, and is checked once more when the last piece is in.
//!
//! What this does not do: a received file is written as an ordinary file
//! in the folder the app chose, so that other apps can open it. It is not
//! inside the encrypted vault.

use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::seal::random_bytes;
use crate::vault::Vault;

const FILES: &str = "file";
/// The hash of every piece of each file being sent, by transfer, so that
/// each piece can be sent with what ties it to the offer.
const TREES: &str = "file_tree";
/// How much of a file goes in one piece.
const PIECE: u32 = 32 * 1024;
/// How many pieces the sender may be ahead of what the receiver has said
/// it holds. Keeps a slow radio from being buried.
const AHEAD: u32 = 8;
/// A file smaller than this is a small file: its pieces go before those
/// of bigger files, though always after chat.
pub(crate) const SMALL_FILE: u64 = 1024 * 1024;
/// How far past its first gap a receiver holds pieces that came early.
/// Anything further is left for the sender to send again later.
const HOLD_AHEAD: u32 = 1024;
const MAX_NAME_BYTES: usize = 255;
const SHOWN_NAME_CHARS: usize = 120;
const PART: &str = ".part";

/// What two devices say to each other about a transfer. The pieces
/// themselves are not here: they travel as bytes, not as JSON.
#[derive(Serialize, Deserialize)]
#[serde(tag = "w", rename_all = "snake_case")]
pub(crate) enum Wire {
    Offer {
        id: String,
        name: String,
        size: u64,
        sha256: String,
        chunk: u32,
        /// A picture the receiver may open one time. Their device then
        /// deletes it.
        #[serde(default, skip_serializing_if = "is_false")]
        once: bool,
        /// The root of the hash tree over the pieces, hex.
        #[serde(default, skip_serializing_if = "String::is_empty")]
        root: String,
    },
    /// "I have opened the picture you sent to be seen once, and it is
    /// gone from this device."
    Viewed {
        id: String,
    },
    Answer {
        id: String,
        accept: bool,
    },
    /// "I hold the first `have` pieces, and these past them."
    Ack {
        id: String,
        have: u32,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        also: Vec<u32>,
    },
    /// "I hold these, and whatever you sent besides did not come. Send
    /// the rest again." Said when a new way between the two may have
    /// opened, by a receiver who cannot tell the sender face to face.
    Again {
        id: String,
        have: u32,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        also: Vec<u32>,
    },
    Cancel {
        id: String,
    },
    /// "What arrived was not what you offered."
    Failed {
        id: String,
    },
}

impl Wire {
    /// Whether this must be kept and sent again until it arrives. An Ack
    /// need not be: the next one says more.
    pub fn kept(&self) -> bool {
        !matches!(self, Wire::Ack { .. } | Wire::Again { .. })
    }
}

fn is_false(flag: &bool) -> bool {
    !*flag
}

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum State {
    /// Sent an offer, waiting for an answer.
    Offered,
    /// Received an offer, waiting for the user.
    Asked,
    Sending,
    Receiving,
    Paused,
    Done,
    Declined,
    Cancelled,
    Failed,
}

#[derive(Clone, Serialize, Deserialize)]
struct Transfer {
    incoming: bool,
    /// The other person, by key.
    with: String,
    name: String,
    size: u64,
    sha256: String,
    chunk: u32,
    state: State,
    /// Pieces the receiver holds from the start with no gap. For a file
    /// being sent, this is what they last said.
    have: u32,
    /// Pieces past the first gap that are held too, in order.
    #[serde(default)]
    also: Vec<u32>,
    /// The root of the hash tree over the pieces, hex. Empty for a
    /// transfer from before there was one: its pieces are checked only
    /// by the whole file's hash.
    #[serde(default)]
    root: String,
    /// Where the file is, or will be. Empty for an offer not yet accepted.
    path: String,
    /// To be opened one time by the receiver, and then deleted there.
    #[serde(default)]
    once: bool,
    /// It has been opened, and the receiver's copy is gone.
    #[serde(default)]
    viewed: bool,
}

impl Transfer {
    fn pieces(&self) -> u32 {
        self.size.div_ceil(self.chunk as u64) as u32
    }

    fn piece_len(&self, index: u32) -> usize {
        let start = index as u64 * self.chunk as u64;
        (self.size - start).min(self.chunk as u64) as usize
    }

    fn partial(&self) -> PathBuf {
        PathBuf::from(format!("{}{PART}", self.path))
    }

    fn holds(&self, index: u32) -> bool {
        index < self.have || self.also.binary_search(&index).is_ok()
    }

    /// Notes that the receiver holds `have` from the start, and `also`
    /// past that. What was held before stays held: a word that arrived
    /// late, by a slower way, says less, not that pieces were lost.
    fn hold(&mut self, have: u32, also: &[u32]) {
        let pieces = self.pieces();
        self.have = self.have.max(have.min(pieces));
        self.also.extend(also.iter().copied().filter(|&i| i < pieces));
        self.also.sort_unstable();
        self.also.dedup();
        while self.also.first() == Some(&self.have) {
            self.also.remove(0);
            self.have += 1;
        }
        let have = self.have;
        self.also.retain(|&i| i > have);
    }

    /// How much of the file is held.
    fn done(&self) -> u64 {
        let start = (self.have as u64 * self.chunk as u64).min(self.size);
        start
            + self
                .also
                .iter()
                .map(|&i| self.piece_len(i) as u64)
                .sum::<u64>()
    }

    fn view(&self, id: &str) -> Value {
        json!({
            "id": id,
            "incoming": self.incoming,
            "with": self.with,
            "name": self.name,
            "size": self.size,
            "done": self.done(),
            "state": self.state,
            "path": self.path,
            "once": self.once,
            "viewed": self.viewed,
        })
    }
}

/// What is known only while the app runs: how far ahead each send has
/// got, the running hash of each file coming in, and the hash tree of
/// each file going out.
#[derive(Default)]
pub(crate) struct Live {
    next: HashMap<String, u32>,
    hashing: HashMap<String, (Sha256, u32)>,
    trees: HashMap<String, Tree>,
}

/// One piece ready to go: its bytes, and whether it is part of a small
/// file, whose pieces go first.
pub(crate) struct Piece {
    pub bytes: Vec<u8>,
    pub small: bool,
}

/// A hash tree over the pieces of a file. The leaves are the pieces'
/// hashes, made up to a power of two with blanks; each node above is the
/// hash of the two below it. Leaves and nodes are hashed with different
/// first bytes, so one cannot pass for the other.
pub(crate) struct Tree {
    /// From the leaves up to the root.
    levels: Vec<Vec<[u8; 32]>>,
}

const BLANK: [u8; 32] = [0; 32];

fn leaf_hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update([0u8]);
    hasher.update(data);
    hasher.finalize().into()
}

fn node_hash(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update([1u8]);
    hasher.update(left);
    hasher.update(right);
    hasher.finalize().into()
}

/// How many hashes tie one piece to the root, for a file of `pieces`.
fn depth(pieces: u32) -> usize {
    (pieces.max(1) as u64).next_power_of_two().trailing_zeros() as usize
}

impl Tree {
    fn new(leaves: &[[u8; 32]]) -> Self {
        let width = (leaves.len().max(1)).next_power_of_two();
        let mut level = leaves.to_vec();
        level.resize(width, BLANK);
        let mut levels = vec![level];
        while levels.last().expect("there is always one").len() > 1 {
            let below = levels.last().expect("there is always one");
            let above = below
                .chunks(2)
                .map(|pair| node_hash(&pair[0], &pair[1]))
                .collect();
            levels.push(above);
        }
        Self { levels }
    }

    fn from_bytes(bytes: &[u8]) -> Self {
        let leaves: Vec<[u8; 32]> = bytes.as_chunks::<32>().0.to_vec();
        Self::new(&leaves)
    }

    fn root(&self) -> [u8; 32] {
        self.levels.last().expect("there is always one")[0]
    }

    /// The hashes beside the path from one leaf to the root.
    fn proof(&self, index: u32) -> Vec<[u8; 32]> {
        let mut at = index as usize;
        let mut out = Vec::with_capacity(self.levels.len() - 1);
        for level in &self.levels[..self.levels.len() - 1] {
            out.push(level[at ^ 1]);
            at /= 2;
        }
        out
    }
}

/// Whether `data` is the piece at `index` of the file whose tree has
/// `root`, as `proof` shows.
fn verify(root: &[u8; 32], index: u32, data: &[u8], proof: &[[u8; 32]]) -> bool {
    let mut node = leaf_hash(data);
    let mut at = index;
    for sibling in proof {
        node = if at.is_multiple_of(2) {
            node_hash(&node, sibling)
        } else {
            node_hash(sibling, &node)
        };
        at /= 2;
    }
    at == 0 && &node == root
}

/// What one arriving message or piece led to.
#[derive(Default)]
pub(crate) struct Outcome {
    /// To send back to whoever sent it.
    pub replies: Vec<Wire>,
    /// The transfer that now looks different, if any.
    pub changed: Option<String>,
    /// A new offer, to show in the chat: id, name, size.
    pub offered: Option<(String, String, u64)>,
}

pub(crate) struct Files<'a> {
    pub vault: &'a Vault,
    pub live: &'a mut Live,
}

fn invalid(what: &str) -> CoreError {
    CoreError::Invalid(what.to_string())
}

fn file_id(text: &str) -> Result<[u8; 16]> {
    hexcode::decode_exact::<16>(text).map_err(|_| invalid("that is not a transfer"))
}

/// A name that is safe to use for a file in a folder, whatever the sender
/// called it. It can never point somewhere else.
pub(crate) fn safe_name(name: &str) -> String {
    let last = name.rsplit(['/', '\\']).next().unwrap_or_default();
    let cleaned: String = last
        .chars()
        .filter(|c| !c.is_control() && !['<', '>', ':', '"', '|', '?', '*'].contains(c))
        .collect();
    let cleaned = cleaned.trim_matches(|c: char| c == ' ' || c == '.');
    let mut name: String = cleaned.chars().take(SHOWN_NAME_CHARS).collect();
    if name.is_empty() {
        name = "file".to_string();
    }
    // Names Windows keeps for devices, with or without an extension.
    let stem = name
        .split('.')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase();
    let reserved = ["con", "prn", "aux", "nul"].contains(&stem.as_str())
        || (stem.len() == 4
            && (stem.starts_with("com") || stem.starts_with("lpt"))
            && stem.ends_with(|c: char| c.is_ascii_digit()));
    if reserved {
        name.insert(0, '_');
    }
    name
}

/// A path in `dir` that nothing is using yet: "photo.jpg", then
/// "photo (1).jpg", and so on.
pub(crate) fn free_path(dir: &Path, name: &str) -> PathBuf {
    let (stem, extension) = match name.rfind('.') {
        Some(dot) if dot > 0 => (&name[..dot], &name[dot..]),
        _ => (name, ""),
    };
    let mut number = 0;
    loop {
        let candidate = match number {
            0 => dir.join(name),
            n => dir.join(format!("{stem} ({n}){extension}")),
        };
        let partial = PathBuf::from(format!("{}{PART}", candidate.display()));
        if !candidate.exists() && !partial.exists() {
            return candidate;
        }
        number += 1;
    }
}

/// The whole file's hash and each piece's, read in one pass.
fn hashes_of(path: &Path, size: u64, chunk: u32) -> std::io::Result<(Sha256, Vec<[u8; 32]>)> {
    let mut whole = Sha256::new();
    let mut leaves = Vec::with_capacity(size.div_ceil(chunk as u64) as usize);
    let mut file = File::open(path)?.take(size);
    let mut buffer = vec![0u8; chunk as usize];
    loop {
        let mut filled = 0;
        while filled < buffer.len() {
            let read = file.read(&mut buffer[filled..])?;
            if read == 0 {
                break;
            }
            filled += read;
        }
        if filled == 0 {
            return Ok((whole, leaves));
        }
        whole.update(&buffer[..filled]);
        leaves.push(leaf_hash(&buffer[..filled]));
        if filled < buffer.len() {
            return Ok((whole, leaves));
        }
    }
}

fn hash_of(path: &Path, bytes: u64) -> std::io::Result<Sha256> {
    let mut hasher = Sha256::new();
    let mut file = File::open(path)?.take(bytes);
    let mut buffer = vec![0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            return Ok(hasher);
        }
        hasher.update(&buffer[..read]);
    }
}

/// For files moving to or from people out of range: what to tell each
/// sender, and who is being sent something.
pub(crate) type Elsewhere = (Vec<(String, Wire)>, Vec<String>);

impl Files<'_> {
    fn load(&self, id: &str) -> Result<Option<Transfer>> {
        match self.vault.get(FILES, &file_id(id)?)? {
            None => Ok(None),
            Some(bytes) => serde_json::from_slice(&bytes)
                .map(Some)
                .map_err(|_| CoreError::Corrupt("a saved transfer is unreadable".into())),
        }
    }

    fn save(&self, id: &str, transfer: &Transfer) -> Result<()> {
        let bytes = serde_json::to_vec(transfer).expect("a transfer is plain data");
        self.vault.put(FILES, &file_id(id)?, &bytes)
    }

    fn all(&self) -> Result<Vec<(String, Transfer)>> {
        self.vault
            .list(FILES)?
            .into_iter()
            .map(|(id, bytes)| {
                let transfer = serde_json::from_slice(&bytes)
                    .map_err(|_| CoreError::Corrupt("a saved transfer is unreadable".into()))?;
                Ok((hexcode::encode(&id), transfer))
            })
            .collect()
    }

    pub fn list(&self) -> Result<Value> {
        Ok(self
            .all()?
            .iter()
            .map(|(id, transfer)| transfer.view(id))
            .collect())
    }

    // What the user does

    /// Offers a file to someone. Returns the new transfer's id, the name
    /// it goes under, its size, and what to send them.
    pub fn offer(
        &mut self,
        to: &str,
        path: &Path,
        name: Option<&str>,
        once: bool,
    ) -> Result<(String, String, u64, Wire)> {
        let unreadable = |_| invalid("that file cannot be read");
        let size = fs::metadata(path).map_err(unreadable)?.len();
        if size == 0 {
            return Err(invalid("an empty file cannot be sent"));
        }
        let name = safe_name(name.unwrap_or_else(|| {
            path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or_default()
        }));
        let (whole, leaves) = hashes_of(path, size, PIECE).map_err(unreadable)?;
        let sha256 = hexcode::encode(&whole.finalize());
        let tree = Tree::new(&leaves);
        let root = hexcode::encode(&tree.root());
        let id = hexcode::encode(random_bytes::<16>()?.as_slice());
        self.vault.put(TREES, &file_id(&id)?, &leaves.concat())?;
        self.live.trees.insert(id.clone(), tree);
        let transfer = Transfer {
            incoming: false,
            with: to.to_string(),
            name: name.clone(),
            size,
            sha256: sha256.clone(),
            chunk: PIECE,
            state: State::Offered,
            have: 0,
            also: Vec::new(),
            root: root.clone(),
            path: path.to_string_lossy().into_owned(),
            once,
            viewed: false,
        };
        self.save(&id, &transfer)?;
        Ok((
            id.clone(),
            name.clone(),
            size,
            Wire::Offer {
                id,
                name,
                size,
                sha256,
                chunk: PIECE,
                once,
                root,
            },
        ))
    }

    /// The receiver has opened a picture sent to be seen once. Its file
    /// is deleted from this device and the transfer remembers only that
    /// it was seen. Returns who to tell.
    pub fn viewed(&self, id: &str) -> Result<(String, Wire)> {
        let mut transfer = self.incoming(id, State::Done)?;
        if !transfer.once || transfer.viewed {
            return Err(invalid("there is no such picture waiting to be seen"));
        }
        // Gone first, and only then recorded as seen. If the file cannot
        // be deleted it is not passed off as deleted.
        match fs::remove_file(&transfer.path) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Err(invalid("the picture could not be deleted")),
        }
        transfer.viewed = true;
        transfer.path = String::new();
        self.save(id, &transfer)?;
        Ok((transfer.with, Wire::Viewed { id: id.to_string() }))
    }

    fn incoming(&self, id: &str, state: State) -> Result<Transfer> {
        match self.load(id)? {
            Some(transfer) if transfer.incoming && transfer.state == state => Ok(transfer),
            _ => Err(invalid("there is no such file waiting")),
        }
    }

    /// Says yes to an offer. The file will be written into `dir`.
    pub fn accept(&self, id: &str, dir: &Path) -> Result<(String, Wire)> {
        let mut transfer = self.incoming(id, State::Asked)?;
        fs::create_dir_all(dir).map_err(|_| invalid("that folder cannot be written to"))?;
        let path = free_path(dir, &transfer.name);
        transfer.path = path.to_string_lossy().into_owned();
        File::create(transfer.partial())
            .map_err(|_| invalid("that folder cannot be written to"))?;
        transfer.state = State::Receiving;
        self.save(id, &transfer)?;
        Ok((
            transfer.with,
            Wire::Answer {
                id: id.to_string(),
                accept: true,
            },
        ))
    }

    pub fn decline(&self, id: &str) -> Result<(String, Wire)> {
        let mut transfer = self.incoming(id, State::Asked)?;
        transfer.state = State::Declined;
        self.save(id, &transfer)?;
        Ok((
            transfer.with,
            Wire::Answer {
                id: id.to_string(),
                accept: false,
            },
        ))
    }

    /// Stops a transfer from either end. Returns who to tell, if it was
    /// still going.
    pub fn cancel(&mut self, id: &str) -> Result<Option<(String, Wire)>> {
        let Some(mut transfer) = self.load(id)? else {
            return Ok(None);
        };
        if !self.stop(id, &mut transfer, State::Cancelled)? {
            return Ok(None);
        }
        Ok(Some((transfer.with, Wire::Cancel { id: id.to_string() })))
    }

    /// Ends a transfer that is still going. A half-received file is
    /// removed. False if it had already ended.
    fn stop(&mut self, id: &str, transfer: &mut Transfer, state: State) -> Result<bool> {
        if matches!(
            transfer.state,
            State::Done | State::Declined | State::Cancelled | State::Failed
        ) {
            return Ok(false);
        }
        if transfer.incoming && !transfer.path.is_empty() {
            let _ = fs::remove_file(transfer.partial());
        }
        transfer.state = state;
        self.live.next.remove(id);
        self.live.hashing.remove(id);
        self.forget_tree(id)?;
        self.save(id, transfer)?;
        Ok(true)
    }

    /// Lets go of a sent file's tree once nothing more will be sent.
    fn forget_tree(&mut self, id: &str) -> Result<()> {
        self.live.trees.remove(id);
        self.vault.delete(TREES, &file_id(id)?)
    }

    /// The tree of a file being sent, from memory or from the vault.
    /// None for a transfer from before there were trees.
    fn tree(&mut self, id: &str) -> Result<Option<&Tree>> {
        if !self.live.trees.contains_key(id) {
            let Some(leaves) = self.vault.get(TREES, &file_id(id)?)? else {
                return Ok(None);
            };
            self.live
                .trees
                .insert(id.to_string(), Tree::from_bytes(&leaves));
        }
        Ok(self.live.trees.get(id))
    }

    /// Holds a send where it is, or lets it go on.
    pub fn pause(&mut self, id: &str, paused: bool) -> Result<()> {
        let (from, to) = if paused {
            (State::Sending, State::Paused)
        } else {
            (State::Paused, State::Sending)
        };
        match self.load(id)? {
            Some(mut transfer) if !transfer.incoming && transfer.state == from => {
                transfer.state = to;
                // Whatever was on its way when it paused may not have
                // arrived. Start again from what they said they hold.
                self.live.next.remove(id);
                self.save(id, &transfer)
            }
            _ => Err(invalid("that file is not being sent")),
        }
    }

    // What the other device says

    /// Takes in one message about a transfer from `from`. `contact` says
    /// whether they are someone the user has accepted.
    pub fn receive(&mut self, from: &str, contact: bool, wire: Wire) -> Result<Outcome> {
        let mut outcome = Outcome::default();
        match wire {
            Wire::Viewed { id } => {
                // Believed only from the one it was sent to, about a
                // picture that was sent to be seen once.
                let Some(mut transfer) = self.ours(&id, from, false)? else {
                    return Ok(outcome);
                };
                if !transfer.once || transfer.viewed {
                    return Ok(outcome);
                }
                transfer.viewed = true;
                self.save(&id, &transfer)?;
                outcome.changed = Some(id);
            }
            Wire::Offer {
                id,
                name,
                size,
                sha256,
                chunk,
                once,
                root,
            } => {
                // Files come from contacts only, like messages.
                let sound = contact
                    && file_id(&id).is_ok()
                    && size > 0
                    && (1024..=1024 * 1024).contains(&chunk)
                    && size.div_ceil(chunk as u64) <= u32::MAX as u64
                    && hexcode::decode_exact::<32>(&sha256).is_ok()
                    && (root.is_empty() || hexcode::decode_exact::<32>(&root).is_ok())
                    && name.len() <= MAX_NAME_BYTES;
                // An offer can arrive twice. It is one offer.
                if !sound || self.load(&id)?.is_some() {
                    return Ok(outcome);
                }
                let name = safe_name(&name);
                let transfer = Transfer {
                    incoming: true,
                    with: from.to_string(),
                    name: name.clone(),
                    size,
                    sha256,
                    chunk,
                    state: State::Asked,
                    have: 0,
                    also: Vec::new(),
                    root,
                    path: String::new(),
                    once,
                    viewed: false,
                };
                self.save(&id, &transfer)?;
                outcome.offered = Some((id.clone(), name, size));
                outcome.changed = Some(id);
            }
            Wire::Answer { id, accept } => {
                let Some(mut transfer) = self.ours(&id, from, false)? else {
                    return Ok(outcome);
                };
                if transfer.state != State::Offered {
                    return Ok(outcome);
                }
                transfer.state = if accept {
                    State::Sending
                } else {
                    State::Declined
                };
                self.save(&id, &transfer)?;
                outcome.changed = Some(id);
            }
            Wire::Ack { id, have, also } => {
                let Some(mut transfer) = self.ours(&id, from, false)? else {
                    return Ok(outcome);
                };
                if !matches!(transfer.state, State::Sending | State::Paused) {
                    return Ok(outcome);
                }
                let before = (transfer.have, transfer.also.clone());
                transfer.hold(have, &also);
                if (transfer.have, &transfer.also) == (before.0, &before.1) {
                    return Ok(outcome);
                }
                if transfer.have == transfer.pieces() {
                    transfer.state = State::Done;
                    self.live.next.remove(&id);
                    self.forget_tree(&id)?;
                }
                self.save(&id, &transfer)?;
                outcome.changed = Some(id);
            }
            Wire::Again { id, have, also } => {
                let Some(mut transfer) = self.ours(&id, from, false)? else {
                    return Ok(outcome);
                };
                if transfer.state != State::Sending {
                    return Ok(outcome);
                }
                let before = (transfer.have, transfer.also.clone());
                transfer.hold(have, &also);
                if (transfer.have, &transfer.also) != (before.0, &before.1) {
                    if transfer.have == transfer.pieces() {
                        transfer.state = State::Done;
                        self.forget_tree(&id)?;
                    }
                    self.save(&id, &transfer)?;
                    outcome.changed = Some(id.clone());
                }
                // Whatever was sent besides is to be sent again.
                self.live.next.remove(&id);
            }
            Wire::Cancel { id } => {
                let Some(mut transfer) = self.load(&id)?.filter(|t| t.with == from) else {
                    return Ok(outcome);
                };
                if self.stop(&id, &mut transfer, State::Cancelled)? {
                    outcome.changed = Some(id);
                }
            }
            Wire::Failed { id } => {
                let Some(mut transfer) = self.ours(&id, from, false)? else {
                    return Ok(outcome);
                };
                if self.stop(&id, &mut transfer, State::Failed)? {
                    outcome.changed = Some(id);
                }
            }
        }
        Ok(outcome)
    }

    /// A transfer with this person, in this direction.
    fn ours(&self, id: &str, with: &str, incoming: bool) -> Result<Option<Transfer>> {
        if file_id(id).is_err() {
            return Ok(None);
        }
        Ok(self
            .load(id)?
            .filter(|t| t.with == with && t.incoming == incoming))
    }

    /// Takes in one piece: sixteen bytes of id, four of position, one
    /// saying how many hashes follow, those hashes, and the data. A piece
    /// may come in any order, by any way. One that is not the piece
    /// offered at its place is not written.
    pub fn piece(&mut self, from: &str, bytes: &[u8]) -> Result<Outcome> {
        let mut outcome = Outcome::default();
        if bytes.len() <= 21 {
            return Ok(outcome);
        }
        let id = hexcode::encode(&bytes[..16]);
        let index = u32::from_be_bytes(bytes[16..20].try_into().expect("four bytes were taken"));
        let count = bytes[20] as usize;
        let Some(data) = bytes.get(21 + count * 32..).filter(|d| !d.is_empty()) else {
            return Ok(outcome);
        };
        let proof: Vec<[u8; 32]> = bytes[21..21 + count * 32].as_chunks::<32>().0.to_vec();
        let Some(mut transfer) = self.ours(&id, from, true)? else {
            return Ok(outcome);
        };
        if transfer.state != State::Receiving {
            return Ok(outcome);
        }
        let pieces = transfer.pieces();
        if index >= pieces
            || index >= transfer.have.saturating_add(HOLD_AHEAD)
            || data.len() != transfer.piece_len(index)
        {
            return Ok(outcome);
        }
        if transfer.holds(index) {
            // Already here, perhaps by another way. Saying again what is
            // held lets the sender find its place.
            outcome.replies.push(Wire::Ack {
                id,
                have: transfer.have,
                also: transfer.also.clone(),
            });
            return Ok(outcome);
        }
        if !transfer.root.is_empty() {
            let root = hexcode::decode_exact::<32>(&transfer.root)?;
            if proof.len() != depth(pieces) || !verify(&root, index, data, &proof) {
                // Sealed and signed by the sender, so nobody on the way
                // changed it: the file itself is not what was offered.
                self.stop(&id, &mut transfer, State::Failed)?;
                outcome.replies.push(Wire::Failed { id: id.clone() });
                outcome.changed = Some(id);
                return Ok(outcome);
            }
        }

        let partial = transfer.partial();
        let at = index as u64 * transfer.chunk as u64;
        let written = (|| -> std::io::Result<()> {
            let mut file = OpenOptions::new().write(true).open(&partial)?;
            file.seek(SeekFrom::Start(at))?;
            file.write_all(data)?;
            file.sync_data()
        })();
        if written.is_err() {
            self.stop(&id, &mut transfer, State::Failed)?;
            outcome.replies.push(Wire::Failed { id: id.clone() });
            outcome.changed = Some(id);
            return Ok(outcome);
        }
        let had = transfer.have;
        transfer.hold(0, &[index]);

        // The whole file's hash is kept running over the part held from
        // the start. After a restart it is worked out again from disk.
        let mut hasher = match self.live.hashing.remove(&id) {
            Some((hasher, upto)) if upto == had => hasher,
            _ => hash_of(&partial, had as u64 * transfer.chunk as u64)
                .map_err(|_| CoreError::Storage("a half-received file cannot be read".into()))?,
        };
        if transfer.have > had {
            let from_at = had as u64 * transfer.chunk as u64;
            let upto = (transfer.have as u64 * transfer.chunk as u64).min(transfer.size);
            let read = (|| -> std::io::Result<()> {
                let mut file = File::open(&partial)?;
                file.seek(SeekFrom::Start(from_at))?;
                let mut rest = file.take(upto - from_at);
                let mut buffer = vec![0u8; 64 * 1024];
                loop {
                    let read = rest.read(&mut buffer)?;
                    if read == 0 {
                        return Ok(());
                    }
                    hasher.update(&buffer[..read]);
                }
            })();
            read.map_err(|_| CoreError::Storage("a half-received file cannot be read".into()))?;
        }

        if transfer.have < pieces {
            self.live
                .hashing
                .insert(id.clone(), (hasher, transfer.have));
            self.save(&id, &transfer)?;
            outcome.replies.push(Wire::Ack {
                id: id.clone(),
                have: transfer.have,
                also: transfer.also.clone(),
            });
        } else if hexcode::encode(&hasher.finalize()) == transfer.sha256
            && OpenOptions::new()
                .write(true)
                .open(&partial)
                .and_then(|file| file.set_len(transfer.size))
                .is_ok()
            && fs::rename(&partial, &transfer.path).is_ok()
        {
            transfer.state = State::Done;
            self.save(&id, &transfer)?;
            outcome.replies.push(Wire::Ack {
                id: id.clone(),
                have: transfer.have,
                also: Vec::new(),
            });
        } else {
            // Not the file that was offered. It is not kept.
            self.stop(&id, &mut transfer, State::Failed)?;
            outcome.replies.push(Wire::Failed { id: id.clone() });
        }
        outcome.changed = Some(id);
        Ok(outcome)
    }

    // Keeping things moving

    /// The pieces to send `peer` now: for each file being sent to them, as
    /// many as keep the sender no more than a few ahead of what they hold,
    /// skipping any they already have.
    pub fn pieces_for(&mut self, peer: &str) -> Result<Vec<Piece>> {
        let mut out = Vec::new();
        for (id, mut transfer) in self.all()? {
            if transfer.incoming || transfer.with != peer || transfer.state != State::Sending {
                continue;
            }
            let mut next = self
                .live
                .next
                .get(&id)
                .copied()
                .unwrap_or(0)
                .max(transfer.have);
            let stop = (transfer.have + AHEAD)
                .saturating_add(transfer.also.len() as u32)
                .min(transfer.pieces());
            let small = transfer.size < SMALL_FILE;
            while next < stop {
                if transfer.holds(next) {
                    next += 1;
                    continue;
                }
                let mut data = vec![0u8; transfer.piece_len(next)];
                let read = (|| -> std::io::Result<()> {
                    let mut file = File::open(&transfer.path)?;
                    file.seek(SeekFrom::Start(next as u64 * transfer.chunk as u64))?;
                    file.read_exact(&mut data)
                })();
                // If the file changed since it was offered, the piece goes
                // all the same: the receiver checks it against the offer,
                // refuses it and says so, and both ends stop.
                let proof = match (read, self.tree(&id)?) {
                    (Err(_), _) => None,
                    (Ok(()), None) => Some(Vec::new()),
                    (Ok(()), Some(tree)) => Some(tree.proof(next)),
                };
                let Some(proof) = proof else {
                    // The file has gone, or shrunk. Nothing more can be
                    // sent, so it ends here.
                    self.stop(&id, &mut transfer, State::Failed)?;
                    break;
                };
                let mut piece = file_id(&id)?.to_vec();
                piece.extend_from_slice(&next.to_be_bytes());
                piece.push(proof.len() as u8);
                for hash in &proof {
                    piece.extend_from_slice(hash);
                }
                piece.extend_from_slice(&data);
                out.push(Piece {
                    bytes: piece,
                    small,
                });
                next += 1;
            }
            if transfer.state == State::Sending {
                self.live.next.insert(id, next);
            }
        }
        Ok(out)
    }

    /// A device has just come into range. Returns what to tell it about
    /// files coming from it, so it knows where to carry on from.
    pub fn met(&mut self, peer: &str) -> Result<Vec<Wire>> {
        let mut say = Vec::new();
        for (id, transfer) in self.all()? {
            if transfer.with != peer {
                continue;
            }
            if transfer.incoming && transfer.state == State::Receiving {
                say.push(Wire::Ack {
                    id,
                    have: transfer.have,
                    also: transfer.also,
                });
            } else if !transfer.incoming {
                // Whatever was on its way when the link dropped is lost.
                self.live.next.remove(&id);
            }
        }
        Ok(say)
    }

    /// One of two connections to `peer` has dropped and the other still
    /// reaches them. Whatever was on the lost one is gone. Returns what to
    /// tell them about files coming from them, so they send again from
    /// where this device had got to; and forgets how far ahead this device
    /// had sent, so it does the same for them.
    pub fn lost_a_way(&mut self, peer: &str) -> Result<Vec<Wire>> {
        let mut say = Vec::new();
        for (id, transfer) in self.all()? {
            if transfer.with != peer {
                continue;
            }
            if transfer.incoming && transfer.state == State::Receiving {
                say.push(Wire::Again {
                    id,
                    have: transfer.have,
                    also: transfer.also,
                });
            } else if !transfer.incoming {
                self.live.next.remove(&id);
            }
        }
        Ok(say)
    }

    /// Someone new has come into range, who may be on the way to people
    /// who are not. For files moving to or from anyone `in_range` does not
    /// hold: returns what to tell the senders, so they know where to carry
    /// on from, and who is being sent a file, so its next pieces can be
    /// tried again by the new way.
    pub fn out_of_range(&mut self, in_range: impl Fn(&str) -> bool) -> Result<Elsewhere> {
        let (mut say, mut sending) = (Vec::new(), Vec::new());
        for (id, transfer) in self.all()? {
            if in_range(&transfer.with) {
                continue;
            }
            if transfer.incoming && transfer.state == State::Receiving {
                say.push((
                    transfer.with,
                    Wire::Again {
                        id,
                        have: transfer.have,
                        also: transfer.also,
                    },
                ));
            } else if !transfer.incoming && transfer.state == State::Sending {
                // Whatever was on its way by the old way is lost.
                self.live.next.remove(&id);
                if !sending.contains(&transfer.with) {
                    sending.push(transfer.with);
                }
            }
        }
        Ok((say, sending))
    }

    /// Removes every file this device received, finished or not. Part of
    /// wiping everything.
    pub fn erase_received(&self) -> Result<()> {
        for (_, transfer) in self.all()? {
            if transfer.incoming && !transfer.path.is_empty() {
                let _ = fs::remove_file(&transfer.path);
                let _ = fs::remove_file(transfer.partial());
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_name_is_made_safe_whatever_it_was() {
        for (given, safe) in [
            ("photo.jpg", "photo.jpg"),
            ("../../evil.exe", "evil.exe"),
            ("..\\..\\evil.exe", "evil.exe"),
            ("C:\\Windows\\evil.exe", "evil.exe"),
            ("/etc/passwd", "passwd"),
            ("..", "file"),
            ("", "file"),
            ("   ", "file"),
            ("a\u{0}b\nc", "abc"),
            ("what?*.txt", "what.txt"),
            ("con", "_con"),
            ("NUL.txt", "_NUL.txt"),
            ("com1", "_com1"),
            ("comet.txt", "comet.txt"),
            ("trailing. . .", "trailing"),
        ] {
            assert_eq!(safe_name(given), safe, "{given:?}");
        }
        assert_eq!(
            safe_name(&"x".repeat(500)).chars().count(),
            SHOWN_NAME_CHARS
        );
    }

    #[test]
    fn a_free_path_never_reuses_a_name() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(free_path(dir.path(), "a.txt"), dir.path().join("a.txt"));
        fs::write(dir.path().join("a.txt"), b"x").unwrap();
        assert_eq!(free_path(dir.path(), "a.txt"), dir.path().join("a (1).txt"));
        // A file still arriving holds its name too.
        fs::write(dir.path().join("a (1).txt.part"), b"x").unwrap();
        assert_eq!(free_path(dir.path(), "a.txt"), dir.path().join("a (2).txt"));
        assert_eq!(free_path(dir.path(), "noext"), dir.path().join("noext"));
    }

    fn files<'a>(vault: &'a Vault, live: &'a mut Live) -> Files<'a> {
        Files { vault, live }
    }

    /// What Mira is sent: three pieces of 1024 bytes, each different.
    fn sent() -> Vec<u8> {
        (0..3 * 1024).map(|i| (i / 1024) as u8 + 5).collect()
    }

    fn tree_of(data: &[u8]) -> Tree {
        let leaves: Vec<[u8; 32]> = data.chunks(1024).map(leaf_hash).collect();
        Tree::new(&leaves)
    }

    /// A transfer Mira has accepted from "aa".
    fn accepted(dir: &Path, vault: &Vault, live: &mut Live) -> String {
        let data = sent();
        let id = "11".repeat(16);
        let offer = Wire::Offer {
            id: id.clone(),
            name: "x.bin".into(),
            size: data.len() as u64,
            sha256: hexcode::encode(&Sha256::digest(&data)),
            chunk: 1024,
            once: false,
            root: hexcode::encode(&tree_of(&data).root()),
        };
        let mut files = files(vault, live);
        files.receive("aa", true, offer).unwrap();
        files.accept(&id, dir).unwrap();
        id
    }

    /// Piece `index` as the sender sends it, with `data` in place of
    /// what is really there.
    fn piece(id: &str, index: u32, data: &[u8]) -> Vec<u8> {
        let proof = tree_of(&sent()).proof(index.min(2));
        let mut bytes = hexcode::decode(id).unwrap();
        bytes.extend_from_slice(&index.to_be_bytes());
        bytes.push(proof.len() as u8);
        for hash in &proof {
            bytes.extend_from_slice(hash);
        }
        bytes.extend_from_slice(data);
        bytes
    }

    fn real(index: usize) -> Vec<u8> {
        sent()[index * 1024..(index + 1) * 1024].to_vec()
    }

    fn state(vault: &Vault, live: &mut Live, id: &str) -> Value {
        files(vault, live)
            .list()
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == id)
            .unwrap()["state"]
            .clone()
    }

    fn have(vault: &Vault, live: &mut Live, id: &str) -> u64 {
        files(vault, live)
            .list()
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == id)
            .unwrap()["done"]
            .as_u64()
            .unwrap()
    }

    #[test]
    fn pieces_out_of_place_too_long_or_from_someone_else_are_not_written() {
        let dir = tempfile::tempdir().unwrap();
        let vault_dir = tempfile::tempdir().unwrap();
        let vault = Vault::open(vault_dir.path(), &[7u8; 32]).unwrap();
        let mut live = Live::default();
        let id = accepted(dir.path(), &vault, &mut live);
        let good = real(0);

        let mut f = files(&vault, &mut live);
        f.piece("aa", &piece(&id, 3, &good)).unwrap(); // past the end
        f.piece("aa", &piece(&id, 0, &[5u8; 1025])).unwrap(); // too long
        f.piece("aa", &piece(&id, 0, &[5u8; 10])).unwrap(); // too short
        f.piece("bb", &piece(&id, 0, &good)).unwrap(); // not the sender
        f.piece("aa", &piece(&"22".repeat(16), 0, &good)).unwrap(); // no such file
        f.piece("aa", &[1, 2, 3]).unwrap(); // not a piece at all
        assert_eq!(have(&vault, &mut live, &id), 0);

        let mut f = files(&vault, &mut live);
        let taken = f.piece("aa", &piece(&id, 0, &good)).unwrap();
        assert!(matches!(taken.replies[..], [Wire::Ack { have: 1, .. }]));
        // The same piece again is not written twice, and the sender is
        // told where things stand.
        let again = f.piece("aa", &piece(&id, 0, &good)).unwrap();
        assert!(matches!(again.replies[..], [Wire::Ack { have: 1, .. }]));
        assert_eq!(have(&vault, &mut live, &id), 1024);
    }

    #[test]
    fn pieces_can_come_in_any_order_and_the_file_is_rebuilt() {
        let dir = tempfile::tempdir().unwrap();
        let vault_dir = tempfile::tempdir().unwrap();
        let vault = Vault::open(vault_dir.path(), &[7u8; 32]).unwrap();
        let mut live = Live::default();
        let id = accepted(dir.path(), &vault, &mut live);

        let mut f = files(&vault, &mut live);
        let last = f.piece("aa", &piece(&id, 2, &real(2))).unwrap();
        match &last.replies[..] {
            [Wire::Ack { have: 0, also, .. }] => assert_eq!(also, &[2]),
            _ => panic!("the last piece is held, past a gap"),
        }
        let first = f.piece("aa", &piece(&id, 0, &real(0))).unwrap();
        assert!(matches!(first.replies[..], [Wire::Ack { have: 1, .. }]));
        let middle = f.piece("aa", &piece(&id, 1, &real(1))).unwrap();
        assert!(matches!(middle.replies[..], [Wire::Ack { have: 3, .. }]));
        assert_eq!(state(&vault, &mut live, &id), "done");
        assert_eq!(fs::read(dir.path().join("x.bin")).unwrap(), sent());
    }

    #[test]
    fn a_piece_that_is_not_the_one_offered_is_never_written() {
        let dir = tempfile::tempdir().unwrap();
        let vault_dir = tempfile::tempdir().unwrap();
        let vault = Vault::open(vault_dir.path(), &[7u8; 32]).unwrap();
        let mut live = Live::default();
        let id = accepted(dir.path(), &vault, &mut live);

        // The right length, in the right place, but not what was offered:
        // the second piece's data where the first belongs.
        let mut f = files(&vault, &mut live);
        let wrong = f.piece("aa", &piece(&id, 0, &real(1))).unwrap();
        assert!(matches!(wrong.replies[..], [Wire::Failed { .. }]));
        assert_eq!(state(&vault, &mut live, &id), "failed");
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
    }

    #[test]
    fn a_hash_tree_ties_each_piece_to_its_place() {
        for count in [1usize, 2, 3, 5, 8, 9] {
            let leaves: Vec<[u8; 32]> = (0..count).map(|i| leaf_hash(&[i as u8])).collect();
            let tree = Tree::new(&leaves);
            for i in 0..count as u32 {
                let proof = tree.proof(i);
                assert_eq!(proof.len(), depth(count as u32));
                assert!(verify(&tree.root(), i, &[i as u8], &proof), "{i} of {count}");
                assert!(!verify(&tree.root(), i, &[200], &proof));
                if count > 1 {
                    let other = (i + 1) % count as u32;
                    assert!(!verify(&tree.root(), other, &[i as u8], &proof));
                }
            }
        }
    }

    #[test]
    fn only_the_receiver_can_move_a_send_forward() {
        let dir = tempfile::tempdir().unwrap();
        let vault_dir = tempfile::tempdir().unwrap();
        let vault = Vault::open(vault_dir.path(), &[7u8; 32]).unwrap();
        let mut live = Live::default();
        let path = dir.path().join("out.bin");
        fs::write(&path, vec![1u8; 400_000]).unwrap();
        let mut f = files(&vault, &mut live);
        let (id, ..) = f.offer("mira", &path, None, false).unwrap();

        // Someone else says yes, and says it has all of it.
        f.receive(
            "eve",
            true,
            Wire::Answer {
                id: id.clone(),
                accept: true,
            },
        )
        .unwrap();
        f.receive(
            "eve",
            true,
            Wire::Ack {
                id: id.clone(),
                have: 99,
                also: Vec::new(),
            },
        )
        .unwrap();
        assert!(
            f.pieces_for("mira").unwrap().is_empty(),
            "not accepted by Mira, so nothing goes"
        );
        assert!(f.pieces_for("eve").unwrap().is_empty());

        f.receive(
            "mira",
            true,
            Wire::Answer {
                id: id.clone(),
                accept: true,
            },
        )
        .unwrap();
        assert_eq!(f.pieces_for("mira").unwrap().len(), AHEAD as usize);
        // No further until Mira says she holds some.
        assert!(f.pieces_for("mira").unwrap().is_empty());
        f.receive(
            "mira",
            true,
            Wire::Ack {
                id: id.clone(),
                have: 2,
                also: Vec::new(),
            },
        )
        .unwrap();
        assert_eq!(f.pieces_for("mira").unwrap().len(), 2);
    }
}
