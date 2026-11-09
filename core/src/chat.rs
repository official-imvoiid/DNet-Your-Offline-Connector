//! Chat requests, contacts, messages and verification.
//!
//! The rule everything here serves: nobody can message a person until that
//! person has accepted their chat request. It is enforced where messages
//! arrive, not only where they are sent, because a sender's app cannot be
//! trusted to be honest.
//!
//! This module moves no bytes. It turns actions into sealed envelopes for
//! some transport to carry, and turns envelopes that arrive into events.

use std::collections::{BTreeMap, HashMap};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::Digest;

use crate::envelope;
use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::identity::{IdentitySecret, PublicIdentity};
use crate::place::Place;
use crate::sas;
use crate::seal::random_bytes;
use crate::vault::Vault;

const PEOPLE: (&str, &[u8]) = ("chat", b"people");
/// What each contact last said about being away, and when they said it,
/// by their signing key. Kept apart from the contacts themselves.
const AWAY: (&str, &[u8]) = ("chat", b"away");
/// The longest reason for being away, as with ".afk lunch".
pub(crate) const MAX_AWAY_CHARS: usize = 120;
const THREAD: &str = "thread";
/// Contacts' profile photos, by their signing key.
const AVATAR: &str = "avatar";
/// People whose chat requests the user declined, by their signing key, and
/// until when a new request from them is quietly dropped.
const DECLINED: &str = "declined";
/// One-time link tokens the user has made and not yet seen used, with
/// when each runs out.
const INVITES: &str = "invites";
const INVITE_PREFIX: &str = "dnet:invite/";
/// Mixed into what a link's maker signs, so the signature cannot be taken
/// for one over anything else.
const INVITE_CONTEXT: &[u8] = b"dnet person link v1";
/// How long a person link works: one day.
pub(crate) const INVITE_LASTS: u64 = 24 * 60 * 60;

/// What a person link says, once its signature has been checked.
struct PersonLink {
    token: [u8; 16],
    expires: u64,
    identity: PublicIdentity,
}

/// Reads a person link: 1, token (16), end time (8), the maker's public
/// identity, and the maker's signature (64) over all that before it.
fn read_person_link(link: &str) -> Result<PersonLink> {
    let not_a_link = || CoreError::Invalid("that is not a DNet link".into());
    let bytes = link
        .trim()
        .strip_prefix(INVITE_PREFIX)
        .and_then(|hex| hexcode::decode(hex).ok())
        .ok_or_else(not_a_link)?;
    if bytes.len() < 1 + 16 + 8 + 1 + 64 || bytes[0] != 1 {
        return Err(not_a_link());
    }
    let (body, signature) = bytes.split_at(bytes.len() - 64);
    let identity = PublicIdentity::from_bytes(&body[25..]).map_err(|_| not_a_link())?;
    identity.verify().map_err(|_| not_a_link())?;
    let signed = [INVITE_CONTEXT, body].concat();
    crate::identity::verify_signature(&identity.signing_key, &signed, signature)
        .map_err(|_| not_a_link())?;
    Ok(PersonLink {
        token: body[1..17].try_into().expect("sixteen bytes were taken"),
        expires: u64::from_be_bytes(body[17..25].try_into().expect("eight bytes were taken")),
        identity,
    })
}

/// How long a declined person must wait before asking again: a few hours
/// the first time, a day the second, three days from then on. They are
/// never told.
pub(crate) fn decline_wait(times: u32) -> u64 {
    const HOUR: u64 = 60 * 60;
    match times {
        0 => 0,
        1 => 4 * HOUR,
        2 => 24 * HOUR,
        _ => 72 * HOUR,
    }
}

/// How often the user has declined someone, and until when a new request
/// from them is dropped.
#[derive(Default, Serialize, Deserialize)]
struct Declined {
    times: u32,
    until: u64,
}
/// How many built-in pictures there are to choose from.
pub(crate) const PRESETS: u8 = 16;
/// The largest profile photo taken in. The app sends far less (about
/// 15 KB), so it moves quickly over Bluetooth.
pub(crate) const MAX_PHOTO_BYTES: usize = 48 * 1024;

/// Whether hex-encoded bytes are a small JPEG, PNG or WebP picture, judged
/// by how the file starts.
pub(crate) fn sound_photo(hex: &str) -> bool {
    let Ok(bytes) = hexcode::decode(hex) else {
        return false;
    };
    let kind = bytes.starts_with(&[0xff, 0xd8, 0xff])
        || bytes.starts_with(&[0x89, b'P', b'N', b'G'])
        || bytes.starts_with(b"GIF87a")
        || bytes.starts_with(b"GIF89a")
        || (bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP");
    kind && bytes.len() <= MAX_PHOTO_BYTES
}

/// The largest picture a sticker of the user's own may be. It travels
/// inside the message, so it is kept as small as a profile photo.
pub(crate) const MAX_STICKER_BYTES: usize = 32 * 1024;
/// The longest name of a sticker the app comes with.
const MAX_STICKER_NAME: usize = 32;

/// A sticker, sent on its own and shown large. Either one every copy of
/// the app comes with, by name, or the sender's own: a small picture or
/// GIF, hex, carried in the message as a profile photo is.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Sticker {
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub image: String,
}

impl Sticker {
    /// One of the two, and as it should be: a name of small letters,
    /// digits and dashes, or a picture no bigger than allowed. A name the
    /// app does not know is still a sticker; the app says it cannot show
    /// it.
    pub fn sound(&self) -> bool {
        match (self.name.is_empty(), self.image.is_empty()) {
            (false, true) => {
                self.name.len() <= MAX_STICKER_NAME
                    && self
                        .name
                        .bytes()
                        .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
            }
            (true, false) => self.image.len() <= MAX_STICKER_BYTES * 2 && sound_photo(&self.image),
            _ => false,
        }
    }
}

/// A contact's profile photo as this device keeps it.
#[derive(Default, Serialize, Deserialize)]
struct Avatar {
    preset: Option<u8>,
    photo: Option<String>,
    version: u64,
}
const MAX_BODY_CHARS: usize = 16_000;
const MAX_NOTE_CHARS: usize = 280;
const MAX_NAME_CHARS: usize = 64;
/// What a check code starts with, so it can be found in a pasted message.
const CHECK_PREFIX: &str = "dnet:check/";
/// Anything larger is not a chat envelope and is not even opened.
const MAX_ENVELOPE_BYTES: usize = 1 << 20;

/// What travels inside an envelope.
#[derive(Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
enum Payload {
    /// "May I chat with you?" Carries the asker's identity, because the
    /// person asked may never have seen it.
    Request {
        name: String,
        #[serde(default)]
        note: Option<String>,
        identity: String,
        /// The one-time token from the asked person's link, when the
        /// request came from one.
        #[serde(default)]
        invite: Option<String>,
        /// The asker's proof that work went into their identity. See
        /// `identity::check_stamp`. A stranger without one is not let in.
        #[serde(default)]
        stamp: Option<String>,
    },
    /// "Yes." There is no message for "no": a declined person is not told.
    Accept {
        name: String,
    },
    Text {
        id: String,
        body: String,
        sent_at: u64,
        /// The choices, if this is a poll. The body is its question.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        options: Vec<String>,
        /// How many seconds after it arrives this message is to be
        /// deleted. Nought means it stays.
        #[serde(default, skip_serializing_if = "is_zero")]
        gone_in: u64,
        /// A contact of the sender's, passed on. The body is their name.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        card: Option<Card>,
        /// Passed on from a channel or another chat. Where from, and who
        /// wrote it first, is not said.
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        forwarded: bool,
        /// Where the sender was, if they sent that. The body is the same
        /// place in words.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        location: Option<Place>,
        /// A sticker, if that is what this is. The body is then empty.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        sticker: Option<Sticker>,
    },
    /// "From now on, what we write here disappears after this long", or
    /// with nought, "stays". `set_at` is when the sender chose it, so
    /// that two changes crossing on the way end the same on both devices.
    Timer {
        seconds: u64,
        set_at: u64,
    },
    /// The sender's choice in a poll in this chat. Their latest counts.
    Vote {
        target: String,
        choice: u32,
    },
    VerifyCommit {
        commit: String,
    },
    VerifyNonce {
        nonce: String,
    },
    VerifyReveal {
        nonce: String,
    },
    /// "These reached my device." Says nothing about what was done with
    /// them, so a blocked or declined person learns nothing from it.
    Ack {
        ids: Vec<String>,
    },
    /// "I have read these." Sent only by someone who switched read
    /// receipts on.
    Read {
        ids: Vec<String>,
    },
    /// "Delete these messages of mine for everyone." Only ever applied to
    /// messages the sender wrote.
    Unsend {
        ids: Vec<String>,
    },
    /// Something about spaces, between two devices. This module only
    /// carries it; `space.rs` knows what it means.
    Space {
        wire: Value,
    },
    /// Something about a file being sent. `file.rs` knows what it means.
    File {
        wire: Value,
    },
    /// "This is what I am called now." Taken only from a contact.
    Name {
        name: String,
    },
    /// The sender's profile photo: one of the built-in pictures, or their
    /// own small photo, or neither. The highest `version` wins.
    Photo {
        #[serde(default)]
        preset: Option<u8>,
        #[serde(default)]
        photo: Option<String>,
        version: u64,
    },
    /// "I am writing to you." Sent only by someone who switched that on.
    Typing,
    /// "I have the app open", or with `active` false, "I have put it
    /// away". Sent only by someone who switched that on.
    Here {
        active: bool,
    },
    /// "I am away, and this is why", or with no note, "I am back". The
    /// user chose to say it. `set_at`, in milliseconds, is when, so the
    /// latest counts however they arrive.
    Away {
        #[serde(default)]
        note: Option<String>,
        set_at: u64,
    },
    /// "Can we use something faster than Bluetooth?" From a contact who is
    /// in range and has something big to send or fetch.
    FastAsk,
    /// "Join this." A Wi-Fi Direct group the sender has just made for the
    /// two of them, and its password. `joins` says whether the sender
    /// could join one instead; a PC cannot. The group is only a road: what
    /// travels on it is sealed exactly as it is over Bluetooth, so the
    /// password guards the road, not the messages.
    FastOffer {
        network: String,
        pass: String,
        joins: bool,
    },
    /// Something about a call between the two. This module only carries
    /// it; `call.rs` knows what it means. Never kept: a call is now or
    /// never.
    Call {
        wire: Value,
    },
}

/// Whether these could be a Wi-Fi Direct group made by the app and its
/// password. Anything else, such as the name of somebody's home Wi-Fi, is
/// neither offered nor taken, so an offer cannot be used to make a device
/// join a network of the sender's choosing.
fn sound_group(network: &str, pass: &str) -> bool {
    let plain = |text: &str| text.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-');
    let tag = network
        .strip_prefix("DIRECT-")
        .unwrap_or_default()
        .as_bytes();
    network.len() <= 32
        && tag.len() >= 2
        && tag[..2].iter().all(u8::is_ascii_alphanumeric)
        && plain(network)
        && (8..=63).contains(&pass.len())
        && pass.bytes().all(|b| b.is_ascii_alphanumeric())
}

/// An envelope whose contents start with this byte holds a piece of a
/// file: raw bytes, not JSON. JSON never starts with it.
const PIECE_MARK: u8 = 1;

/// What is sealed into an envelope: one payload and, for anything that
/// must not be lost, a number the receiving device answers with. Until
/// that answer comes back the sender keeps the envelope and sends it again
/// whenever the two meet.
#[derive(Serialize, Deserialize)]
struct Sealed {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ack: Option<String>,
    #[serde(flatten)]
    payload: Payload,
}

/// The most messages one answer may name.
const MAX_IDS: usize = 256;

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Relation {
    /// They asked. Waiting for the user's answer.
    Incoming,
    /// The user asked. Waiting for theirs.
    Outgoing,
    /// Accepted. The only relation in which messages flow.
    Contact,
    /// May not ask again.
    Blocked,
}

#[derive(Clone, Serialize, Deserialize)]
struct Person {
    /// Their public identity, hex encoded. Empty only for someone blocked
    /// before their identity was ever seen.
    identity: String,
    name: String,
    #[serde(default)]
    note: Option<String>,
    relation: Relation,
    #[serde(default)]
    verified: bool,
    /// A random id for their message thread. It is the part of a stored
    /// message's address that is not encrypted, so it must say nothing
    /// about who the thread is with.
    thread: String,
    /// Set on someone blocked who was a contact, so that unblocking them
    /// brings the chat back.
    #[serde(default)]
    was_contact: bool,
    /// The user read this person's identity off their own screen with the
    /// camera, before asking them. That is as good as comparing words, so
    /// they are verified the moment they accept.
    #[serde(default)]
    scanned: bool,
    /// How long messages in this chat live, in seconds. Nought: for good.
    #[serde(default)]
    timer: u64,
    /// When that was last chosen, by whichever of the two chose it.
    #[serde(default)]
    timer_set_at: u64,
    /// The user deleted this chat. It stays off the list until a new
    /// message comes; the person is still a contact.
    #[serde(default)]
    hidden: bool,
    /// Messages this person deleted for everyone before they arrived
    /// here. If one turns up later, it is dropped.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    gone_ids: Vec<String>,
}

#[derive(Serialize, Deserialize)]
struct StoredMessage {
    id: String,
    mine: bool,
    body: String,
    sent_at: u64,
    /// For the user's own messages: the other device has said it has it.
    #[serde(default)]
    delivered: bool,
    /// For the user's own messages: the other person has said they read
    /// it, which they do only if they switched that on.
    #[serde(default)]
    read: bool,
    /// For messages from the other person: the user has opened the chat
    /// since it arrived.
    #[serde(default)]
    seen: bool,
    /// Set when this message is a file. Its id is the transfer's.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    file: Option<FileRef>,
    /// The choices, if this is a poll. The body is its question.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    options: Vec<String>,
    /// What the user chose in the poll, and what the other person chose.
    #[serde(default)]
    my_vote: Option<u32>,
    #[serde(default)]
    their_vote: Option<u32>,
    /// When this message is to be deleted from this device, in seconds
    /// since 1970. None: it stays.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    gone_at: Option<u64>,
    /// Set when this message passes on a contact.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    card: Option<Card>,
    /// Deleted for everyone by its writer. Only its place in the chat is
    /// kept: "This message was deleted".
    #[serde(default)]
    deleted: bool,
    /// Passed on from a channel or another chat.
    #[serde(default)]
    forwarded: bool,
    /// Set when this message is where someone was.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    location: Option<Place>,
    /// Set when this message is a sticker.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    sticker: Option<Sticker>,
}

/// How long after sending a message its writer can delete it for
/// everyone: two days, as in WhatsApp.
const UNSEND_WINDOW: u64 = 2 * 24 * 60 * 60;
/// How many "delete for everyone" ids are remembered for messages that
/// have not arrived yet.
const MAX_GONE_IDS: usize = 256;

/// Someone passed on by a person who knows them: what they are called and
/// their public identity, which is all that is needed to ask them for a
/// chat. Having a card lets nobody message them. They still have to say
/// yes to the request, like anyone.
#[derive(Clone, Serialize, Deserialize)]
struct Card {
    name: String,
    identity: String,
    /// Their signing key, which is what the app knows a person by. Never
    /// taken from the sender: worked out from the identity on arrival.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    key: String,
}

impl Card {
    /// The card with its key filled in, if it holds together: a name that
    /// could be a name, and an identity that is one.
    fn checked(self) -> Option<Card> {
        let name = self.name.trim().to_string();
        if name.is_empty() || too_long(&name, MAX_NAME_CHARS) {
            return None;
        }
        let identity = hexcode::decode(&self.identity)
            .and_then(|bytes| PublicIdentity::from_bytes(&bytes))
            .ok()
            .filter(|identity| identity.verify().is_ok())?;
        Some(Card {
            name,
            key: hexcode::encode(&identity.signing_key),
            identity: self.identity,
        })
    }
}

fn is_zero(n: &u64) -> bool {
    *n == 0
}

/// The times a chat can be set to forget its messages after: an hour, a
/// day, a week. Nought switches it off.
const TIMERS: [u64; 4] = [0, 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60];

/// A poll offers two to six choices, each with something in it.
fn sound_choices(options: &[String]) -> bool {
    options.is_empty()
        || ((2..=6).contains(&options.len())
            && options
                .iter()
                .all(|c| !c.trim().is_empty() && !too_long(c, 80)))
}

#[derive(Serialize, Deserialize)]
struct FileRef {
    id: String,
    name: String,
    size: u64,
}

/// A word comparison in progress. Kept in memory only: it is worthless
/// after the moment it is for.
pub(crate) enum Verifying {
    Started { nonce: sas::Nonce },
    Answered { commit: [u8; 32], nonce: sas::Nonce },
    Ready { words: sas::Words },
}

pub(crate) type Sessions = HashMap<String, Verifying>;

/// People, keyed by their signing key in hex.
type People = BTreeMap<String, Person>;

pub(crate) struct Chat<'a> {
    pub vault: &'a Vault,
    pub me: IdentitySecret,
    pub my_name: String,
    pub sessions: &'a mut Sessions,
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn ignored() -> Value {
    json!({ "event": { "kind": "ignored" }, "replies": [] })
}

fn event(kind: &str, from: &str, replies: Vec<Value>) -> Value {
    json!({ "event": { "kind": kind, "from": from }, "replies": replies })
}

fn new_thread_id() -> Result<String> {
    Ok(hexcode::encode(random_bytes::<16>()?.as_slice()))
}

fn too_long(text: &str, limit: usize) -> bool {
    text.chars().count() > limit
}

impl Chat<'_> {
    fn people(&self) -> Result<People> {
        match self.vault.get(PEOPLE.0, PEOPLE.1)? {
            None => Ok(People::new()),
            Some(bytes) => serde_json::from_slice(&bytes)
                .map_err(|_| CoreError::Corrupt("the saved contacts are unreadable".into())),
        }
    }

    fn save(&self, people: &People) -> Result<()> {
        let bytes = serde_json::to_vec(people).expect("contacts are plain data");
        self.vault.put(PEOPLE.0, PEOPLE.1, &bytes)
    }

    fn identity_of(person: &Person) -> Result<PublicIdentity> {
        PublicIdentity::from_bytes(&hexcode::decode(&person.identity)?)
    }

    fn seal_for(
        &self,
        key: &str,
        identity: &PublicIdentity,
        payload: Payload,
        ack: Option<String>,
    ) -> Result<Value> {
        let sealed = Sealed {
            ack: ack.clone(),
            payload,
        };
        let bytes = serde_json::to_vec(&sealed).expect("payloads are plain data");
        let envelope = envelope::seal(&self.me, identity, &bytes)?;
        let mut out = json!({ "to": key, "envelope": hexcode::encode(&envelope) });
        if let Some(ack) = ack {
            out["ack"] = json!(ack);
        }
        Ok(out)
    }

    /// Seals something about spaces for one device. With `kept`, it is
    /// held and sent again until that device answers.
    pub fn seal_space_wire(
        &self,
        key: &str,
        identity: &PublicIdentity,
        wire: Value,
        kept: bool,
    ) -> Result<Value> {
        let ack = if kept { Some(Self::new_ack()?) } else { None };
        self.seal_for(key, identity, Payload::Space { wire }, ack)
    }

    /// The identity of someone who has accepted, or been accepted by, the
    /// user.
    pub fn contact_identity(&self, key: &str) -> Result<PublicIdentity> {
        Self::identity_of(&Self::contact(&self.people()?, key)?)
    }

    /// Seals something about a file transfer. With `ack`, it is held and
    /// sent again until the other device answers with that number.
    pub fn seal_file_wire(
        &self,
        key: &str,
        identity: &PublicIdentity,
        wire: Value,
        ack: Option<String>,
    ) -> Result<Value> {
        self.seal_for(key, identity, Payload::File { wire }, ack)
    }

    /// Seals one piece of a file. It is sealed and signed exactly as a
    /// message is; only what is inside differs.
    pub fn seal_piece(&self, key: &str, identity: &PublicIdentity, piece: &[u8]) -> Result<Value> {
        let mut bytes = Vec::with_capacity(1 + piece.len());
        bytes.push(PIECE_MARK);
        bytes.extend_from_slice(piece);
        let envelope = envelope::seal(&self.me, identity, &bytes)?;
        Ok(json!({ "to": key, "envelope": hexcode::encode(&envelope) }))
    }

    /// Puts a file into the thread with a contact, as a message would be.
    /// An offer that arrives twice is one entry.
    pub fn file_message(
        &mut self,
        with: &str,
        mine: bool,
        id: &str,
        name: &str,
        size: u64,
    ) -> Result<()> {
        let person = Self::contact(&self.people()?, with)?;
        if self.messages(&person)?.iter().any(|m| m.id == id) {
            return Ok(());
        }
        let message = StoredMessage {
            id: id.to_string(),
            mine,
            body: String::new(),
            sent_at: now(),
            delivered: false,
            read: false,
            seen: mine,
            file: Some(FileRef {
                id: id.to_string(),
                name: name.to_string(),
                size,
            }),
            options: Vec::new(),
            my_vote: None,
            their_vote: None,
            // A file is the user's once it is saved. The timer is for
            // what is written, and leaves files alone.
            gone_at: None,
            card: None,
            deleted: false,
            forwarded: false,
            location: None,
            sticker: None,
        };
        self.append(&person, &message)
    }

    /// Seals `payload` for one person, ready for a transport to carry. It
    /// is sent once, to whoever is there. Used for things that are only
    /// worth anything now.
    fn seal_to(&self, key: &str, person: &Person, payload: Payload) -> Result<Value> {
        self.seal_for(key, &Self::identity_of(person)?, payload, None)
    }

    /// Seals something about a call for a contact. Sent once, to whoever
    /// is there.
    pub fn seal_call_wire(&self, to: &str, wire: Value) -> Result<Value> {
        let person = Self::contact(&self.people()?, to)?;
        self.seal_to(to, &person, Payload::Call { wire })
    }

    /// The same, for something that must arrive. The envelope carries
    /// `ack`, and is kept and sent again until the other device answers
    /// with it.
    fn seal_kept(
        &self,
        key: &str,
        person: &Person,
        payload: Payload,
        ack: String,
    ) -> Result<Value> {
        self.seal_for(key, &Self::identity_of(person)?, payload, Some(ack))
    }

    fn new_ack() -> Result<String> {
        Ok(hexcode::encode(random_bytes::<16>()?.as_slice()))
    }

    /// The user's public identity: what someone needs in order to ask them
    /// for a chat. Safe to show to anyone.
    pub fn card(&self) -> Value {
        json!({ "identity": hexcode::encode(&self.me.public().to_bytes()) })
    }

    /// The user scanned the code of someone who is already a contact. If
    /// it is the very identity this device holds for them, they are
    /// verified. Returns whether they were.
    pub fn verify_scanned(&mut self, identity: &str) -> Result<Value> {
        let scanned = PublicIdentity::from_bytes(&hexcode::decode(identity)?)?;
        scanned.verify()?;
        let key = hexcode::encode(&scanned.signing_key);
        let mut people = self.people()?;
        let held = people.get_mut(&key).filter(|p| {
            p.relation == Relation::Contact && p.identity == hexcode::encode(&scanned.to_bytes())
        });
        let Some(person) = held else {
            return Ok(json!({ "verified": false }));
        };
        person.verified = true;
        self.save(&people)?;
        Ok(json!({ "verified": true, "key": key }))
    }

    /// The same, from the short code on the other person's screen: their
    /// key alone. A contact whose identity has this key is the person
    /// whose screen it is, since a key cannot be shown by anyone else.
    pub fn verify_key(&mut self, key: &str) -> Result<Value> {
        if hexcode::decode_exact::<32>(key).is_err() {
            return Ok(json!({ "verified": false }));
        }
        let mut people = self.people()?;
        let Some(person) = people
            .get_mut(key)
            .filter(|p| p.relation == Relation::Contact)
        else {
            return Ok(json!({ "verified": false }));
        };
        person.verified = true;
        self.save(&people)?;
        Ok(json!({ "verified": true, "key": key }))
    }

    /// `scanned` says the identity was read off the other person's screen
    /// with the camera.
    /// A new link for asking the user to chat: signed, good once, for a
    /// day. Every call makes a different one.
    pub fn invite_link(&mut self) -> Result<Value> {
        let token = random_bytes::<16>()?;
        let expires = now() + INVITE_LASTS;
        let mut body = vec![1u8];
        body.extend_from_slice(token.as_slice());
        body.extend_from_slice(&expires.to_be_bytes());
        body.extend_from_slice(&self.me.public().to_bytes());
        let signature = self.me.sign(&[INVITE_CONTEXT, &body].concat());
        body.extend_from_slice(&signature);
        self.vault
            .put(INVITES, token.as_slice(), &expires.to_be_bytes())?;
        Ok(json!({
            "link": format!("{INVITE_PREFIX}{}", hexcode::encode(&body)),
            "expires_in": INVITE_LASTS,
        }))
    }

    /// Who made a pasted link, and whether it has run out, without asking.
    pub fn check_invite(&self, link: &str) -> Result<Value> {
        let read = read_person_link(link)?;
        Ok(json!({
            "key": hexcode::encode(&read.identity.signing_key),
            "identity": hexcode::encode(&read.identity.to_bytes()),
            "expired": now() >= read.expires,
        }))
    }

    /// Asks the maker of a link to chat, carrying the link's token. A link
    /// that has run out is not used.
    /// `scanned` says the link was read off the other person's own device,
    /// as when two phones are tapped together.
    pub fn request_by_invite(&mut self, link: &str, note: Option<String>, scanned: bool) -> Result<Value> {
        let read = read_person_link(link)?;
        if now() >= read.expires {
            return Err(CoreError::Invalid("this link has run out".into()));
        }
        let identity = hexcode::encode(&read.identity.to_bytes());
        self.ask(
            &identity,
            note,
            scanned,
            None,
            Some(hexcode::encode(&read.token)),
        )
    }

    pub fn request_chat(
        &mut self,
        identity: &str,
        note: Option<String>,
        scanned: bool,
        known_as: Option<String>,
    ) -> Result<Value> {
        self.ask(identity, note, scanned, known_as, None)
    }

    fn ask(
        &mut self,
        identity: &str,
        note: Option<String>,
        scanned: bool,
        known_as: Option<String>,
        invite: Option<String>,
    ) -> Result<Value> {
        let identity = PublicIdentity::from_bytes(&hexcode::decode(identity)?)?;
        identity.verify()?;
        let key = hexcode::encode(&identity.signing_key);
        if identity.signing_key == self.me.signing_public() {
            return Err(CoreError::Invalid("you cannot ask yourself".into()));
        }
        let note = note.map(|n| n.trim().to_string()).filter(|n| !n.is_empty());
        if note.as_deref().is_some_and(|n| too_long(n, MAX_NOTE_CHARS)) {
            return Err(CoreError::Invalid("the note is too long".into()));
        }

        let mut people = self.people()?;
        match people.get(&key).map(|p| p.relation) {
            Some(Relation::Contact) => return Err(CoreError::Invalid("already a contact".into())),
            Some(Relation::Blocked) => {
                return Err(CoreError::Invalid("this person is blocked".into()))
            }
            // They already asked the user, so asking them is a yes.
            Some(Relation::Incoming) => return self.accept(&key),
            Some(Relation::Outgoing) | None => {}
        }
        // What the user was told this person is called, by whoever passed
        // them on. Shown while the request waits. Once they accept, the
        // name they give themselves takes its place.
        let known_as = known_as
            .map(|name| name.trim().to_string())
            .filter(|name| !too_long(name, MAX_NAME_CHARS))
            .unwrap_or_default();
        let person = Person {
            identity: hexcode::encode(&identity.to_bytes()),
            name: known_as,
            note: None,
            relation: Relation::Outgoing,
            verified: false,
            thread: new_thread_id()?,
            was_contact: false,
            scanned,
            timer: 0,
            timer_set_at: 0,
            hidden: false,
            gone_ids: Vec::new(),
        };
        let envelope = self.seal_kept(
            &key,
            &person,
            Payload::Request {
                name: self.my_name.clone(),
                note,
                identity: hexcode::encode(&self.me.public().to_bytes()),
                invite,
                stamp: crate::proof::my_stamp(self.vault, &self.me.signing_public())?,
            },
            Self::new_ack()?,
        )?;
        people.insert(key, person);
        self.save(&people)?;
        Ok(envelope)
    }

    pub fn cancel_request(&mut self, to: &str) -> Result<Value> {
        let mut people = self.people()?;
        if people
            .get(to)
            .is_some_and(|p| p.relation == Relation::Outgoing)
        {
            people.remove(to);
            self.save(&people)?;
        }
        Ok(Value::Null)
    }

    pub fn requests(&self) -> Result<Value> {
        let people = self.people()?;
        let list = |relation: Relation| -> Result<Vec<Value>> {
            people
                .iter()
                .filter(|(_, p)| p.relation == relation)
                .map(|(key, p)| {
                    Ok(json!({
                        "key": key,
                        "name": p.name,
                        "note": p.note,
                        "spoken_code": Self::identity_of(p)?.spoken_code(),
                    }))
                })
                .collect()
        };
        // Someone can be blocked before their identity was ever seen, so
        // the blocked are listed by key alone.
        let blocked: Vec<&String> = people
            .iter()
            .filter(|(_, p)| p.relation == Relation::Blocked)
            .map(|(key, _)| key)
            .collect();
        Ok(json!({
            "incoming": list(Relation::Incoming)?,
            "outgoing": list(Relation::Outgoing)?,
            "blocked": blocked,
        }))
    }

    pub fn accept(&mut self, from: &str) -> Result<Value> {
        let mut people = self.people()?;
        let person = people
            .get_mut(from)
            .filter(|p| p.relation == Relation::Incoming)
            .ok_or_else(|| CoreError::Invalid("there is no request from this person".into()))?;
        person.relation = Relation::Contact;
        person.note = None;
        let person = person.clone();
        let envelope = self.seal_kept(
            from,
            &person,
            Payload::Accept {
                name: self.my_name.clone(),
            },
            Self::new_ack()?,
        )?;
        self.save(&people)?;
        Ok(envelope)
    }

    /// Removes the request. Nothing is sent: the person is not told. A new
    /// request from them is quietly dropped for a while, longer each time.
    pub fn decline(&mut self, from: &str) -> Result<Value> {
        let mut people = self.people()?;
        if people
            .get(from)
            .is_some_and(|p| p.relation == Relation::Incoming)
        {
            people.remove(from);
            self.save(&people)?;
            let mut record = self.declined(from)?;
            record.times = record.times.saturating_add(1);
            record.until = now() + decline_wait(record.times);
            self.vault.put(
                DECLINED,
                &hexcode::decode(from)?,
                &serde_json::to_vec(&record).expect("a record is plain data"),
            )?;
        }
        Ok(Value::Null)
    }

    /// Spends a link token the user made: true if it was theirs, unused
    /// and still running.
    fn use_invite(&mut self, token: Option<&str>) -> Result<bool> {
        let Some(token) = token.and_then(|t| hexcode::decode(t).ok()) else {
            return Ok(false);
        };
        let Some(end) = self.vault.get(INVITES, &token)? else {
            return Ok(false);
        };
        self.vault.delete(INVITES, &token)?;
        let end: [u8; 8] = end.as_slice().try_into().unwrap_or_default();
        Ok(now() < u64::from_be_bytes(end))
    }

    fn declined(&self, key: &str) -> Result<Declined> {
        Ok(match self.vault.get(DECLINED, &hexcode::decode(key)?)? {
            Some(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
            None => Declined::default(),
        })
    }

    /// Ends any chat with this person and stops them asking again. Nothing
    /// is sent: the person is not told.
    pub fn block(&mut self, who: &str) -> Result<Value> {
        hexcode::decode_exact::<32>(who)?;
        let mut people = self.people()?;
        match people.get_mut(who) {
            Some(person) => {
                person.was_contact = person.relation == Relation::Contact;
                person.relation = Relation::Blocked;
                person.verified = false;
                person.note = None;
            }
            None => {
                people.insert(
                    who.to_string(),
                    Person {
                        identity: String::new(),
                        name: String::new(),
                        note: None,
                        relation: Relation::Blocked,
                        verified: false,
                        thread: new_thread_id()?,
                        was_contact: false,
                        scanned: false,
                        timer: 0,
                        timer_set_at: 0,
                        hidden: false,
                        gone_ids: Vec::new(),
                    },
                );
            }
        }
        self.sessions.remove(who);
        self.save(&people)?;
        Ok(Value::Null)
    }

    pub fn contacts(&self) -> Result<Value> {
        let people = self.people()?;
        let aways = self.aways()?;
        let mut contacts = Vec::new();
        for (key, person) in people
            .iter()
            .filter(|(_, p)| p.relation == Relation::Contact)
        {
            let identity = Self::identity_of(person)?;
            contacts.push(json!({
                "key": key,
                "name": person.name,
                "verified": person.verified,
                "timer": person.timer,
                "hidden": person.hidden,
                // Why they said they are away, if they are.
                "away": aways.get(key).and_then(|(note, _)| note.clone()),
                "photo_version": self.avatar(key)?.version,
                "fingerprint": identity.fingerprint(),
                "spoken_code": identity.spoken_code(),
            }));
        }
        Ok(Value::Array(contacts))
    }

    fn contact(people: &People, key: &str) -> Result<Person> {
        people
            .get(key)
            .filter(|p| p.relation == Relation::Contact)
            .cloned()
            .ok_or(CoreError::NotAContact)
    }

    fn thread_prefix(person: &Person) -> Result<Vec<u8>> {
        hexcode::decode(&person.thread)
    }

    /// Every message in a thread, each with the key it is stored under.
    fn stored(&self, person: &Person) -> Result<Vec<(Vec<u8>, StoredMessage)>> {
        self.vault
            .list_prefix(THREAD, &Self::thread_prefix(person)?)?
            .into_iter()
            .map(|(key, bytes)| {
                let message = serde_json::from_slice(&bytes)
                    .map_err(|_| CoreError::Corrupt("a saved message is unreadable".into()))?;
                Ok((key, message))
            })
            .collect()
    }

    fn messages(&self, person: &Person) -> Result<Vec<StoredMessage>> {
        Ok(self
            .stored(person)?
            .into_iter()
            .map(|(_, message)| message)
            .collect())
    }

    /// Changes the messages in a thread that `change` says to, and returns
    /// the ids of those it changed.
    fn update(
        &self,
        person: &Person,
        mut change: impl FnMut(&mut StoredMessage) -> bool,
    ) -> Result<Vec<String>> {
        let mut changed = Vec::new();
        for (key, mut message) in self.stored(person)? {
            if change(&mut message) {
                let bytes = serde_json::to_vec(&message).expect("messages are plain data");
                self.vault.put(THREAD, &key, &bytes)?;
                changed.push(message.id);
            }
        }
        Ok(changed)
    }

    fn append(&self, person: &Person, message: &StoredMessage) -> Result<()> {
        // Numbered in arrival order, so the thread lists in that order. One
        // more than the last number in use, not a count: old messages can
        // be deleted, and a count would then hand out a number twice.
        let mut id = Self::thread_prefix(person)?;
        let next = self
            .vault
            .list_prefix(THREAD, &id)?
            .last()
            .and_then(|(key, _)| key.get(16..24)?.try_into().ok())
            .map_or(0, |last: [u8; 8]| u64::from_be_bytes(last) + 1);
        id.extend_from_slice(&next.to_be_bytes());
        let bytes = serde_json::to_vec(message).expect("messages are plain data");
        self.vault.put(THREAD, &id, &bytes)
    }

    /// Chooses in a poll in the chat with `with`. Returns the envelope
    /// that tells them, kept until their device has it.
    pub fn vote(&mut self, with: &str, id: &str, choice: u32) -> Result<Value> {
        let person = Self::contact(&self.people()?, with)?;
        let voted = self.update(&person, |message| {
            let poll = message.id == id && (choice as usize) < message.options.len();
            if poll {
                message.my_vote = Some(choice);
            }
            poll
        })?;
        if voted.is_empty() {
            return Err(CoreError::Invalid(
                "that is not a choice in a poll here".into(),
            ));
        }
        self.seal_kept(
            with,
            &person,
            Payload::Vote {
                target: id.to_string(),
                choice,
            },
            Self::new_ack()?,
        )
    }

    /// With `options` it is a poll, and `body` is its question.
    pub fn send_text(&mut self, to: &str, body: &str, options: Vec<String>) -> Result<Value> {
        self.send(to, body, options, None, false, None, None)
    }

    /// Passes on words the user read in a channel or another chat. They
    /// go as a new message of the user's, marked as passed on, and say
    /// nothing of where they came from or who wrote them first.
    pub fn forward(&mut self, to: &str, body: &str) -> Result<Value> {
        self.send(to, body, Vec::new(), None, true, None, None)
    }

    /// Passes one contact on to another, as a card the receiver can ask
    /// them for a chat by.
    pub fn send_card(&mut self, to: &str, contact: &str) -> Result<Value> {
        let passed = Self::contact(&self.people()?, contact)?;
        if to == contact {
            return Err(CoreError::Invalid("nobody needs their own card".into()));
        }
        let card = Card {
            name: passed.name.clone(),
            identity: passed.identity,
            key: contact.to_string(),
        };
        self.send(to, &passed.name, Vec::new(), Some(card), false, None, None)
    }

    /// Sends where the user is, as their device found it. The message's
    /// words are the place written out, for anything that cannot show it.
    pub fn send_location(&mut self, to: &str, place: Place) -> Result<Value> {
        let place = place
            .checked()
            .ok_or_else(|| CoreError::Invalid("that is not a place on Earth".into()))?;
        self.send(
            to,
            &place.text(),
            Vec::new(),
            None,
            false,
            Some(place),
            None,
        )
    }

    /// Sends a sticker. It has no words of its own.
    pub fn send_sticker(&mut self, to: &str, sticker: Sticker) -> Result<Value> {
        if !sticker.sound() {
            return Err(CoreError::Invalid("that is not a sticker".into()));
        }
        self.send(to, "", Vec::new(), None, false, None, Some(sticker))
    }

    #[allow(clippy::too_many_arguments)]
    fn send(
        &mut self,
        to: &str,
        body: &str,
        options: Vec<String>,
        card: Option<Card>,
        forwarded: bool,
        location: Option<Place>,
        sticker: Option<Sticker>,
    ) -> Result<Value> {
        let people = self.people()?;
        // Checked here for a clear error. The check that matters is the
        // one the recipient makes in `receive`.
        let person = Self::contact(&people, to)?;
        let body = body.trim();
        if (body.is_empty() && sticker.is_none()) || too_long(body, MAX_BODY_CHARS) {
            return Err(CoreError::Invalid(
                "a message must be between 1 and 16000 characters".into(),
            ));
        }
        let options: Vec<String> = options
            .iter()
            .map(|choice| choice.trim().to_string())
            .collect();
        if !sound_choices(&options) {
            return Err(CoreError::Invalid(
                "a poll needs between two and six choices".into(),
            ));
        }
        let message = StoredMessage {
            id: hexcode::encode(random_bytes::<16>()?.as_slice()),
            mine: true,
            body: body.to_string(),
            sent_at: now(),
            delivered: false,
            read: false,
            seen: true,
            file: None,
            options,
            my_vote: None,
            their_vote: None,
            gone_at: None,
            card,
            deleted: false,
            forwarded,
            location,
            sticker,
        };
        let message = StoredMessage {
            gone_at: (person.timer > 0).then(|| message.sent_at + person.timer),
            ..message
        };
        // The message's own id is what the other device answers with.
        let mut envelope = self.seal_kept(
            to,
            &person,
            Payload::Text {
                id: message.id.clone(),
                body: message.body.clone(),
                sent_at: message.sent_at,
                options: message.options.clone(),
                gone_in: person.timer,
                // The key is not sent. The receiver works it out.
                card: message.card.clone().map(|card| Card {
                    key: String::new(),
                    ..card
                }),
                forwarded,
                location,
                sticker: message.sticker.clone(),
            },
            message.id.clone(),
        )?;
        self.append(&person, &message)?;
        self.unhide(to)?;
        envelope["id"] = json!(message.id);
        Ok(envelope)
    }

    /// Puts a deleted chat back on the list.
    fn unhide(&self, with: &str) -> Result<()> {
        let mut people = self.people()?;
        if let Some(person) = people.get_mut(with).filter(|p| p.hidden) {
            person.hidden = false;
            self.save(&people)?;
        }
        Ok(())
    }

    /// Deletes messages from this device only. The other person's copy is
    /// theirs.
    pub fn delete_mine(&self, with: &str, ids: &[String]) -> Result<Value> {
        let person = Self::contact(&self.people()?, with)?;
        for (key, message) in self.stored(&person)? {
            if ids.contains(&message.id) {
                self.vault.delete(THREAD, &key)?;
            }
        }
        Ok(Value::Null)
    }

    /// Deletes the user's own messages for everyone: on this device they
    /// become "This message was deleted", and the returned envelope, kept
    /// until the other device has it, does the same there. Only messages
    /// the user wrote in the last two days; others in `ids` are left. An
    /// error if none is.
    pub fn unsend(&mut self, with: &str, ids: &[String]) -> Result<Value> {
        let person = Self::contact(&self.people()?, with)?;
        let since = now().saturating_sub(UNSEND_WINDOW);
        let gone = self.update(&person, |message| {
            let may = message.mine
                && !message.deleted
                && message.sent_at >= since
                && ids.contains(&message.id);
            if may {
                Self::tombstone(message);
            }
            may
        })?;
        if gone.is_empty() {
            return Err(CoreError::Invalid(
                "only your own messages of the last two days can be deleted for everyone".into(),
            ));
        }
        self.seal_kept(
            with,
            &person,
            Payload::Unsend { ids: gone },
            Self::new_ack()?,
        )
    }

    /// Leaves only the place of a deleted message.
    fn tombstone(message: &mut StoredMessage) {
        message.deleted = true;
        message.body = String::new();
        message.options.clear();
        message.my_vote = None;
        message.their_vote = None;
        message.card = None;
        message.file = None;
        message.location = None;
        message.sticker = None;
    }

    /// Deletes every message in a chat from this device. The person stays
    /// a contact.
    pub fn clear(&self, with: &str) -> Result<Value> {
        let person = Self::contact(&self.people()?, with)?;
        for (key, _) in self.stored(&person)? {
            self.vault.delete(THREAD, &key)?;
        }
        Ok(Value::Null)
    }

    /// Clears a chat and takes it off the list until a new message comes.
    pub fn delete_chat(&self, with: &str) -> Result<Value> {
        self.clear(with)?;
        let mut people = self.people()?;
        if let Some(person) = people.get_mut(with) {
            person.hidden = true;
        }
        self.save(&people)?;
        Ok(Value::Null)
    }

    /// Deletes every direct message written before `before` (seconds
    /// since 1970) from this device. Returns how many went. Contacts stay,
    /// and nobody else's copy is touched.
    pub fn purge(&self, before: u64) -> Result<u64> {
        let mut removed = 0;
        for person in self.people()?.values() {
            for (key, message) in self.stored(person)? {
                if message.sent_at < before {
                    self.vault.delete(THREAD, &key)?;
                    removed += 1;
                }
            }
        }
        Ok(removed)
    }

    /// Sets how long messages in a chat live from now on, on this device,
    /// and returns an envelope telling the other person, to be kept until
    /// their device has it. What is already in the chat is not touched.
    pub fn set_timer(&mut self, with: &str, seconds: u64) -> Result<Value> {
        let mut people = self.people()?;
        Self::contact(&people, with)?;
        if !TIMERS.contains(&seconds) {
            return Err(CoreError::Invalid(
                "that is not a time the app offers".into(),
            ));
        }
        let person = people.get_mut(with).expect("it was just found");
        person.timer = seconds;
        // Later than any choice either of them made before.
        person.timer_set_at = now().max(person.timer_set_at.saturating_add(1));
        let person = person.clone();
        self.save(&people)?;
        self.seal_kept(
            with,
            &person,
            Payload::Timer {
                seconds,
                set_at: person.timer_set_at,
            },
            Self::new_ack()?,
        )
    }

    /// Deletes from this device every message whose time is up at `now`
    /// (seconds since 1970). Returns how many went.
    pub fn expire(&self, now: u64) -> Result<u64> {
        let mut removed = 0;
        for person in self.people()?.values() {
            for (key, message) in self.stored(person)? {
                if message.gone_at.is_some_and(|at| at <= now) {
                    self.vault.delete(THREAD, &key)?;
                    removed += 1;
                }
            }
        }
        Ok(removed)
    }

    pub fn thread(&self, with: &str) -> Result<Value> {
        let person = Self::contact(&self.people()?, with)?;
        Ok(serde_json::to_value(self.messages(&person)?).expect("messages are plain data"))
    }

    /// The user has opened the chat. Everything in it counts as seen from
    /// now on. Returns an envelope telling the other person so, but only
    /// if `report` is set, which is the user's "send read receipts" switch,
    /// and only if there was something new.
    pub fn mark_read(&mut self, with: &str, report: bool) -> Result<Value> {
        let person = Self::contact(&self.people()?, with)?;
        let ids = self.update(&person, |message| {
            let new = !message.mine && !message.seen;
            message.seen = true;
            new
        })?;
        if !report || ids.is_empty() {
            return Ok(Value::Null);
        }
        self.seal_kept(with, &person, Payload::Read { ids }, Self::new_ack()?)
    }

    fn avatar(&self, key: &str) -> Result<Avatar> {
        Ok(match self.vault.get(AVATAR, &hexcode::decode(key)?)? {
            Some(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
            None => Avatar::default(),
        })
    }

    /// A contact's profile photo, as far as they have shared it.
    pub fn photo_of(&self, who: &str) -> Result<Value> {
        Self::contact(&self.people()?, who)?;
        Ok(serde_json::to_value(self.avatar(who)?).expect("an avatar is plain data"))
    }

    /// Envelopes telling contacts the user's profile photo: every contact,
    /// or just `only`. Each is to be kept until that contact's device has
    /// it.
    pub fn photo_envelopes(
        &self,
        only: Option<&str>,
        preset: Option<u8>,
        photo: Option<String>,
        version: u64,
    ) -> Result<Vec<Value>> {
        self.people()?
            .iter()
            .filter(|(key, person)| {
                person.relation == Relation::Contact && only.is_none_or(|only| only == *key)
            })
            .map(|(key, person)| {
                self.seal_kept(
                    key,
                    person,
                    Payload::Photo {
                        preset,
                        photo: photo.clone(),
                        version,
                    },
                    Self::new_ack()?,
                )
            })
            .collect()
    }

    /// Tells every contact the user's name, after it has changed. Each
    /// envelope is to be kept until that contact's device has it.
    pub fn name_envelopes(&self) -> Result<Vec<Value>> {
        self.people()?
            .iter()
            .filter(|(_, person)| person.relation == Relation::Contact)
            .map(|(key, person)| {
                self.seal_kept(
                    key,
                    person,
                    Payload::Name {
                        name: self.my_name.clone(),
                    },
                    Self::new_ack()?,
                )
            })
            .collect()
    }

    /// Tells a contact the user is writing to them. Sent once, to whoever
    /// is there. The caller has checked the user's switch.
    pub fn typing(&self, to: &str) -> Result<Value> {
        let person = Self::contact(&self.people()?, to)?;
        self.seal_to(to, &person, Payload::Typing)
    }

    /// Tells a contact whether the user has the app open. The caller has
    /// checked the user's switch.
    pub fn here(&self, to: &str, active: bool) -> Result<Value> {
        let person = Self::contact(&self.people()?, to)?;
        self.seal_to(to, &person, Payload::Here { active })
    }

    /// Tells every contact the user is away, with why, or with None that
    /// they are back. Each envelope is to be kept until that contact's
    /// device has it.
    pub fn away_envelopes(&self, note: Option<&str>) -> Result<Vec<Value>> {
        let set_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        self.people()?
            .iter()
            .filter(|(_, person)| person.relation == Relation::Contact)
            .map(|(key, person)| {
                self.seal_kept(
                    key,
                    person,
                    Payload::Away {
                        note: note.map(str::to_string),
                        set_at,
                    },
                    Self::new_ack()?,
                )
            })
            .collect()
    }

    /// What each contact last said about being away, and when.
    fn aways(&self) -> Result<BTreeMap<String, (Option<String>, u64)>> {
        match self.vault.get(AWAY.0, AWAY.1)? {
            None => Ok(BTreeMap::new()),
            Some(bytes) => serde_json::from_slice(&bytes)
                .map_err(|_| CoreError::Corrupt("what contacts said is unreadable".into())),
        }
    }

    /// Asks a contact whether a faster link can be set up. Sent once, to
    /// whoever is there: it is no use to them later.
    pub fn fast_ask(&self, to: &str) -> Result<Value> {
        let person = Self::contact(&self.people()?, to)?;
        self.seal_to(to, &person, Payload::FastAsk)
    }

    /// Tells a contact the Wi-Fi Direct group this device has made for
    /// the two of them.
    pub fn fast_offer(&self, to: &str, network: &str, pass: &str, joins: bool) -> Result<Value> {
        let person = Self::contact(&self.people()?, to)?;
        if !sound_group(network, pass) {
            return Err(CoreError::Invalid(
                "that is not a group made for this".into(),
            ));
        }
        self.seal_to(
            to,
            &person,
            Payload::FastOffer {
                network: network.into(),
                pass: pass.into(),
                joins,
            },
        )
    }

    /// Takes in an envelope from any transport and says what it was.
    ///
    /// Anything that is not for the user, not well formed, or not allowed
    /// by the request rule comes back as "ignored". The sender gets no
    /// signal either way.
    pub fn receive(&mut self, envelope: &str) -> Result<Value> {
        let envelope = hexcode::decode(envelope)?;
        if envelope.len() > MAX_ENVELOPE_BYTES {
            return Ok(ignored());
        }
        let Ok(opened) = envelope::open(&self.me, &envelope) else {
            return Ok(ignored());
        };
        // The envelope's signature was checked, so this is who sent it.
        let from = hexcode::encode(&opened.sender_signing_key);
        if let Some((&PIECE_MARK, piece)) = opened.payload.split_first() {
            // A piece of a file. Handed up as it is; whether it belongs to
            // anything is for `file.rs` to say.
            let mut result = event("file_piece", &from, vec![]);
            result["event"]["piece"] = json!(hexcode::encode(piece));
            return Ok(result);
        }
        let Ok(sealed) = serde_json::from_slice::<Sealed>(&opened.payload) else {
            return Ok(ignored());
        };
        // Someone asking for the first time has to bring their identity
        // with them. It is what the answer below is sealed to.
        let brought = match &sealed.payload {
            Payload::Request { identity, .. } => hexcode::decode(identity)
                .and_then(|bytes| PublicIdentity::from_bytes(&bytes))
                .ok()
                .filter(|identity| {
                    identity.signing_key == opened.sender_signing_key && identity.verify().is_ok()
                }),
            _ => None,
        };
        let mut result = self.take(&from, &opened, sealed.payload)?;

        // Say it arrived. This is the same whatever was done with it, so
        // it tells a declined or blocked person nothing.
        if let Some(ack) = sealed
            .ack
            .filter(|ack| hexcode::decode_exact::<16>(ack).is_ok())
        {
            let known = self
                .people()?
                .get(&from)
                .filter(|p| !p.identity.is_empty())
                .map(Self::identity_of)
                .transpose()?;
            if let Some(identity) = known.or(brought) {
                let answer =
                    self.seal_for(&from, &identity, Payload::Ack { ids: vec![ack] }, None)?;
                result["replies"]
                    .as_array_mut()
                    .expect("replies is always a list")
                    .push(answer);
            }
        }
        Ok(result)
    }

    /// Acts on one payload from `from`, whose signature has been checked.
    fn take(&mut self, from: &str, opened: &envelope::Opened, payload: Payload) -> Result<Value> {
        let from = from.to_string();
        let mut people = self.people()?;
        let relation = people.get(&from).map(|p| p.relation);

        match payload {
            Payload::Request {
                name,
                note,
                identity,
                invite,
                stamp,
            } => {
                let Ok(identity) =
                    hexcode::decode(&identity).and_then(|b| PublicIdentity::from_bytes(&b))
                else {
                    return Ok(ignored());
                };
                // The identity inside must be the one that signed the
                // envelope, and must itself hold together.
                if identity.signing_key != opened.sender_signing_key || identity.verify().is_err() {
                    return Ok(ignored());
                }
                if too_long(&name, MAX_NAME_CHARS)
                    || note.as_deref().is_some_and(|n| too_long(n, MAX_NOTE_CHARS))
                {
                    return Ok(ignored());
                }
                match relation {
                    Some(Relation::Blocked) | Some(Relation::Contact) => Ok(ignored()),
                    Some(Relation::Outgoing) => {
                        // Both asked each other. That is two yeses.
                        let person = people
                            .get_mut(&from)
                            .expect("relation was read from this entry");
                        person.relation = Relation::Contact;
                        person.name = name;
                        let person = person.clone();
                        let reply = self.seal_kept(
                            &from,
                            &person,
                            Payload::Accept {
                                name: self.my_name.clone(),
                            },
                            Self::new_ack()?,
                        )?;
                        self.save(&people)?;
                        Ok(event("accepted", &from, vec![reply]))
                    }
                    Some(Relation::Incoming) => {
                        // Asked again while still waiting. Keep the newer
                        // name and note, but it is not a new request.
                        let person = people
                            .get_mut(&from)
                            .expect("relation was read from this entry");
                        person.name = name;
                        person.note = note;
                        self.save(&people)?;
                        Ok(ignored())
                    }
                    // Declined not long ago: dropped, and they are not told.
                    None if now() < self.declined(&from)?.until => Ok(ignored()),
                    // A stranger must show the work that went into their
                    // identity, so identities made in bulk cost in bulk.
                    // Checked before an invite is spent on them.
                    None if !crate::proof::stamp_sound(&identity.signing_key, stamp.as_deref()) => {
                        Ok(ignored())
                    }
                    // From one of the user's links: good only once, and
                    // only before it runs out. Otherwise quietly dropped.
                    None if invite.is_some() && !self.use_invite(invite.as_deref())? => {
                        Ok(ignored())
                    }
                    None => {
                        people.insert(
                            from.clone(),
                            Person {
                                identity: hexcode::encode(&identity.to_bytes()),
                                name,
                                note,
                                relation: Relation::Incoming,
                                verified: false,
                                thread: new_thread_id()?,
                                was_contact: false,
                                scanned: false,
                                timer: 0,
                                timer_set_at: 0,
                                hidden: false,
                                gone_ids: Vec::new(),
                            },
                        );
                        self.save(&people)?;
                        let mut asked = event("request", &from, vec![]);
                        // Came with one of the user's own links, which the
                        // user's "who can ask me" choice lets through.
                        asked["event"]["invited"] = json!(invite.is_some());
                        Ok(asked)
                    }
                }
            }
            Payload::Accept { name } => {
                // Only an answer to a question the user asked counts.
                if relation != Some(Relation::Outgoing) || too_long(&name, MAX_NAME_CHARS) {
                    return Ok(ignored());
                }
                let person = people
                    .get_mut(&from)
                    .expect("relation was read from this entry");
                person.relation = Relation::Contact;
                person.name = name;
                // An identity read off their own screen needs no words
                // compared.
                person.verified = person.scanned;
                self.save(&people)?;
                Ok(event("accepted", &from, vec![]))
            }
            Payload::Vote { target, choice } => {
                let Some(person) = people
                    .get(&from)
                    .filter(|p| p.relation == Relation::Contact)
                else {
                    return Ok(ignored());
                };
                let voted = self.update(person, |message| {
                    let poll = message.id == target && (choice as usize) < message.options.len();
                    if poll {
                        message.their_vote = Some(choice);
                    }
                    poll
                })?;
                if voted.is_empty() {
                    return Ok(ignored());
                }
                Ok(event("voted", &from, vec![]))
            }
            Payload::Timer { seconds, set_at } => {
                if relation != Some(Relation::Contact) || !TIMERS.contains(&seconds) {
                    return Ok(ignored());
                }
                let person = people
                    .get_mut(&from)
                    .expect("relation was read from this entry");
                // A clock set far ahead must not let one of the two fix
                // the timer for good.
                let set_at = set_at.min(now() + 24 * 60 * 60);
                if set_at <= person.timer_set_at {
                    return Ok(ignored());
                }
                person.timer = seconds;
                person.timer_set_at = set_at;
                self.save(&people)?;
                Ok(event("timer", &from, vec![]))
            }
            Payload::Text {
                id,
                body,
                sent_at,
                options,
                gone_in,
                card,
                forwarded,
                location,
                sticker,
            } => {
                // The request rule, enforced on arrival.
                if relation != Some(Relation::Contact) {
                    return Ok(ignored());
                }
                // A card that does not hold together is not shown as one.
                let card = match card {
                    Some(card) => match card.checked() {
                        Some(card) => Some(card),
                        None => return Ok(ignored()),
                    },
                    None => None,
                };
                // Nor is a place that is not on the globe, or one sent
                // as part of a poll or a card.
                let location = match location {
                    Some(place) => match place.checked() {
                        Some(place) if options.is_empty() && card.is_none() => Some(place),
                        _ => return Ok(ignored()),
                    },
                    None => None,
                };
                // The words with a place are the place, whatever the
                // sender put, so a list of chats shows nothing else.
                let body = location.map_or(body, |place| place.text());
                // A sticker stands alone, and has no words: one that does
                // not hold together, or comes with anything else, was not
                // sent by the app.
                if let Some(sticker) = &sticker {
                    if !sticker.sound()
                        || !body.is_empty()
                        || !options.is_empty()
                        || card.is_some()
                        || location.is_some()
                    {
                        return Ok(ignored());
                    }
                }
                // Longer than the app ever offers is not something the
                // app wrote.
                if gone_in > TIMERS[TIMERS.len() - 1] {
                    return Ok(ignored());
                }
                if (body.is_empty() && sticker.is_none())
                    || too_long(&body, MAX_BODY_CHARS)
                    || hexcode::decode_exact::<16>(&id).is_err()
                {
                    return Ok(ignored());
                }
                if !sound_choices(&options) {
                    return Ok(ignored());
                }
                let person = people
                    .get(&from)
                    .expect("relation was read from this entry");
                // A mesh can deliver the same message along two paths.
                if self.messages(person)?.iter().any(|m| m.id == id) {
                    return Ok(ignored());
                }
                // Its writer deleted it for everyone before it got here.
                if person.gone_ids.contains(&id) {
                    return Ok(ignored());
                }
                let message = StoredMessage {
                    id: id.clone(),
                    mine: false,
                    body,
                    sent_at,
                    delivered: false,
                    read: false,
                    seen: false,
                    file: None,
                    options,
                    my_vote: None,
                    their_vote: None,
                    // Counted from when it got here, by this device's
                    // own clock, whatever the sender's says.
                    gone_at: (gone_in > 0).then(|| now() + gone_in),
                    card,
                    deleted: false,
                    forwarded,
                    location,
                    sticker,
                };
                self.append(person, &message)?;
                // A new message brings a deleted chat back.
                self.unhide(&from)?;
                let mut result = event("text", &from, vec![]);
                result["event"]["id"] = json!(id);
                Ok(result)
            }
            Payload::VerifyCommit { commit } => {
                let (Some(Relation::Contact), Ok(commit)) =
                    (relation, hexcode::decode_exact::<32>(&commit))
                else {
                    return Ok(ignored());
                };
                // Both started at once. The one with the lower key carries
                // on as the starter and the other gives way, so the two
                // agree without another message.
                if matches!(self.sessions.get(&from), Some(Verifying::Started { .. }))
                    && self.me.signing_public() < opened.sender_signing_key
                {
                    return Ok(ignored());
                }
                let nonce = *random_bytes::<32>()?;
                self.sessions
                    .insert(from.clone(), Verifying::Answered { commit, nonce });
                let person = people
                    .get(&from)
                    .expect("relation was read from this entry");
                let reply = self.seal_to(
                    &from,
                    person,
                    Payload::VerifyNonce {
                        nonce: hexcode::encode(&nonce),
                    },
                )?;
                Ok(event("verify_started", &from, vec![reply]))
            }
            Payload::VerifyNonce { nonce } => {
                let (Some(Relation::Contact), Ok(their_nonce)) =
                    (relation, hexcode::decode_exact::<32>(&nonce))
                else {
                    return Ok(ignored());
                };
                let Some(Verifying::Started { nonce: my_nonce }) = self.sessions.get(&from) else {
                    return Ok(ignored());
                };
                let my_nonce = *my_nonce;
                let person = people
                    .get(&from)
                    .expect("relation was read from this entry");
                let words = sas::words(
                    &self.me.public().hash(),
                    &Self::identity_of(person)?.hash(),
                    &my_nonce,
                    &their_nonce,
                );
                self.sessions
                    .insert(from.clone(), Verifying::Ready { words });
                // Revealed only now, after their number is fixed.
                let reply = self.seal_to(
                    &from,
                    person,
                    Payload::VerifyReveal {
                        nonce: hexcode::encode(&my_nonce),
                    },
                )?;
                Ok(event("verify_ready", &from, vec![reply]))
            }
            Payload::VerifyReveal { nonce } => {
                let (Some(Relation::Contact), Ok(their_nonce)) =
                    (relation, hexcode::decode_exact::<32>(&nonce))
                else {
                    return Ok(ignored());
                };
                let Some(Verifying::Answered {
                    commit,
                    nonce: my_nonce,
                }) = self.sessions.get(&from)
                else {
                    return Ok(ignored());
                };
                let (commit, my_nonce) = (*commit, *my_nonce);
                if sas::check_reveal(&commit, &their_nonce).is_err() {
                    // They changed their number after seeing ours. Stop.
                    self.sessions.remove(&from);
                    return Ok(ignored());
                }
                let person = people
                    .get(&from)
                    .expect("relation was read from this entry");
                let words = sas::words(
                    &Self::identity_of(person)?.hash(),
                    &self.me.public().hash(),
                    &their_nonce,
                    &my_nonce,
                );
                self.sessions
                    .insert(from.clone(), Verifying::Ready { words });
                Ok(event("verify_ready", &from, vec![]))
            }
            Payload::Space { wire } => {
                // Handed up as it is. Whether to act on it depends on who
                // sent it, which is all this module adds.
                let mut result = event("space_wire", &from, vec![]);
                result["event"]["wire"] = wire;
                result["event"]["contact"] = json!(relation == Some(Relation::Contact));
                result["event"]["blocked"] = json!(relation == Some(Relation::Blocked));
                Ok(result)
            }
            Payload::File { wire } => {
                let mut result = event("file_wire", &from, vec![]);
                result["event"]["wire"] = wire;
                result["event"]["contact"] = json!(relation == Some(Relation::Contact));
                Ok(result)
            }
            Payload::Ack { ids } => {
                // Only someone the user has sent something to can say it
                // arrived, and only for what was sent to them.
                let Some(person) = people.get(&from) else {
                    return Ok(ignored());
                };
                if !Self::are_ids(&ids) {
                    return Ok(ignored());
                }
                if person.relation == Relation::Contact {
                    self.update(person, |message| {
                        let now = message.mine && !message.delivered && ids.contains(&message.id);
                        message.delivered |= now;
                        now
                    })?;
                }
                let mut result = event("delivered", &from, vec![]);
                result["event"]["ids"] = json!(ids);
                Ok(result)
            }
            Payload::Typing => {
                if relation != Some(Relation::Contact) {
                    return Ok(ignored());
                }
                Ok(event("typing", &from, vec![]))
            }
            Payload::Here { active } => {
                if relation != Some(Relation::Contact) {
                    return Ok(ignored());
                }
                let mut result = event("here", &from, vec![]);
                result["event"]["active"] = json!(active);
                Ok(result)
            }
            Payload::Away { note, set_at } => {
                let note = note.map(|note| note.split_whitespace().collect::<Vec<_>>().join(" "));
                if relation != Some(Relation::Contact)
                    || note
                        .as_deref()
                        .is_some_and(|note| too_long(note, MAX_AWAY_CHARS))
                {
                    return Ok(ignored());
                }
                let mut aways = self.aways()?;
                if aways.get(&from).is_some_and(|(_, at)| *at > set_at) {
                    return Ok(ignored());
                }
                aways.insert(from.to_string(), (note, set_at));
                let bytes = serde_json::to_vec(&aways).expect("plain data");
                self.vault.put(AWAY.0, AWAY.1, &bytes)?;
                Ok(event("away", &from, vec![]))
            }
            Payload::FastAsk => {
                if relation != Some(Relation::Contact) {
                    return Ok(ignored());
                }
                Ok(event("fast_ask", &from, vec![]))
            }
            Payload::FastOffer {
                network,
                pass,
                joins,
            } => {
                if relation != Some(Relation::Contact) || !sound_group(&network, &pass) {
                    return Ok(ignored());
                }
                let mut result = event("fast_offer", &from, vec![]);
                result["event"]["network"] = json!(network);
                result["event"]["pass"] = json!(pass);
                result["event"]["joins"] = json!(joins);
                Ok(result)
            }
            // Only a contact can call. Anyone else is not even told no.
            Payload::Call { wire } => {
                if relation != Some(Relation::Contact) {
                    return Ok(ignored());
                }
                let mut result = event("call_wire", &from, vec![]);
                result["event"]["wire"] = wire;
                Ok(result)
            }
            Payload::Photo {
                preset,
                photo,
                version,
            } => {
                // Taken from contacts only, and only a picture.
                if relation != Some(Relation::Contact)
                    || preset.is_some_and(|p| p >= PRESETS)
                    || photo.as_deref().is_some_and(|p| !sound_photo(p))
                    || (preset.is_some() && photo.is_some())
                {
                    return Ok(ignored());
                }
                if version <= self.avatar(&from)?.version {
                    return Ok(ignored());
                }
                let avatar = Avatar {
                    preset,
                    photo,
                    version,
                };
                self.vault.put(
                    AVATAR,
                    &hexcode::decode(&from)?,
                    &serde_json::to_vec(&avatar).expect("an avatar is plain data"),
                )?;
                Ok(event("photo", &from, vec![]))
            }
            Payload::Name { name } => {
                // Someone still asking keeps the name they asked under,
                // so a request cannot change its face while it waits.
                let name = name.trim();
                if relation != Some(Relation::Contact)
                    || name.is_empty()
                    || too_long(name, MAX_NAME_CHARS)
                {
                    return Ok(ignored());
                }
                people
                    .get_mut(&from)
                    .expect("relation was read from this entry")
                    .name = name.to_string();
                self.save(&people)?;
                Ok(event("renamed", &from, vec![]))
            }
            Payload::Unsend { ids } => {
                let Some(person) = people
                    .get(&from)
                    .filter(|p| p.relation == Relation::Contact)
                else {
                    return Ok(ignored());
                };
                if !Self::are_ids(&ids) {
                    return Ok(ignored());
                }
                // Only messages this person wrote, never the user's own.
                let gone = self.update(person, |message| {
                    let theirs = !message.mine && !message.deleted && ids.contains(&message.id);
                    if theirs {
                        Self::tombstone(message);
                    }
                    theirs
                })?;
                // Those not here yet are remembered, so they are dropped
                // when they come.
                let held: Vec<String> = self.messages(person)?.into_iter().map(|m| m.id).collect();
                let person = people.get_mut(&from).expect("it was just found");
                for id in ids {
                    if !held.contains(&id) && !person.gone_ids.contains(&id) {
                        person.gone_ids.push(id);
                    }
                }
                let over = person.gone_ids.len().saturating_sub(MAX_GONE_IDS);
                person.gone_ids.drain(..over);
                self.save(&people)?;
                let mut result = event("unsent", &from, vec![]);
                result["event"]["ids"] = json!(gone);
                Ok(result)
            }
            Payload::Read { ids } => {
                let Some(person) = people
                    .get(&from)
                    .filter(|p| p.relation == Relation::Contact)
                else {
                    return Ok(ignored());
                };
                if !Self::are_ids(&ids) {
                    return Ok(ignored());
                }
                let read = self.update(person, |message| {
                    let now = message.mine && !message.read && ids.contains(&message.id);
                    if now {
                        message.read = true;
                        message.delivered = true;
                    }
                    now
                })?;
                if read.is_empty() {
                    return Ok(ignored());
                }
                let mut result = event("read", &from, vec![]);
                result["event"]["ids"] = json!(read);
                Ok(result)
            }
        }
    }

    fn are_ids(ids: &[String]) -> bool {
        !ids.is_empty()
            && ids.len() <= MAX_IDS
            && ids.iter().all(|id| hexcode::decode_exact::<16>(id).is_ok())
    }

    /// Begins the word comparison with a contact.
    pub fn verify_start(&mut self, with: &str) -> Result<Value> {
        let person = Self::contact(&self.people()?, with)?;
        let nonce = *random_bytes::<32>()?;
        let commit = sas::commitment(&nonce);
        self.sessions
            .insert(with.to_string(), Verifying::Started { nonce });
        self.seal_to(
            with,
            &person,
            Payload::VerifyCommit {
                commit: hexcode::encode(&commit),
            },
        )
    }

    pub fn verify_words(&self, with: &str) -> Result<Value> {
        match self.sessions.get(with) {
            Some(Verifying::Ready { words }) => Ok(json!({ "words": words })),
            _ => Err(CoreError::Invalid("the words are not ready".into())),
        }
    }

    /// Undoes a block. Nothing is sent. Someone who was a contact is one
    /// again. Anyone else may ask again, and is not a contact until the
    /// user accepts.
    pub fn unblock(&mut self, who: &str) -> Result<Value> {
        let mut people = self.people()?;
        match people.get_mut(who) {
            // They were never told they were blocked, and still hold the
            // user as a contact. So the chat simply carries on. They are
            // to be verified afresh.
            Some(person)
                if person.relation == Relation::Blocked
                    && person.was_contact
                    && !person.identity.is_empty() =>
            {
                person.relation = Relation::Contact;
                person.was_contact = false;
            }
            Some(person) if person.relation == Relation::Blocked => {
                people.remove(who);
            }
            _ => return Ok(Value::Null),
        }
        self.save(&people)?;
        Ok(Value::Null)
    }

    /// Everyone the user has blocked, with the name each was known by.
    pub fn blocked(&self) -> Result<Value> {
        let people = self.people()?;
        Ok(people
            .iter()
            .filter(|(_, p)| p.relation == Relation::Blocked)
            .map(|(key, p)| json!({ "key": key, "name": p.name }))
            .collect())
    }

    /// The code the user and one contact can compare from anywhere: over
    /// a phone call, or sent through any other app.
    ///
    /// It is made from the two identities this device really holds. If
    /// someone stood between the two, passing themselves off to each as
    /// the other, each side holds a different pair and the codes differ.
    /// Twelve bytes, so nobody can make keys until a code happens to
    /// match. Nothing is exchanged to make it, so it needs no link.
    fn check_bytes(&self, with: &str) -> Result<[u8; 12]> {
        let people = self.people()?;
        let theirs = hexcode::decode(&Self::contact(&people, with)?.identity)?;
        let mine = self.me.public().to_bytes();
        let (first, second) = if mine <= theirs {
            (&mine, &theirs)
        } else {
            (&theirs, &mine)
        };
        let hash = sha2::Sha256::new()
            .chain_update(b"dnet check code v1")
            .chain_update(first)
            .chain_update(second)
            .finalize();
        Ok(hash[..12].try_into().expect("a SHA-256 digest is 32 bytes"))
    }

    pub fn check_code(&self, with: &str) -> Result<Value> {
        let bytes = self.check_bytes(with)?;
        let words: Vec<&str> = bytes
            .iter()
            .map(|byte| crate::words::WORDS[*byte as usize])
            .collect();
        Ok(json!({ "code": format!("{CHECK_PREFIX}{}", hexcode::encode(&bytes)), "words": words }))
    }

    /// Compares a code the other person sent with the one this device
    /// makes. If they are the same the person is marked verified. The
    /// code may arrive with other words around it.
    pub fn check_paste(&mut self, with: &str, pasted: &str) -> Result<Value> {
        let mine = hexcode::encode(&self.check_bytes(with)?);
        let theirs = pasted.split(CHECK_PREFIX).nth(1).map(|rest| {
            rest.chars()
                .take_while(char::is_ascii_hexdigit)
                .collect::<String>()
                .to_lowercase()
        });
        let matched = theirs.as_deref() == Some(mine.as_str());
        if matched {
            let mut people = self.people()?;
            people.get_mut(with).ok_or(CoreError::NotAContact)?.verified = true;
            self.save(&people)?;
        }
        Ok(json!({ "matched": matched }))
    }

    /// Records the user's answer. Only "they match", after a finished
    /// exchange, marks the person verified.
    pub fn verify_confirm(&mut self, with: &str, matched: bool) -> Result<Value> {
        let Some(Verifying::Ready { .. }) = self.sessions.remove(with) else {
            return Err(CoreError::Invalid("there are no words to confirm".into()));
        };
        if matched {
            let mut people = self.people()?;
            let person = people
                .get_mut(with)
                .filter(|p| p.relation == Relation::Contact)
                .ok_or(CoreError::NotAContact)?;
            person.verified = true;
            self.save(&people)?;
        }
        Ok(Value::Null)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_wait_after_declining_grows_from_hours_to_days() {
        let hour = 60 * 60;
        assert_eq!(decline_wait(0), 0);
        assert_eq!(decline_wait(1), 4 * hour);
        assert_eq!(decline_wait(2), 24 * hour);
        assert_eq!(decline_wait(3), 72 * hour);
        assert_eq!(decline_wait(40), 72 * hour);
    }
}
