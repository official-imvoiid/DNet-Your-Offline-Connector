//! Spaces: groups with channels.
//!
//! A space lives on its members' devices and nowhere else. Everything said
//! in it is an *item*: sealed with the space's key, signed by whoever wrote
//! it, and passed from member to member whenever two of them meet. There
//! is no server and no list of spaces anywhere.
//!
//! - A **private** space's key is given only in an invite. People nearby
//!   are never told the space exists.
//! - A **public** space, and a public **channel** where only the owner
//!   posts, announce themselves to devices nearby, key included, so anyone
//!   can join. They are public: nothing said in one is secret.
//!
//! What this does not do: there is no way yet to remove a member or change
//!   a space's key, so anyone who was ever let in can read on. And a member
//!   learns which other members are in range, because syncing with them is
//!   how the space travels.

use std::collections::{BTreeMap, HashSet};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::chat::Sticker;
use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::identity::{
    verify_signature, IdentitySecret, PublicIdentity, SIGNATURE_LEN, SIGNING_LEN,
};
use crate::place::Place;
use crate::seal::{self, random_bytes};
use crate::shelf::{self, Shelf, Taken};
use crate::vault::Vault;

const SPACE: &str = "space";
const ITEM: &str = "space_item";
/// Each space's icon as this device holds it, by space.
const ICON: &str = "space_icon";

const MANIFEST_CONTEXT: &[u8] = b"dnet space manifest v1";
const HANDOVER_CONTEXT: &[u8] = b"dnet space handover v1";
/// How many times a space can change hands, and how many of an owner's
/// decisions a hand-over can carry. Both are far more than a space of
/// people who know each other needs, and keep what has to be checked, and
/// passed to every newcomer, to a size that can be.
const MAX_HANDOVERS: usize = 16;
const MAX_HANDOVER_LOG: usize = 300;
const ITEM_CONTEXT: &[u8] = b"dnet space item v1";
const ITEM_KEY_CONTEXT: &[u8] = b"dnet space item key v1";
const TAG_CONTEXT: &[u8] = b"dnet space tag v1";
const LINK_PREFIX: &str = "dnet:space/";
/// What whoever made a link that runs out signs: the link up to their
/// signature, then the space's name.
const LINK_CONTEXT: &[u8] = b"dnet space link v2";
/// How long a link that runs out may last, in seconds: an hour to thirty
/// days.
const LINK_SHORTEST: u64 = 60 * 60;
const LINK_LONGEST: u64 = 30 * 24 * 60 * 60;

const MAX_NAME_CHARS: usize = 64;
const MAX_DESCRIPTION_CHARS: usize = 140;
const MAX_WELCOME_CHARS: usize = 500;
/// The largest profile photo that goes into a space, in bytes. It travels
/// inside one item, which has room for no more.
const MAX_SPACE_PHOTO_BYTES: usize = 32 * 1024;
/// The largest space icon, in bytes: a small picture or GIF. Only its
/// fingerprint goes in what the owner signs, which public spaces announce
/// to every device nearby. The picture itself goes apart, to whoever asks.
const MAX_ICON_BYTES: usize = 24 * 1024;
const MAX_RULES_CHARS: usize = 2_000;
const MAX_BODY_CHARS: usize = 16_000;
/// A poll offers at least two choices and no more than this.
const MAX_CHOICES: usize = 6;
const MAX_CHOICE_CHARS: usize = 80;
const MAX_CHANNELS: usize = 64;
/// The most people one message can call on.
const MAX_MENTIONS: usize = 20;
/// Larger than any honest item. Anything bigger is not even opened.
const MAX_ITEM_BYTES: usize = 96 * 1024;
/// How many of a space's items one device offers another when they meet.
/// Older ones stay where they are.
const MAX_OFFERED: usize = 2_000;
/// The most one sync message carries, so it always fits an envelope.
const MAX_BATCH_BYTES: usize = 192 * 1024;
const MAX_ANNOUNCED: usize = 64;

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Debug)]
#[serde(rename_all = "snake_case")]
enum Kind {
    /// Invite only. Never announced.
    Private,
    /// Anyone nearby can find it and join.
    Public,
    /// Public, and only its owner posts.
    Channel,
}

impl Kind {
    fn byte(self) -> u8 {
        match self {
            Kind::Private => 0,
            Kind::Public => 1,
            Kind::Channel => 2,
        }
    }

    fn from_byte(byte: u8) -> Option<Self> {
        [Kind::Private, Kind::Public, Kind::Channel]
            .into_iter()
            .find(|kind| kind.byte() == byte)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Status {
    Joined,
    /// A contact sent an invite. Nothing is taken in until the user joins.
    Invited,
    /// A public space a device nearby announced.
    Nearby,
}

#[derive(Clone, Serialize, Deserialize)]
struct ChannelDef {
    id: String,
    name: String,
    /// "announcements", "text" or "voice".
    kind: String,
    /// "info", "text" or "voice": where it is listed.
    group: String,
    /// Slow mode: how many seconds a member must leave between two
    /// messages here. 0 is no limit. The owner and admins are not bound.
    #[serde(default)]
    slow: u32,
    /// Members may not post links here.
    #[serde(default)]
    no_links: bool,
    /// When these rules were last set. They bind what is written after
    /// that, so setting a rule never hides what was said before it.
    #[serde(default)]
    since: u64,
    /// How many seconds a message written here lasts before every device
    /// deletes it. 0: messages stay.
    #[serde(default)]
    disappear: u32,
    /// The longest a member's message here may be, in characters. 0: no
    /// limit beyond the app's own.
    #[serde(default)]
    max_len: u32,
    /// If any: only members holding one of these roles (and the owner and
    /// admins) write here. Everyone in the space can still read it.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    writers: Vec<String>,
}

/// A role the owner made: a name, and what whoever holds it may do.
#[derive(Clone, Serialize, Deserialize)]
struct RoleDef {
    id: String,
    name: String,
    /// Some of [`ROLE_POWERS`].
    may: Vec<String>,
}

/// What a role can let its holder do: pin messages, write in the
/// announcement channels, take down anyone's message, time a member out,
/// and call on everyone in the space at once with @everyone. Running the
/// space itself (its name, channels, roles and who is in it) stays with
/// the owner.
const ROLE_POWERS: [&str; 5] = ["pin", "announce", "delete", "timeout", "mention_everyone"];

/// What a member can tell fellow members in range about themselves.
/// "invisible" is never sent: a member who chose it tells nobody anything.
pub const STATUSES: [&str; 4] = ["online", "idle", "dnd", "invisible"];
const MAX_ROLES: usize = 20;
const MAX_ROLE_NAME_CHARS: usize = 32;

/// What a post says about a file it carries. The file itself is fetched
/// from whoever holds it (see `shelf.rs`).
#[derive(Clone, Serialize, Deserialize)]
struct Attached {
    sha256: String,
    name: String,
    size: u64,
    /// "picture", "video", "voice" or "file".
    kind: String,
    /// How long a voice message or a video is.
    #[serde(default, skip_serializing_if = "is_zero_u32")]
    seconds: u32,
}

const FILE_KINDS: [&str; 4] = ["picture", "video", "voice", "file"];
const MAX_FILE_NAME_BYTES: usize = 255;

impl Attached {
    fn sound(&self) -> bool {
        // A voice message is at most an hour; a video may be a film.
        let longest = if self.kind == "video" {
            12 * 60 * 60
        } else {
            60 * 60
        };
        hexcode::decode_exact::<32>(&self.sha256).is_ok()
            && !self.name.trim().is_empty()
            && self.name.len() <= MAX_FILE_NAME_BYTES
            && (1..=shelf::MAX_SIZE).contains(&self.size)
            && FILE_KINDS.contains(&self.kind.as_str())
            && self.seconds <= longest
    }
}

/// A new post as the user writes it.
#[derive(Default)]
pub struct NewPost {
    pub body: String,
    pub reply_to: Option<String>,
    /// The choices, if it is a poll.
    pub options: Vec<String>,
    /// Members it calls on, by signing key.
    pub mentions: Vec<String>,
    /// Calls on everyone in the space. Only the owner, admins and roles
    /// allowed to may.
    pub everyone: bool,
    /// Roles it calls on, by id: whoever holds one is called.
    pub roles: Vec<String>,
    /// Passed on from another channel or a chat.
    pub forwarded: bool,
    /// Where the user is, if that is what they post. Its words are then
    /// the place written out.
    pub location: Option<Place>,
    /// A sticker, if that is what they post. It has no words.
    pub sticker: Option<Sticker>,
}

/// A file the user posts: where it is on the device, and what it is.
pub struct FileToPost {
    pub path: std::path::PathBuf,
    /// "picture", "video", "voice" or "file".
    pub kind: String,
    /// What to call it, if not its own name.
    pub name: Option<String>,
    /// How long a voice message or a video is.
    pub seconds: u32,
}

/// The longest messages the owner can allow in a channel.
const LENGTH_CHOICES: [u32; 3] = [200, 500, 2000];
/// The most words or phrases the owner can keep out of a space, and the
/// longest each may be.
const MAX_BANNED: usize = 50;
const MAX_BANNED_CHARS: usize = 32;

/// A message's words, in small letters, without what is between them.
fn words_of(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .map(str::to_string)
        .collect()
}

/// How long the same words from one member in one channel count as a
/// repeat: ten minutes, in milliseconds.
const REPEAT_WINDOW: u64 = 10 * 60 * 1000;
/// The most messages one member may write in a space in a minute.
const MAX_PER_MINUTE: usize = 20;

/// A message's words, for telling whether two say the same thing.
fn same_words(body: &str) -> String {
    let words = words_of(body).join(" ");
    if words.is_empty() {
        body.trim().to_lowercase()
    } else {
        words
    }
}

/// What a post says, for telling whether two say the same thing. A post
/// with a file is told apart by the file as well as its words, and a
/// sticker by which sticker it is, so different pictures without words
/// are not taken for one sent twice.
fn post_words(body: &str, file: Option<&Attached>, sticker: Option<&Sticker>) -> String {
    match (file, sticker) {
        (_, Some(sticker)) if sticker.image.is_empty() => format!("sticker:{}", sticker.name),
        (_, Some(sticker)) => {
            format!(
                "sticker:{}",
                hexcode::encode(&Sha256::digest(sticker.image.as_bytes()))
            )
        }
        (Some(file), None) => format!("file:{}:{}", file.sha256, same_words(body)),
        (None, None) => same_words(body),
    }
}

/// Spam a member's message would be, judged against what they wrote
/// before it in this space, as (sent at, channel, words): "repeat" for the
/// same words in the same channel within ten minutes, "fast" for more
/// than twenty messages in a minute. None if it is neither.
fn spam_of(
    earlier: &[(u64, &str, String)],
    at: u64,
    channel: &str,
    words: &str,
) -> Option<&'static str> {
    if earlier
        .iter()
        .any(|(when, c, w)| *c == channel && w == words && at.saturating_sub(*when) < REPEAT_WINDOW)
    {
        return Some("repeat");
    }
    let recent = earlier
        .iter()
        .filter(|(when, _, _)| at.saturating_sub(*when) < 60 * 1000)
        .count();
    (recent >= MAX_PER_MINUTE).then_some("fast")
}

/// Whether a message has one of the words or phrases the owner keeps
/// out: whole words only, so "spoiler" does not catch "spoilers", and
/// capitals do not matter.
fn has_banned(body: &str, banned: &[String]) -> bool {
    if banned.is_empty() {
        return false;
    }
    let words = words_of(body);
    banned.iter().any(|ban| {
        let parts = words_of(ban);
        !parts.is_empty()
            && words
                .windows(parts.len())
                .any(|run| run == parts.as_slice())
    })
}

/// The owner's rules for one channel, as asked for. What is not given is
/// left as it is.
#[derive(Default)]
pub struct ChannelRules {
    pub slow: Option<u32>,
    pub no_links: Option<bool>,
    pub owners_only: Option<bool>,
    pub disappear: Option<u32>,
    pub max_len: Option<u32>,
    /// Role ids. Empty: everyone writes.
    pub writers: Option<Vec<String>>,
}

/// How long the owner can have a channel's messages last: an hour, a day
/// or a week.
const DISAPPEAR_CHOICES: [u32; 3] = [60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60];

fn is_zero_u32(n: &u32) -> bool {
    *n == 0
}

fn is_zero_u64(n: &u64) -> bool {
    *n == 0
}

/// When an item is to be deleted from every device, if it is. A post goes
/// after what it says it lasts, or what its channel says if that is
/// shorter, so a changed app cannot make one outlast the channel's rule.
/// A change to a post goes when the post does.
fn ends_at(event: &Event, manifest: Option<&Manifest>) -> Option<u64> {
    match event {
        Event::Post {
            channel,
            sent_at,
            lasts,
            ..
        } => {
            let rule = manifest
                .and_then(|m| m.channels.iter().find(|c| c.id == *channel))
                .filter(|c| c.disappear > 0 && *sent_at >= c.since)
                .map(|c| c.disappear);
            let own = (*lasts > 0).then_some(*lasts);
            let life = match (own, rule) {
                (Some(a), Some(b)) => Some(a.min(b)),
                (a, b) => a.or(b),
            };
            life.map(|seconds| sent_at.saturating_add(seconds as u64 * 1000))
        }
        Event::Edit { until, .. } if *until > 0 => Some(*until),
        _ => None,
    }
}

/// Whether a message has a link in it, in any form one can be written:
/// with a scheme ("https://", "ftp://"), starting "www.", a DNet invite,
/// or a bare name such as "example.com", which is also what a markdown
/// link "[words](example.com)" points at. An e-mail address is not a
/// link. The app checks the same way before sending, so the two agree:
/// see `SafeLink.hasLink` in app/lib/data/safe_link.dart.
pub(crate) fn has_link(body: &str) -> bool {
    let lower = body.to_lowercase();
    if ["www.", "dnet:space/", "dnet:invite/"]
        .iter()
        .any(|mark| lower.contains(mark))
    {
        return true;
    }
    // A scheme is letters just before "://".
    let mut from = 0;
    while let Some(found) = lower[from..].find("://") {
        let at = from + found;
        if lower[..at]
            .chars()
            .next_back()
            .is_some_and(|c| c.is_ascii_alphabetic())
        {
            return true;
        }
        from = at + 3;
    }
    has_bare_name(body)
}

/// The endings of web names that are not two letters, as the ones of
/// countries are. Any two letters count.
const NAME_ENDINGS: [&str; 74] = [
    "com", "net", "org", "edu", "gov", "mil", "int", "info", "biz", "name", "pro", "mobi", "app",
    "dev", "page", "xyz", "online", "site", "store", "shop", "link", "click", "top", "club",
    "live", "news", "blog", "tech", "cloud", "zip", "mov", "art", "wiki", "fun", "space",
    "website", "email", "life", "world", "today", "network", "digital", "social", "media", "video",
    "stream", "chat", "games", "game", "bet", "win", "vip", "icu", "cyou", "sbs", "cfd", "buzz",
    "rest", "bond", "lol", "monster", "quest", "run", "onion", "lat", "cam", "xxx", "porn", "sex",
    "coop", "aero", "museum", "travel", "asia",
];

/// Whether `body` has a web name in it with no scheme, as "example.com"
/// or "maps.example.org/trail". Runs of letters, digits, dots and dashes
/// are looked at; anything not ASCII counts as a letter, so the app and
/// the core cut the text the same way.
fn has_bare_name(body: &str) -> bool {
    let joins = |c: char| !c.is_ascii() || c.is_ascii_alphanumeric() || c == '.' || c == '-';
    let mut before: Option<char> = None;
    let mut run = String::new();
    for c in body.chars().chain(std::iter::once(' ')) {
        if joins(c) {
            run.push(c);
            continue;
        }
        if !run.is_empty() {
            // After an @ it is an e-mail address, or someone's name.
            if before != Some('@') && is_web_name(&run) {
                return true;
            }
            run.clear();
        }
        before = Some(c);
    }
    false
}

/// Whether one run of text, as cut by [`has_bare_name`], is a web name.
fn is_web_name(run: &str) -> bool {
    let run = run.trim_matches(|c| c == '.' || c == '-');
    let labels: Vec<&str> = run.split('.').collect();
    if labels.len() < 2
        || labels
            .iter()
            .any(|label| label.trim_matches('-').is_empty())
    {
        return false;
    }
    let end = labels[labels.len() - 1];
    let lower = end.to_lowercase();
    if lower.starts_with("xn--") && lower.len() > 4 {
        return true;
    }
    if !end.chars().all(|c| c.is_ascii_alphabetic()) {
        return false;
    }
    // "home.It was late" is a missed space, not a web name: an ending
    // written with a capital and then small letters does not count.
    let mut letters = end.chars();
    if letters.next().is_some_and(|c| c.is_ascii_uppercase())
        && letters.any(|c| c.is_ascii_lowercase())
    {
        return false;
    }
    lower.len() == 2 || NAME_ENDINGS.contains(&lower.as_str())
}

/// Whether a post has a link in its words or, for a poll, its choices.
fn post_has_link(body: &str, options: &[String]) -> bool {
    has_link(body) || options.iter().any(|choice| has_link(choice))
}

/// What a space is: its name, kind and channels. Signed by its owner.
#[derive(Clone, Serialize, Deserialize)]
struct Manifest {
    id: String,
    name: String,
    kind: Kind,
    #[serde(default)]
    description: String,
    owner: String,
    channels: Vec<ChannelDef>,
    /// Goes up each time the owner changes the name, the description or
    /// the channels. The highest one heard is the one that counts.
    #[serde(default)]
    version: u32,
    /// If the space has changed hands: every hand-over, oldest first,
    /// from whoever made it to `owner`. Anyone given this manifest can
    /// check the whole way through, knowing only who made the space.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    chain: Vec<Handover>,
    /// Who made the space, if it has changed hands since.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    founder: String,
    /// Words and phrases the owner keeps out of every channel, in small
    /// letters. They bind what members write after `banned_since`.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    banned: Vec<String>,
    #[serde(default, skip_serializing_if = "is_zero_u64")]
    banned_since: u64,
    /// The owner or an admin switched the word filter off. The list is
    /// kept for when it is switched on again.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    words_off: bool,
    /// The roles the owner has made, in the order they were made.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    roles: Vec<RoleDef>,
    /// What the owner says to everyone who joins.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    welcome: String,
    /// The space's rules, as the owner wrote them.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    rules: String,
    /// The SHA-256 of the space's icon, hex, if it has one. The picture
    /// is sent apart, so that what is announced nearby stays small.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    icon: String,
}

impl Manifest {
    /// Who made the space.
    fn founder(&self) -> &str {
        if self.founder.is_empty() {
            &self.owner
        } else {
            &self.founder
        }
    }
}

/// One hand-over of a space: the outgoing owner's word that it is someone
/// else's from a given moment, kept exactly as they signed it.
#[derive(Clone, PartialEq, Serialize, Deserialize)]
struct Handover {
    /// The signed bytes, hex. They read as a [`Handed`].
    statement: String,
    signature: String,
}

/// What a hand-over says.
#[derive(Clone, Serialize, Deserialize)]
struct Handed {
    space: String,
    /// Which hand-over of this space it is: 0 for the first.
    index: u32,
    from: String,
    to: String,
    /// When, in milliseconds. `to` owns the space from then.
    at: u64,
    /// Everything `from` decided as owner that still matters: who they
    /// made an admin or stopped being one, who they removed or let back,
    /// each with its time.
    ///
    /// Once a space has been handed over, this list is all of the old
    /// owner's word as owner that any device goes by. So nothing they
    /// sign afterwards counts as an owner's decision, whatever date they
    /// put on it.
    #[serde(default)]
    log: Vec<Event>,
}

fn signed_handover(statement: &[u8]) -> Vec<u8> {
    [HANDOVER_CONTEXT, statement].concat()
}

/// Checks a run of hand-overs link by link, starting from whoever made
/// the space, and returns what each says. `None` if any is not signed by
/// the owner before it, is out of place, or holds something it may not.
fn read_chain(space: &str, founder: &str, chain: &[Handover]) -> Option<Vec<Handed>> {
    if chain.len() > MAX_HANDOVERS {
        return None;
    }
    let mut owner = founder.to_string();
    let mut since = 0;
    let mut said = Vec::new();
    for (index, link) in chain.iter().enumerate() {
        let bytes = hexcode::decode(&link.statement).ok()?;
        let signature = hexcode::decode(&link.signature).ok()?;
        if bytes.len() > MAX_ITEM_BYTES || signature.len() != SIGNATURE_LEN {
            return None;
        }
        let key = hexcode::decode_exact::<SIGNING_LEN>(&owner).ok()?;
        verify_signature(&key, &signed_handover(&bytes), &signature).ok()?;
        let handed: Handed = serde_json::from_slice(&bytes).ok()?;
        let sound = handed.space == space
            && handed.index as usize == index
            && handed.from == owner
            && handed.to != owner
            && hexcode::decode_exact::<SIGNING_LEN>(&handed.to).is_ok()
            && handed.at >= since
            && handed.log.len() <= MAX_HANDOVER_LOG
            && handed.log.iter().all(|event| match event {
                Event::Role {
                    member, sent_at, ..
                }
                | Event::Remove {
                    member, sent_at, ..
                }
                | Event::Grant {
                    member, sent_at, ..
                } => *sent_at <= handed.at && hexcode::decode_exact::<SIGNING_LEN>(member).is_ok(),
                _ => false,
            });
        if !sound {
            return None;
        }
        owner = handed.to.clone();
        since = handed.at;
        said.push(handed);
    }
    Some(said)
}

/// Whether one run of hand-overs carries on from another: the same as far
/// as the other goes, and perhaps further.
fn extends(longer: &[Handover], shorter: &[Handover]) -> bool {
    longer.len() >= shorter.len() && longer[..shorter.len()] == *shorter
}

/// One owner's time: who, and from when. For an owner who has handed the
/// space on, also what they decided while it was theirs.
struct Term {
    owner: String,
    from: u64,
    log: Vec<Event>,
}

/// What this device keeps about one space.
#[derive(Clone, Serialize, Deserialize)]
struct Record {
    key: String,
    owner: String,
    status: Status,
    /// The name and kind as last heard. They come with an invite link, so
    /// a space can be shown before its manifest arrives.
    name: String,
    kind: Kind,
    #[serde(default)]
    description: String,
    /// The exact signed bytes, hex. Empty until a member has been met.
    #[serde(default)]
    manifest: String,
    #[serde(default)]
    signature: String,
    #[serde(default)]
    invited_by: Option<String>,
    /// Items are numbered in the order they reached this device.
    #[serde(default)]
    next_arrival: u64,
    /// For each channel, how many arrivals had been read.
    #[serde(default)]
    read: BTreeMap<String, u64>,
    /// Nothing written before this counts as unread.
    #[serde(default)]
    joined_at: u64,
    /// The latest time seen on anything in this space. The user's own
    /// writing is always stamped later than this, so an answer never sorts
    /// above what it answers, whatever the devices' clocks say.
    #[serde(default)]
    clock: u64,
    #[serde(default)]
    muted: bool,
    /// The keys this space had before someone was removed from it, newest
    /// first. Kept to open what was written under them.
    #[serde(default)]
    old_keys: Vec<String>,
    /// How many times the key has been changed.
    #[serde(default)]
    epoch: u32,
    /// The owner deleted the space. The record is kept, with the owner's
    /// word of it and nothing else, so that members met later are told
    /// and the space cannot be joined again by an old link.
    #[serde(default)]
    closed: bool,
    /// What the user goes by in this space, if not their usual name.
    #[serde(default)]
    nick: Option<String>,
    /// Every hand-over of this space this device has taken as true,
    /// oldest first. `owner` above is who made the space and never
    /// changes: it is what this device was first told, and what each
    /// hand-over is checked back to. A hand-over that does not carry on
    /// from these is refused, so an old owner cannot hand the same space
    /// to someone else later and be believed here.
    #[serde(default)]
    chain: Vec<Handover>,
}

/// One thing that happened in a space. Times are in milliseconds.
// The manifest variant carries the whole manifest; the others are small.
// Boxing it would touch every match on it for no gain: events are made,
// sealed and dropped, never kept in bulk.
#[allow(clippy::large_enum_variant)]
#[derive(Clone, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
enum Event {
    /// "I am in this space, and this is what to call me." Carries the
    /// writer's identity so that others can send them a chat request.
    Member {
        name: String,
        identity: String,
        sent_at: u64,
        /// Their profile photo, hex, if they show it: a small picture or
        /// GIF.
        #[serde(default, skip_serializing_if = "String::is_empty")]
        photo: String,
    },
    Left {
        sent_at: u64,
    },
    Post {
        id: String,
        channel: String,
        body: String,
        sent_at: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        reply_to: Option<String>,
        /// The choices, if this is a poll. The body is its question.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        options: Vec<String>,
        /// What the writer goes by, where the space keeps no list of
        /// members to look it up in.
        #[serde(default, skip_serializing_if = "String::is_empty")]
        name: String,
        /// Who it calls on, by signing key. Only members count.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        mentions: Vec<String>,
        /// How many seconds it lasts, from the channel's rule when it was
        /// written. 0: for good.
        #[serde(default, skip_serializing_if = "is_zero_u32")]
        lasts: u32,
        /// A file it carries: what it is, not the file itself.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        file: Option<Box<Attached>>,
        /// Calls on everyone in the space. It counts only from someone
        /// who could at the time: the owner, an admin, or a role allowed
        /// to. Signed with the rest, so nobody can add it on the way.
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        everyone: bool,
        /// The roles it calls on, by id. Whoever held one when it was
        /// written is called.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        roles: Vec<String>,
        /// Passed on from another channel or a chat. Where from, and who
        /// wrote it first, is not said.
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        forwarded: bool,
        /// Where the writer was, if that is what they posted. The body is
        /// the same place in words.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        location: Option<Place>,
        /// A sticker, if that is what was posted. The body is then empty.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        sticker: Option<Sticker>,
    },
    React {
        target: String,
        kind: String,
        on: bool,
        sent_at: u64,
    },
    /// The owner putting a message at the top of its channel, or taking it
    /// down.
    Pin {
        target: String,
        on: bool,
        sent_at: u64,
    },
    /// One person's choice in a poll. Their latest is the one counted.
    ///
    /// It is signed like everything else, which is what makes it one vote
    /// each. So members' devices do learn who chose what; the app does
    /// not show it.
    Vote {
        target: String,
        choice: u32,
        sent_at: u64,
    },
    /// The owner changing what the space is: its name, its description or
    /// its channels. Carries the whole manifest, signed afresh.
    Manifest {
        manifest: String,
        signature: String,
        sent_at: u64,
    },
    /// The owner making someone an admin, or no longer one.
    Role {
        member: String,
        admin: bool,
        sent_at: u64,
    },
    /// The owner giving a member one of the space's roles, or (`on:
    /// false`) taking it back.
    Grant {
        member: String,
        role: String,
        on: bool,
        sent_at: u64,
    },
    /// The owner putting someone out of the space, or (`on: false`)
    /// letting them back.
    Remove {
        member: String,
        on: bool,
        sent_at: u64,
    },
    /// Taking a message down. Its writer may, and so may whoever runs the
    /// space.
    Delete {
        target: String,
        sent_at: u64,
    },
    /// The writer of a message changing its words. Only its writer's
    /// change counts, and the newest one is shown. A poll's question is
    /// never changed: votes were cast on it as it was.
    Edit {
        target: String,
        body: String,
        sent_at: u64,
        /// When the message changed is to disappear, if it is: the change
        /// goes with it.
        #[serde(default, skip_serializing_if = "is_zero_u64")]
        until: u64,
    },
    /// The owner deleting the whole space.
    Closed {
        sent_at: u64,
    },
    /// The owner handing the space to someone else. Carries their signed
    /// word of it, a [`Handover`].
    Handover {
        statement: String,
        signature: String,
        sent_at: u64,
    },
    /// Whoever runs the space telling a member to keep quiet until
    /// `until`. Their latest word on each member is the one that counts,
    /// so an `until` already past lifts it.
    Timeout {
        member: String,
        until: u64,
        sent_at: u64,
    },
    /// Whoever runs the space setting what a member is called there, or
    /// with an empty name letting them go by their own again. Their latest
    /// word on each member counts.
    Nick {
        member: String,
        name: String,
        sent_at: u64,
    },
    /// Whoever runs the space muting a member in its voice rooms, or
    /// deafening them so they hear nothing there, or with both false,
    /// letting them be. Their latest word on each member counts.
    Voice {
        member: String,
        #[serde(default)]
        mute: bool,
        #[serde(default)]
        deafen: bool,
        sent_at: u64,
    },
}

impl Event {
    fn sent_at(&self) -> u64 {
        match self {
            Event::Member { sent_at, .. }
            | Event::Left { sent_at }
            | Event::Post { sent_at, .. }
            | Event::React { sent_at, .. }
            | Event::Pin { sent_at, .. }
            | Event::Vote { sent_at, .. }
            | Event::Manifest { sent_at, .. }
            | Event::Role { sent_at, .. }
            | Event::Remove { sent_at, .. }
            | Event::Grant { sent_at, .. }
            | Event::Delete { sent_at, .. }
            | Event::Edit { sent_at, .. }
            | Event::Closed { sent_at }
            | Event::Handover { sent_at, .. }
            | Event::Timeout { sent_at, .. }
            | Event::Nick { sent_at, .. }
            | Event::Voice { sent_at, .. } => *sent_at,
        }
    }
}

/// A sealed item as stored: its id, the order it arrived in, its bytes.
type Stored = ([u8; 16], u64, Vec<u8>);

/// The new key for one member who is staying: their signing key, their
/// identity, and what to send them.
pub(crate) type Rekeying = (String, String, Wire);

/// A member's name and identity.
type Membership = (String, String);

/// An item this device holds, opened.
struct Item {
    arrival: u64,
    /// Who signed it, hex.
    author: String,
    event: Event,
}

/// A space as its owner signed it, with the key that opens it.
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct Announcement {
    manifest: String,
    signature: String,
    key: String,
}

#[derive(Serialize, Deserialize)]
pub(crate) struct HaveSpace {
    id: String,
    ids: Vec<String>,
    has_manifest: bool,
}

/// What two devices say to each other about spaces. Always inside a sealed
/// envelope between the two of them.
#[derive(Serialize, Deserialize)]
#[serde(tag = "w", rename_all = "snake_case")]
pub(crate) enum Wire {
    /// Sent on meeting. `tags` lets the two find the spaces they share
    /// without naming any space to someone who is not in it. `public` is
    /// what anyone nearby may know about.
    Hello {
        tags: Vec<String>,
        #[serde(default)]
        public: Vec<Announcement>,
        /// Ask the other device to start comparing notes.
        #[serde(default)]
        sync: bool,
    },
    /// "For the spaces we share, this is what I hold."
    Have {
        spaces: Vec<HaveSpace>,
        /// Ask for the same in return.
        #[serde(default)]
        want: bool,
    },
    /// Items the other device lacks.
    Items {
        space: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        manifest: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        signature: Option<String>,
        items: Vec<String>,
    },
    /// An invite to a private space, from a contact.
    Invite { space: Announcement },
    /// "Send me the pieces of this file, from this one on."
    FileWant {
        space: String,
        file: String,
        from: u64,
    },
    /// Some pieces of a file, in order, starting at `from`.
    FilePieces {
        space: String,
        file: String,
        from: u64,
        pieces: Vec<String>,
    },
    /// From a private space's owner to a member who is staying, after
    /// someone was removed: the key to use from now on. Whoever was
    /// removed is not sent it.
    Rekey {
        space: String,
        epoch: u32,
        key: String,
    },
    /// "This is how I am": "online", "idle" or "dnd", or "offline" to take
    /// back what was said before going invisible. Sent only to a device
    /// that shares a space, and never by someone invisible. With `away`,
    /// the sender also said they are away, and why, as with ".afk lunch".
    Status {
        status: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        away: Option<String>,
    },
    /// "I am writing in this channel." Sent once, to members in range, by
    /// someone who switched on "show when I'm typing". Never kept.
    Typing { space: String, channel: String },
    /// "Send me this space's icon: the picture whose SHA-256 is `icon`."
    IconWant { space: String, icon: String },
    /// A space's icon, hex. Whoever takes it checks it against the
    /// fingerprint the owner signed, so it may come from anyone.
    Icon { space: String, icon: String },
    /// About one of the space's voice rooms: who is inside, and letting
    /// someone in. `call.rs` knows what it means. Never kept.
    Room {
        space: String,
        channel: String,
        call: Value,
    },
}

/// What one arriving sync message led to.
#[derive(Default)]
pub(crate) struct Outcome {
    /// To send back to whoever sent it.
    pub replies: Vec<Wire>,
    /// Items this device had not seen, by space, to pass on to other
    /// members in range.
    pub fresh: Vec<(String, Vec<Vec<u8>>)>,
    /// The spaces that now look different.
    pub changed: bool,
    /// A space's key changed, so devices in range need to be shown this
    /// device's spaces again.
    pub rekeyed: bool,
    /// A member in range is writing in this space and channel.
    pub typing: Option<(String, String)>,
    /// A member in range said something about this voice room.
    pub room: Option<(String, String, Value)>,
}

/// What this device knows about the spaces of one device in range.
#[derive(Default)]
pub(crate) struct PeerSpaces {
    /// The tags it showed. Kept so that joining a space later can be
    /// matched against them without asking again.
    tags: HashSet<String>,
    /// The spaces both are in.
    pub shared: HashSet<String>,
    /// How it says it is: "online", "idle" or "dnd". None until it says,
    /// and after it goes invisible.
    pub status: Option<String>,
    /// What it was last told of the user's own status.
    pub told: Option<String>,
    /// Why it said it is away, if it did. Empty when it gave no reason.
    pub away: Option<String>,
    /// What it was last told of the user being away.
    pub told_away: Option<String>,
}

pub(crate) struct Spaces<'a> {
    pub vault: &'a Vault,
    pub me: &'a IdentitySecret,
    pub my_name: &'a str,
    /// The user's profile photo, hex, if they show it. Members of their
    /// spaces are given it with what they go by.
    pub my_photo: Option<&'a str>,
    /// The folder where files posted in channels are kept.
    pub files: &'a Path,
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// What an invite link says.
struct Invite {
    id: [u8; 16],
    key: String,
    owner: String,
    kind: Kind,
    name: String,
    /// When it stops letting anyone in, in milliseconds, if it does.
    expires: Option<u64>,
}

/// Reads an invite link. A link that runs out carries its end time signed
/// by whoever made it, so nobody it passes through can make it last
/// longer.
///
/// Version 1: 1, space (16), key (32), owner (32), kind (1), name.
/// Version 2: 2, the same up to kind, end time (8), maker (32),
/// signature (64), name.
fn read_link(link: &str) -> Result<Invite> {
    let not_an_invite = || invalid("that is not a DNet invite");
    let bytes = link
        .trim()
        .strip_prefix(LINK_PREFIX)
        .and_then(|hex| hexcode::decode(hex).ok())
        .ok_or_else(not_an_invite)?;
    let (name, expires) = match bytes.first() {
        Some(1) if bytes.len() > 82 => (&bytes[82..], None),
        Some(2) if bytes.len() > 186 => {
            let signed = [LINK_CONTEXT, &bytes[..122], &bytes[186..]].concat();
            verify_signature(&bytes[90..122], &signed, &bytes[122..186])
                .map_err(|_| not_an_invite())?;
            let end: [u8; 8] = bytes[82..90].try_into().expect("eight bytes were taken");
            (&bytes[186..], Some(u64::from_be_bytes(end)))
        }
        _ => return Err(not_an_invite()),
    };
    let kind = Kind::from_byte(bytes[81]).ok_or_else(not_an_invite)?;
    let name = std::str::from_utf8(name)
        .map(str::trim)
        .map_err(|_| not_an_invite())?;
    if name.is_empty() || too_long(name, MAX_NAME_CHARS) {
        return Err(not_an_invite());
    }
    Ok(Invite {
        id: bytes[1..17].try_into().expect("sixteen bytes were taken"),
        key: hexcode::encode(&bytes[17..49]),
        owner: hexcode::encode(&bytes[49..81]),
        kind,
        name: name.to_string(),
        expires,
    })
}

/// A clock that is this far ahead is not believed when ordering things.
const CLOCK_SLACK_MS: u64 = 5 * 60 * 1000;

fn invalid(what: &str) -> CoreError {
    CoreError::Invalid(what.to_string())
}

fn too_long(text: &str, limit: usize) -> bool {
    text.chars().count() > limit
}

fn derive<const N: usize>(key: &[u8; 32], info: &[&[u8]]) -> [u8; N] {
    let mut out = [0u8; N];
    Hkdf::<Sha256>::new(None, key)
        .expand_multi_info(info, &mut out)
        .expect("the output is far shorter than HKDF's limit");
    out
}

fn item_id(sealed: &[u8]) -> [u8; 16] {
    let digest = Sha256::digest(sealed);
    digest[..16]
        .try_into()
        .expect("a SHA-256 digest is 32 bytes")
}

/// A post as the rules look at it: when, by whom, in which channel, its
/// id, its words, and the roles the writer holds.
type RuledPost<'a> = (u64, &'a str, &'a str, &'a str, &'a str, &'a [String]);

fn signed_item(space: &[u8; 16], event: &[u8]) -> Vec<u8> {
    [ITEM_CONTEXT, space, event].concat()
}

fn signed_manifest(manifest: &[u8]) -> Vec<u8> {
    [MANIFEST_CONTEXT, manifest].concat()
}

/// The tag `from` shows `to` for one space. Only someone holding the
/// space's key can work it out, and it is different for every pair of
/// people, so it cannot be used to follow a space around.
fn tag(key: &[u8; 32], space: &[u8; 16], from: &[u8], to: &[u8]) -> String {
    hexcode::encode(&derive::<16>(key, &[TAG_CONTEXT, space, from, to]))
}

fn space_id(text: &str) -> Result<[u8; 16]> {
    hexcode::decode_exact::<16>(text).map_err(|_| invalid("that is not a space"))
}

fn default_channels(kind: Kind) -> Result<Vec<ChannelDef>> {
    let named: &[(&str, &str, &str)] = match kind {
        Kind::Channel => &[("feed", "text", "text")],
        // No voice room is made until voice exists.
        _ => &[
            ("announcements", "announcements", "info"),
            ("rules", "text", "info"),
            ("general", "text", "text"),
        ],
    };
    named
        .iter()
        .map(|(name, kind, group)| {
            Ok(ChannelDef {
                id: hexcode::encode(random_bytes::<8>()?.as_slice()),
                name: name.to_string(),
                kind: kind.to_string(),
                group: group.to_string(),
                slow: 0,
                no_links: false,
                since: 0,
                disappear: 0,
                max_len: 0,
                writers: Vec::new(),
            })
        })
        .collect()
}

/// Checks a signed manifest holds together and returns it.
fn read_manifest(manifest_hex: &str, signature_hex: &str) -> Option<Manifest> {
    let bytes = hexcode::decode(manifest_hex).ok()?;
    let signature = hexcode::decode(signature_hex).ok()?;
    if bytes.len() > MAX_ITEM_BYTES || signature.len() != SIGNATURE_LEN {
        return None;
    }
    let manifest: Manifest = serde_json::from_slice(&bytes).ok()?;
    let owner = hexcode::decode_exact::<SIGNING_LEN>(&manifest.owner).ok()?;
    verify_signature(&owner, &signed_manifest(&bytes), &signature).ok()?;
    space_id(&manifest.id).ok()?;
    // If the space has changed hands, every hand-over must be there and
    // hold, and the last must be to whoever signed this.
    if manifest.chain.is_empty() && !manifest.founder.is_empty() {
        return None;
    }
    let handed = read_chain(&manifest.id, manifest.founder(), &manifest.chain)?;
    if handed.last().is_some_and(|last| last.to != manifest.owner) {
        return None;
    }
    let name = manifest.name.trim();
    if name.is_empty()
        || too_long(name, MAX_NAME_CHARS)
        || too_long(&manifest.description, MAX_DESCRIPTION_CHARS)
        || too_long(&manifest.welcome, MAX_WELCOME_CHARS)
        || too_long(&manifest.rules, MAX_RULES_CHARS)
        || (!manifest.icon.is_empty() && hexcode::decode_exact::<32>(&manifest.icon).is_err())
    {
        return None;
    }
    if manifest.channels.is_empty() || manifest.channels.len() > MAX_CHANNELS {
        return None;
    }
    let sound = manifest.channels.iter().all(|c| {
        hexcode::decode_exact::<8>(&c.id).is_ok()
            && !c.name.trim().is_empty()
            && !too_long(&c.name, MAX_NAME_CHARS)
            && ["announcements", "text", "voice"].contains(&c.kind.as_str())
            && ["info", "text", "voice"].contains(&c.group.as_str())
            && c.slow <= 24 * 60 * 60
            && (c.disappear == 0 || DISAPPEAR_CHOICES.contains(&c.disappear))
            && (c.max_len == 0 || LENGTH_CHOICES.contains(&c.max_len))
    });
    let banned_sound = manifest.banned.len() <= MAX_BANNED
        && manifest
            .banned
            .iter()
            .all(|ban| !words_of(ban).is_empty() && !too_long(ban, MAX_BANNED_CHARS));
    let mut role_ids = HashSet::new();
    let roles_sound = manifest.roles.len() <= MAX_ROLES
        && manifest.roles.iter().all(|role| {
            hexcode::decode_exact::<8>(&role.id).is_ok()
                && role_ids.insert(role.id.as_str())
                && !role.name.trim().is_empty()
                && !too_long(&role.name, MAX_ROLE_NAME_CHARS)
                && role
                    .may
                    .iter()
                    .all(|power| ROLE_POWERS.contains(&power.as_str()))
        })
        && manifest.channels.iter().all(|c| {
            c.writers
                .iter()
                .all(|role| role_ids.contains(role.as_str()))
        });
    (sound && banned_sound && roles_sound).then_some(manifest)
}

impl Record {
    fn key(&self) -> Result<[u8; 32]> {
        hexcode::decode_exact::<32>(&self.key)
    }

    /// Every key the space has had, the one in use first.
    fn keys(&self) -> Result<Vec<[u8; 32]>> {
        std::iter::once(&self.key)
            .chain(&self.old_keys)
            .map(|key| hexcode::decode_exact::<32>(key))
            .collect()
    }

    fn manifest(&self) -> Option<Manifest> {
        if self.manifest.is_empty() {
            return None;
        }
        // Checked when it was stored.
        serde_json::from_slice(&hexcode::decode(&self.manifest).ok()?).ok()
    }

    fn announcement(&self) -> Announcement {
        Announcement {
            manifest: self.manifest.clone(),
            signature: self.signature.clone(),
            key: self.key.clone(),
        }
    }

    /// What each hand-over this device holds says. They were checked
    /// when they were taken.
    fn handed(&self) -> Vec<Handed> {
        self.chain
            .iter()
            .filter_map(|link| serde_json::from_slice(&hexcode::decode(&link.statement).ok()?).ok())
            .collect()
    }

    /// Who owns the space now: whoever it was last handed to, or else
    /// whoever made it.
    fn owner_now(&self) -> String {
        self.handed()
            .pop()
            .map_or_else(|| self.owner.clone(), |last| last.to)
    }

    /// Each owner in turn, the one who made the space first.
    fn terms(&self) -> Vec<Term> {
        let mut terms = vec![Term {
            owner: self.owner.clone(),
            from: 0,
            log: Vec::new(),
        }];
        for handed in self.handed() {
            if let Some(before) = terms.last_mut() {
                before.log = handed.log;
            }
            terms.push(Term {
                owner: handed.to,
                from: handed.at,
                log: Vec::new(),
            });
        }
        terms
    }
}

/// The two reactions the app has always had, by name.
const REACTIONS: [&str; 2] = ["heart", "agree"];
/// The most kinds of reaction shown on one message: the most given.
const MAX_REACTION_KINDS: usize = 20;

/// Whether a member may react with `kind`: one of [`REACTIONS`], or a
/// single emoji.
fn reaction_ok(kind: &str) -> bool {
    REACTIONS.contains(&kind) || one_emoji(kind)
}

/// Whether `text` is one emoji and nothing else: one picture character,
/// or several joined into one as a family or a flag is, with the marks
/// that colour or change it. Letters, words and spaces are not.
fn one_emoji(text: &str) -> bool {
    if text.is_empty() || text.len() > 32 {
        return false;
    }
    // A digit, # or * is an emoji only as a key: "1", a mark, a keycap.
    let keycap = text.ends_with('\u{20E3}');
    let mut pictures = 0;
    let mut after_join = false;
    let mut after_flag_half = false;
    for c in text.chars() {
        match c as u32 {
            // Joins the picture before to the one after.
            0x200D => {
                if pictures == 0 || after_join {
                    return false;
                }
                after_join = true;
            }
            // Marks that change the picture before them: shown as a
            // picture, a key, a skin tone, a flag's tags.
            0xFE0F | 0x20E3 | 0x1F3FB..=0x1F3FF | 0xE0020..=0xE007F => {
                if pictures == 0 {
                    return false;
                }
            }
            code => {
                let flag_half = (0x1F1E6..=0x1F1FF).contains(&code);
                let picture = match code {
                    0x23 | 0x2A | 0x30..=0x39 => keycap && pictures == 0,
                    0xA9 | 0xAE | 0x203C | 0x2049 | 0x2122 | 0x2139 => true,
                    0x2194..=0x21AA | 0x231A..=0x23FF | 0x24C2 => true,
                    0x25AA..=0x25FE | 0x2600..=0x27BF | 0x2934..=0x2935 => true,
                    0x2B05..=0x2B55 | 0x3030 | 0x303D | 0x3297 | 0x3299 => true,
                    0x1F000..=0x1FAFF => true,
                    _ => false,
                };
                // A second picture only joined to the first, or as the
                // second half of a flag.
                let joined = after_join || (flag_half && after_flag_half);
                if !picture || (pictures > 0 && !joined) {
                    return false;
                }
                after_flag_half = flag_half && !after_flag_half;
                after_join = false;
                pictures += 1;
            }
        }
    }
    pictures > 0 && !after_join
}

/// Whether `author` may write `event` in this space.
fn allowed(event: &Event, author: &str, record: &Record, manifest: &Manifest) -> bool {
    match event {
        Event::Member {
            name,
            identity,
            photo,
            ..
        } => {
            // A public channel keeps no list of who follows it.
            if record.kind == Kind::Channel
                || name.trim().is_empty()
                || too_long(name, MAX_NAME_CHARS)
                || (!photo.is_empty()
                    && (photo.len() > MAX_SPACE_PHOTO_BYTES * 2
                        || !crate::chat::sound_photo(photo)))
            {
                return false;
            }
            // The identity shown must be the one that signed.
            hexcode::decode(identity)
                .and_then(|bytes| PublicIdentity::from_bytes(&bytes))
                .is_ok_and(|shown| {
                    hexcode::encode(&shown.signing_key) == author && shown.verify().is_ok()
                })
        }
        Event::Left { .. } => true,
        Event::Post {
            id,
            channel,
            body,
            reply_to,
            options,
            name,
            mentions,
            lasts,
            file,
            roles,
            location,
            sticker,
            ..
        } => {
            if *lasts != 0 && !DISAPPEAR_CHOICES.contains(lasts) {
                return false;
            }
            // A sticker is posted on its own, with no words.
            if sticker.as_ref().is_some_and(|sticker| {
                !sticker.sound()
                    || !body.is_empty()
                    || !options.is_empty()
                    || file.is_some()
                    || location.is_some()
            }) {
                return false;
            }
            // A place is on the globe, and is posted on its own: not as a
            // poll, and not with a file.
            if location.is_some_and(|place| {
                place.checked().is_none() || !options.is_empty() || file.is_some()
            }) {
                return false;
            }
            // Whether whoever called on everyone could is judged when the
            // channel is read, as it depends on their roles at the time.
            if mentions.len() + roles.len() > MAX_MENTIONS
                || roles
                    .iter()
                    .any(|role| hexcode::decode_exact::<8>(role).is_err())
            {
                return false;
            }
            // A file needs no words with it; a poll carries no file.
            if file
                .as_ref()
                .is_some_and(|file| !file.sound() || !options.is_empty())
            {
                return false;
            }
            if hexcode::decode_exact::<16>(id).is_err()
                || (body.trim().is_empty() && file.is_none() && sticker.is_none())
                || too_long(body, MAX_BODY_CHARS)
                || mentions.len() > MAX_MENTIONS
                || mentions
                    .iter()
                    .any(|key| hexcode::decode_exact::<SIGNING_LEN>(key).is_err())
            {
                return false;
            }
            let a_poll = (2..=MAX_CHOICES).contains(&options.len())
                && options
                    .iter()
                    .all(|choice| !choice.trim().is_empty() && !too_long(choice, MAX_CHOICE_CHARS));
            if (!options.is_empty() && !a_poll) || too_long(name, MAX_NAME_CHARS) {
                return false;
            }
            if reply_to
                .as_ref()
                .is_some_and(|target| hexcode::decode_exact::<16>(target).is_err())
            {
                return false;
            }
            if hexcode::decode_exact::<8>(channel).is_err() {
                return false;
            }
            // In a public channel anyone may answer a post, but only the
            // owner starts one. Who may write in a space's info channels
            // depends on who was an admin when, which is judged when the
            // channel is read: see `Standing`. So is whether the channel
            // still exists.
            let owners_only = record.kind == Kind::Channel && reply_to.is_none();
            !owners_only || author == record.owner
        }
        Event::React { target, kind, .. } => {
            hexcode::decode_exact::<16>(target).is_ok() && reaction_ok(kind)
        }
        // Whether whoever pinned it was running the space is judged when
        // the channel is read.
        Event::Pin { target, .. } | Event::Delete { target, .. } => {
            hexcode::decode_exact::<16>(target).is_ok()
        }
        // Whether it was the writer, and what the channel's rules said at
        // the time, is judged when the channel is read.
        Event::Edit { target, body, .. } => {
            hexcode::decode_exact::<16>(target).is_ok()
                && !body.trim().is_empty()
                && !too_long(body, MAX_BODY_CHARS)
        }
        Event::Manifest {
            manifest: bytes,
            signature,
            ..
        } => {
            // Signed by whoever it names as owner, for the space this
            // device knows, made by who this device was told made it. If
            // the space has changed hands, its hand-overs must be the ones
            // this device holds, or carry on from them, or stop short of
            // them: never a different story.
            read_manifest(bytes, signature).is_some_and(|new| {
                new.id == manifest.id
                    && new.owner == author
                    && new.kind == record.kind
                    && new.founder() == record.owner
                    && (extends(&new.chain, &record.chain) || extends(&record.chain, &new.chain))
            })
        }
        Event::Closed { .. } => author == record.owner_now(),
        // The next hand-over, signed by whoever owns the space now, or
        // one this device already holds. A public channel, where only the
        // owner posts, cannot be handed over.
        Event::Handover {
            statement,
            signature,
            ..
        } => {
            let link = Handover {
                statement: statement.clone(),
                signature: signature.clone(),
            };
            record.kind != Kind::Channel
                && (record.chain.contains(&link) || {
                    let mut longer = record.chain.clone();
                    longer.push(link);
                    read_chain(&manifest.id, &record.owner, &longer)
                        .is_some_and(|said| said.last().is_some_and(|last| last.from == author))
                })
        }
        // Whether whoever sent it was running the space is judged when
        // the space is read. Nobody times the owner out.
        Event::Timeout { member, .. } => {
            member != &record.owner_now() && hexcode::decode_exact::<SIGNING_LEN>(member).is_ok()
        }
        // The same for muting in voice rooms. A public channel has none.
        Event::Voice { member, .. } => {
            record.kind != Kind::Channel
                && member != &record.owner_now()
                && hexcode::decode_exact::<SIGNING_LEN>(member).is_ok()
        }
        Event::Role { member, .. } | Event::Remove { member, .. } => {
            let owner = record.owner_now();
            author == owner
                && member != &owner
                && hexcode::decode_exact::<SIGNING_LEN>(member).is_ok()
        }
        Event::Grant { member, role, .. } => {
            let owner = record.owner_now();
            author == owner
                && member != &owner
                && hexcode::decode_exact::<SIGNING_LEN>(member).is_ok()
                && hexcode::decode_exact::<8>(role).is_ok()
        }
        Event::Vote { target, choice, .. } => {
            hexcode::decode_exact::<16>(target).is_ok() && (*choice as usize) < MAX_CHOICES
        }
        // Whether whoever sent it was running the space, and may rename
        // this member, is judged when the space is read. Nobody renames
        // the owner, and a public channel lists nobody to rename.
        Event::Nick { member, name, .. } => {
            record.kind != Kind::Channel
                && member != &record.owner_now()
                && hexcode::decode_exact::<SIGNING_LEN>(member).is_ok()
                && !too_long(name, MAX_NAME_CHARS)
        }
    }
}

/// Who runs a space and who has been put out of it, worked out from what
/// its owner signed. It is worked out afresh each time a space is read,
/// from everything this device holds, so the order things arrived in does
/// not matter.
struct Standing<'a> {
    /// Who owns the space now.
    owner: String,
    /// Each owner in turn and when the space became theirs, the one who
    /// made it first.
    owners: Vec<(String, u64)>,
    /// For each member, when they were made an admin or stopped being
    /// one, oldest first.
    roles: BTreeMap<String, Vec<(u64, bool)>>,
    /// For each person now removed, when.
    removed: BTreeMap<String, u64>,
    /// Messages taken down by someone allowed to.
    deleted: HashSet<&'a str>,
    /// The channels only the owner and admins write in.
    info: HashSet<&'a str>,
    /// Messages that break their channel's rules: a link where links are
    /// not allowed, or one sent too soon in slow mode.
    ruled_out: HashSet<&'a str>,
    /// For each member told to keep quiet: from when, and until when.
    timeouts: BTreeMap<&'a str, (u64, u64)>,
    /// For each member and role, when the owner gave it or took it back,
    /// oldest first.
    grants: BTreeMap<(String, String), Vec<(u64, bool)>>,
    /// What each of the space's roles may do.
    powers: BTreeMap<&'a str, Vec<&'a str>>,
    /// The channels kept for some roles to write in, and which.
    writers: BTreeMap<&'a str, &'a [String]>,
    /// What whoever runs the space has set members to be called, by key.
    nicks: BTreeMap<String, String>,
    /// For each member muted or deafened in the voice rooms: the latest
    /// word on them, and whether muted and whether deafened.
    voice: BTreeMap<&'a str, (u64, bool, bool)>,
}

impl<'a> Standing<'a> {
    fn of(items: &'a [Item], record: &'a Record, manifest: &'a Manifest) -> Self {
        let terms = record.terms();
        let owner = terms
            .last()
            .map_or_else(|| record.owner.clone(), |term| term.owner.clone());
        let mut roles: BTreeMap<String, Vec<(u64, bool)>> = BTreeMap::new();
        let mut removals: BTreeMap<String, (u64, bool)> = BTreeMap::new();
        let mut grants: BTreeMap<(String, String), Vec<(u64, bool)>> = BTreeMap::new();
        let mut decided = |event: &Event| match event {
            Event::Grant {
                member,
                role,
                on,
                sent_at,
            } => grants
                .entry((member.clone(), role.clone()))
                .or_default()
                .push((*sent_at, *on)),
            Event::Role {
                member,
                admin,
                sent_at,
            } => roles
                .entry(member.clone())
                .or_default()
                .push((*sent_at, *admin)),
            Event::Remove {
                member,
                on,
                sent_at,
            } => {
                let latest = removals.entry(member.clone()).or_insert((0, false));
                if *sent_at >= latest.0 {
                    *latest = (*sent_at, *on);
                }
            }
            _ => {}
        };
        // What each owner decided while the space was theirs. For one who
        // has handed it on, that is what their hand-over lists and nothing
        // else, so nothing they sign afterwards counts. For the owner
        // now, it is what they have written into the space.
        for term in terms.iter().rev().skip(1) {
            term.log.iter().for_each(&mut decided);
        }
        for item in items.iter().filter(|item| item.author == owner) {
            decided(&item.event);
        }
        let owners = terms
            .into_iter()
            .map(|term| (term.owner, term.from))
            .collect();
        for changes in roles.values_mut() {
            changes.sort();
        }
        for changes in grants.values_mut() {
            changes.sort();
        }
        let removed = removals
            .into_iter()
            .filter(|(_, (_, on))| *on)
            .map(|(member, (at, _))| (member, at))
            .collect();
        let info = manifest
            .channels
            .iter()
            .filter(|c| c.group == "info")
            .map(|c| c.id.as_str())
            .collect();
        let mut standing = Standing {
            owner,
            owners,
            roles,
            removed,
            deleted: HashSet::new(),
            info,
            ruled_out: HashSet::new(),
            timeouts: BTreeMap::new(),
            grants,
            powers: manifest
                .roles
                .iter()
                .map(|role| {
                    (
                        role.id.as_str(),
                        role.may.iter().map(String::as_str).collect(),
                    )
                })
                .collect(),
            writers: manifest
                .channels
                .iter()
                .filter(|c| !c.writers.is_empty())
                .map(|c| (c.id.as_str(), c.writers.as_slice()))
                .collect(),
            nicks: BTreeMap::new(),
            voice: BTreeMap::new(),
        };
        // What each member is called, as the latest word of someone
        // running the space then. Nobody renames whoever owned the space
        // at the time, and an admin does not rename another admin.
        let mut nicks: BTreeMap<&str, (u64, &str)> = BTreeMap::new();
        for item in items {
            let Event::Nick {
                member,
                name,
                sent_at,
            } = &item.event
            else {
                continue;
            };
            let owner = standing.owner_at(*sent_at);
            if !standing.runs_at(&item.author, *sent_at)
                || owner == member
                || (item.author != owner && standing.runs_at(member, *sent_at))
            {
                continue;
            }
            let latest = nicks.entry(member).or_insert((0, ""));
            if *sent_at >= latest.0 {
                *latest = (*sent_at, name);
            }
        }
        standing.nicks = nicks
            .into_iter()
            .filter(|(_, (_, name))| !name.trim().is_empty())
            .map(|(member, (_, name))| (member.to_string(), name.trim().to_string()))
            .collect();
        // The latest word on each member, from someone running the space
        // when they said it.
        for item in items {
            let Event::Timeout {
                member,
                until,
                sent_at,
            } = &item.event
            else {
                continue;
            };
            // Nobody times out whoever owned the space at the time, and a
            // role does not reach the owner's admins.
            if !standing.may_at(&item.author, "timeout", *sent_at)
                || standing.owner_at(*sent_at) == member
                || (!standing.runs_at(&item.author, *sent_at) && standing.runs_at(member, *sent_at))
            {
                continue;
            }
            let latest = standing.timeouts.entry(member).or_insert((0, 0));
            if *sent_at >= latest.0 {
                *latest = (*sent_at, *until);
            }
        }
        // Who is muted or deafened in the voice rooms: the latest word of
        // the owner or an admin, as for timeouts. An admin does not reach
        // another admin.
        for item in items {
            let Event::Voice {
                member,
                mute,
                deafen,
                sent_at,
            } = &item.event
            else {
                continue;
            };
            if !standing.runs_at(&item.author, *sent_at)
                || standing.owner_at(*sent_at) == member
                || (item.author != standing.owner_at(*sent_at)
                    && standing.runs_at(member, *sent_at))
            {
                continue;
            }
            let latest = standing.voice.entry(member).or_insert((0, false, false));
            if *sent_at >= latest.0 {
                *latest = (*sent_at, *mute, *deafen);
            }
        }

        let writers: BTreeMap<&str, &str> = items
            .iter()
            .filter_map(|item| match &item.event {
                Event::Post { id, .. } => Some((id.as_str(), item.author.as_str())),
                _ => None,
            })
            .collect();
        for item in items {
            let Event::Delete { target, sent_at } = &item.event else {
                continue;
            };
            let Some(writer) = writers.get(target.as_str()) else {
                continue;
            };
            if *writer == item.author || standing.may_at(&item.author, "delete", *sent_at) {
                standing.deleted.insert(target);
            }
        }

        // The owner's rules for each channel. A member's own app refuses
        // to send what breaks them. This is every other device refusing
        // to show it, should a changed app send it anyway.
        let ruled: BTreeMap<&str, &ChannelDef> = manifest
            .channels
            .iter()
            .filter(|c| c.slow > 0 || c.no_links || c.max_len > 0)
            .map(|c| (c.id.as_str(), c))
            .collect();
        if !ruled.is_empty() || !manifest.banned.is_empty() {
            let mut posts: Vec<RuledPost<'_>> = items
                .iter()
                .filter_map(|item| match &item.event {
                    Event::Post {
                        id,
                        channel,
                        body,
                        sent_at,
                        options,
                        ..
                    } => Some((
                        *sent_at,
                        id.as_str(),
                        channel.as_str(),
                        item.author.as_str(),
                        body.as_str(),
                        options.as_slice(),
                    )),
                    _ => None,
                })
                .collect();
            posts.sort();
            let mut last: BTreeMap<(&str, &str), u64> = BTreeMap::new();
            for (at, id, channel, author, body, options) in posts {
                if standing.runs_at(author, at)
                    || standing.deleted.contains(id)
                    || standing.removed_by(author, at)
                {
                    continue;
                }
                if !manifest.words_off
                    && at >= manifest.banned_since
                    && has_banned(body, &manifest.banned)
                {
                    standing.ruled_out.insert(id);
                    continue;
                }
                let Some(rule) = ruled.get(channel).filter(|rule| at >= rule.since) else {
                    continue;
                };
                if rule.max_len > 0 && body.chars().count() > rule.max_len as usize {
                    standing.ruled_out.insert(id);
                    continue;
                }
                let too_soon = rule.slow > 0
                    && last
                        .get(&(channel, author))
                        .is_some_and(|before| at < before + rule.slow as u64 * 1000);
                if too_soon || (rule.no_links && post_has_link(body, options)) {
                    standing.ruled_out.insert(id);
                } else {
                    last.insert((channel, author), at);
                }
            }
        }

        // Spam: the same words over and over, or a flood. A member's own
        // app refuses to send it; every other device refuses to show it,
        // should a changed app send it anyway. The owner and admins are
        // not held to it.
        let mut posts: Vec<(u64, &str, &str, &str, String)> = items
            .iter()
            .filter_map(|item| match &item.event {
                Event::Post {
                    id,
                    channel,
                    body,
                    sent_at,
                    file,
                    sticker,
                    ..
                } => Some((
                    *sent_at,
                    id.as_str(),
                    channel.as_str(),
                    item.author.as_str(),
                    post_words(body, file.as_deref(), sticker.as_ref()),
                )),
                _ => None,
            })
            .collect();
        posts.sort();
        let mut earlier: BTreeMap<&str, Vec<(u64, &str, String)>> = BTreeMap::new();
        for (at, id, channel, author, words) in posts {
            if standing.runs_at(author, at)
                || standing.deleted.contains(id)
                || standing.ruled_out.contains(id)
                || standing.removed_by(author, at)
            {
                continue;
            }
            let theirs = earlier.entry(author).or_default();
            if spam_of(theirs, at, channel, &words).is_some() {
                standing.ruled_out.insert(id);
            } else {
                theirs.push((at, channel, words));
            }
        }
        standing
    }

    /// Whether `who` had been removed by the time `at`.
    fn removed_by(&self, who: &str, at: u64) -> bool {
        self.removed.get(who).is_some_and(|since| at >= *since)
    }

    /// If `who` had been told to keep quiet at the time `at`, when that
    /// ends.
    fn quiet_until(&self, who: &str, at: u64) -> Option<u64> {
        self.timeouts
            .get(who)
            .filter(|(from, until)| at >= *from && at < *until)
            .map(|(_, until)| *until)
    }

    /// Who owned the space at the time `at`.
    fn owner_at(&self, at: u64) -> &str {
        self.owners
            .iter()
            .rev()
            .find(|(_, from)| *from <= at)
            .or(self.owners.first())
            .map_or(self.owner.as_str(), |(owner, _)| owner)
    }

    /// Whether `who` was the owner or an admin at the time `at`.
    fn runs_at(&self, who: &str, at: u64) -> bool {
        if who == self.owner_at(at) {
            return true;
        }
        let admin = self
            .roles
            .get(who)
            .and_then(|changes| changes.iter().rev().find(|(since, _)| *since <= at));
        admin.is_some_and(|(_, admin)| *admin) && !self.removed_by(who, at)
    }

    fn runs(&self, who: &str) -> bool {
        self.runs_at(who, u64::MAX)
    }

    /// Whether `who` held `role` at the time `at`.
    fn holds_at(&self, who: &str, role: &str, at: u64) -> bool {
        !self.removed_by(who, at)
            && self
                .grants
                .get(&(who.to_string(), role.to_string()))
                .and_then(|changes| changes.iter().rev().find(|(since, _)| *since <= at))
                .is_some_and(|(_, on)| *on)
    }

    /// Whether `who` could do `power` at the time `at`: the owner and
    /// admins can do all of them, and a role can allow some.
    fn may_at(&self, who: &str, power: &str, at: u64) -> bool {
        self.runs_at(who, at)
            || self
                .powers
                .iter()
                .any(|(role, may)| may.contains(&power) && self.holds_at(who, role, at))
    }

    fn may(&self, who: &str, power: &str) -> bool {
        self.may_at(who, power, u64::MAX)
    }

    /// The roles `who` holds now, in the order the space lists them.
    fn roles_of(&self, who: &str) -> Vec<&'a str> {
        self.powers
            .keys()
            .copied()
            .filter(|role| self.holds_at(who, role, u64::MAX))
            .collect()
    }

    /// Whether `who` could write in `channel` at the time `at`, as far as
    /// the roles it is kept for go.
    fn writes_in(&self, who: &str, channel: &str, at: u64) -> bool {
        match self.writers.get(channel) {
            None => true,
            Some(roles) => {
                self.runs_at(who, at) || roles.iter().any(|role| self.holds_at(who, role, at))
            }
        }
    }

    /// Whether `event`, a post `author` wrote, calls on `who`: by name, as
    /// one of everyone when its writer could call on everyone then, or
    /// through a role `who` held when it was written. Nobody is called by
    /// their own post.
    fn calls(&self, who: &str, author: &str, event: &Event) -> bool {
        let Event::Post {
            mentions,
            everyone,
            roles,
            sent_at,
            ..
        } = event
        else {
            return false;
        };
        who != author
            && (mentions.iter().any(|key| key == who)
                || (*everyone && self.may_at(author, "mention_everyone", *sent_at))
                || roles.iter().any(|role| {
                    self.powers.contains_key(role.as_str()) && self.holds_at(who, role, *sent_at)
                }))
    }

    fn role(&self, who: &str) -> &'static str {
        match who {
            _ if who == self.owner => "owner",
            _ if self.runs(who) => "admin",
            _ => "member",
        }
    }

    /// Whether a post is to be shown: not taken down, not written by
    /// someone after they were removed, and, in an info channel, written
    /// by someone who was running the space at the time.
    fn shows(&self, id: &str, author: &str, channel: &str, sent_at: u64) -> bool {
        !self.deleted.contains(id)
            && !self.ruled_out.contains(id)
            && self.quiet_until(author, sent_at).is_none()
            && !self.removed_by(author, sent_at)
            && (!self.info.contains(channel) || self.may_at(author, "announce", sent_at))
            && self.writes_in(author, channel, sent_at)
    }

    /// The people in the space now: everyone who said they joined, less
    /// anyone removed.
    fn present(&self, items: &[Item]) -> BTreeMap<String, Membership> {
        let mut members = Spaces::members(items);
        members.retain(|key, _| !self.removed.contains_key(key));
        self.renamed(members)
    }

    /// Members as whoever runs the space has named them.
    fn renamed(&self, mut members: BTreeMap<String, Membership>) -> BTreeMap<String, Membership> {
        for (key, (name, _)) in members.iter_mut() {
            if let Some(nick) = self.nicks.get(key) {
                name.clone_from(nick);
            }
        }
        members
    }
}

/// A post as the app is shown it, and where it belongs.
struct Shown {
    channel: String,
    /// The post this answers, if any.
    answers: Option<String>,
    /// When the owner pinned it, if it is pinned now.
    pinned_at: Option<u64>,
    sent_at: u64,
    view: Value,
}

fn by_time(a: &Shown, b: &Shown) -> std::cmp::Ordering {
    (a.sent_at, a.view["id"].as_str()).cmp(&(b.sent_at, b.view["id"].as_str()))
}

impl Spaces<'_> {
    fn my_key(&self) -> String {
        hexcode::encode(&self.me.signing_public())
    }

    fn load(&self, id: &[u8; 16]) -> Result<Option<Record>> {
        match self.vault.get(SPACE, id)? {
            None => Ok(None),
            Some(bytes) => serde_json::from_slice(&bytes)
                .map(Some)
                .map_err(|_| CoreError::Corrupt("a saved space is unreadable".into())),
        }
    }

    fn save(&self, id: &[u8; 16], record: &Record) -> Result<()> {
        self.vault.put(
            SPACE,
            id,
            &serde_json::to_vec(record).expect("a space record is plain data"),
        )
    }

    fn all(&self) -> Result<Vec<([u8; 16], Record)>> {
        let mut spaces = Vec::new();
        for (id, bytes) in self.vault.list(SPACE)? {
            let id: [u8; 16] = id
                .try_into()
                .map_err(|_| CoreError::Corrupt("a saved space is misfiled".into()))?;
            let record = serde_json::from_slice(&bytes)
                .map_err(|_| CoreError::Corrupt("a saved space is unreadable".into()))?;
            spaces.push((id, record));
        }
        Ok(spaces)
    }

    fn joined(&self, id: &str) -> Result<([u8; 16], Record)> {
        let id = space_id(id)?;
        match self.load(&id)? {
            Some(record) if record.status == Status::Joined => Ok((id, record)),
            _ => Err(invalid("you are not in that space")),
        }
    }

    // Items

    fn seal_item(&self, id: &[u8; 16], key: &[u8; 32], event: &Event) -> Result<Vec<u8>> {
        let event = serde_json::to_vec(event).expect("an event is plain data");
        let mut inner = self.me.signing_public().to_vec();
        inner.extend_from_slice(&self.me.sign(&signed_item(id, &event)));
        inner.extend_from_slice(&event);
        seal::seal(&derive::<32>(key, &[ITEM_KEY_CONTEXT]), id, &inner)
    }

    /// Opens an item and checks who signed it. None if it was not sealed
    /// with this space's key or the signature does not hold.
    fn open_item(id: &[u8; 16], key: &[u8; 32], sealed: &[u8]) -> Option<(String, Event)> {
        let inner = seal::open(&derive::<32>(key, &[ITEM_KEY_CONTEXT]), id, sealed).ok()?;
        if inner.len() < SIGNING_LEN + SIGNATURE_LEN {
            return None;
        }
        let (author, rest) = inner.split_at(SIGNING_LEN);
        let (signature, event) = rest.split_at(SIGNATURE_LEN);
        verify_signature(author, &signed_item(id, event), signature).ok()?;
        Some((hexcode::encode(author), serde_json::from_slice(event).ok()?))
    }

    fn stored(&self, id: &[u8; 16]) -> Result<Vec<Stored>> {
        let mut items = Vec::new();
        for (key, value) in self.vault.list_prefix(ITEM, id)? {
            let (Some(item), Some(arrival)) = (key.get(16..32), value.get(..8)) else {
                return Err(CoreError::Corrupt("a saved space item is misfiled".into()));
            };
            items.push((
                item.try_into().expect("sixteen bytes were taken"),
                u64::from_be_bytes(arrival.try_into().expect("eight bytes were taken")),
                value[8..].to_vec(),
            ));
        }
        Ok(items)
    }

    /// Opens an item with whichever of the space's keys it was sealed
    /// under.
    fn open_any(id: &[u8; 16], keys: &[[u8; 32]], sealed: &[u8]) -> Option<(String, Event)> {
        keys.iter().find_map(|key| Self::open_item(id, key, sealed))
    }

    /// Everything this device holds of a space, opened. What has run out
    /// of time is deleted from the device first, never shown or passed
    /// on.
    fn items(&self, id: &[u8; 16], record: &Record) -> Result<Vec<Item>> {
        let keys = record.keys()?;
        let manifest = record.manifest();
        let now = now();
        let mut gone = Vec::new();
        let items = self
            .stored(id)?
            .into_iter()
            .filter_map(|(item, arrival, sealed)| {
                let (author, event) = Self::open_any(id, &keys, &sealed)?;
                if ends_at(&event, manifest.as_ref()).is_some_and(|end| end <= now) {
                    gone.push(item);
                    return None;
                }
                Some(Item {
                    arrival,
                    author,
                    event,
                })
            })
            .collect();
        if !gone.is_empty() {
            self.vault.batch(|tx| {
                for item in &gone {
                    tx.delete(ITEM, &[id.as_slice(), item.as_slice()].concat())?;
                }
                Ok(())
            })?;
        }
        Ok(items)
    }

    fn shelf(&self) -> Shelf<'_> {
        Shelf {
            vault: self.vault,
            dir: self.files,
        }
    }

    /// What a post's file is, and how much of it this device has.
    fn file_view(&self, file: &Attached) -> Value {
        let kept = self.shelf().get(&file.sha256).ok().flatten();
        let held = kept.as_ref().is_some_and(|k| k.done);
        json!({
            "sha256": file.sha256,
            "name": file.name,
            "size": file.size,
            "kind": file.kind,
            "seconds": file.seconds,
            "pieces": shelf::pieces_of(file.size),
            "have": kept.as_ref().map_or(0, |k| k.have),
            "held": held,
            "wanted": kept.as_ref().is_some_and(|k| k.wanted),
            "path": held.then(|| self.shelf().path(&file.sha256).display().to_string()),
        })
    }

    /// Forgets a space and everything said in it, and the files its posts
    /// carried that no other space needs.
    fn forget(&self, id: &[u8; 16]) -> Result<()> {
        self.shelf().sweep(&hexcode::encode(id), &HashSet::new())?;
        self.vault.batch(|tx| {
            for (item, _, _) in self.stored(id)? {
                tx.delete(ITEM, &[id.as_slice(), item.as_slice()].concat())?;
            }
            tx.delete(ICON, id)?;
            tx.delete(SPACE, id)
        })
    }

    /// The icon this device holds for a space, if it is the one the
    /// owner's latest word names.
    fn icon_of(&self, id: &[u8; 16], record: &Record) -> Result<Option<Vec<u8>>> {
        let Some(named) = record.manifest().map(|m| m.icon).filter(|i| !i.is_empty()) else {
            return Ok(None);
        };
        Ok(self
            .vault
            .get(ICON, id)?
            .filter(|bytes| hexcode::encode(&Sha256::digest(bytes)) == named))
    }

    /// The fingerprint of a space's icon, if the owner has set one and this
    /// device does not have it yet.
    fn lacks_icon(&self, id: &[u8; 16], record: &Record) -> Result<Option<String>> {
        let Some(named) = record.manifest().map(|m| m.icon).filter(|i| !i.is_empty()) else {
            return Ok(None);
        };
        if record.closed || self.icon_of(id, record)?.is_some() {
            return Ok(None);
        }
        Ok(Some(named))
    }

    /// Stores an item if it is new, opens with this space's key, is
    /// properly signed and is something its writer may write. Returns
    /// whether it was stored. The caller saves `record`.
    fn take(
        &self,
        id: &[u8; 16],
        record: &mut Record,
        manifest: &Manifest,
        sealed: &[u8],
    ) -> Result<bool> {
        if sealed.len() > MAX_ITEM_BYTES {
            return Ok(false);
        }
        // A deleted space takes nothing more in, but for one thing.
        if record.closed {
            return self.reopen(id, record, sealed);
        }
        let mut place = id.to_vec();
        place.extend_from_slice(&item_id(sealed));
        if self.vault.get(ITEM, &place)?.is_some() {
            return Ok(false);
        }
        let Some((author, event)) = Self::open_any(id, &record.keys()?, sealed) else {
            return Ok(false);
        };
        // The manifest may have changed earlier in the same batch.
        let current = record.manifest();
        let manifest = current.as_ref().unwrap_or(manifest);
        if !allowed(&event, &author, record, manifest) {
            return Ok(false);
        }
        if ends_at(&event, Some(manifest)).is_some_and(|end| end <= now()) {
            return Ok(false);
        }
        if event.sent_at() <= now() + CLOCK_SLACK_MS {
            record.clock = record.clock.max(event.sent_at());
        }
        let mut value = record.next_arrival.to_be_bytes().to_vec();
        value.extend_from_slice(sealed);
        self.vault.put(ITEM, &place, &value)?;
        record.next_arrival += 1;
        // The owner deleting the space: everything said in it goes from
        // this device. The owner's word of it stays, to pass on.
        if matches!(event, Event::Closed { .. }) {
            record.closed = true;
            self.vault.batch(|tx| {
                for (item, _, _) in self.stored(id)? {
                    if item != item_id(sealed) {
                        tx.delete(ITEM, &[id.as_slice(), item.as_slice()].concat())?;
                    }
                }
                Ok(())
            })?;
        }
        // The owner's newest word on what the space is replaces the last.
        if let Event::Manifest {
            manifest: bytes,
            signature,
            ..
        } = &event
        {
            // One from a later owner outranks any from an earlier one.
            // Among one owner's, the highest version does.
            if let Some(new) = read_manifest(bytes, signature).filter(|new| {
                new.chain.len() >= record.chain.len()
                    && (new.chain.len(), new.version) > (manifest.chain.len(), manifest.version)
            }) {
                record.manifest = bytes.clone();
                record.signature = signature.clone();
                record.name = new.name.trim().to_string();
                record.description = new.description.trim().to_string();
                record.chain = new.chain;
            }
        }
        // A hand-over is taken as true from here on.
        if let Event::Handover {
            statement,
            signature,
            ..
        } = event
        {
            let link = Handover {
                statement,
                signature,
            };
            if !record.chain.contains(&link) {
                record.chain.push(link);
            }
        }
        Ok(true)
    }

    /// The one thing a deleted space takes in: proof that whoever deleted
    /// it had already handed it to someone else, and so no longer could.
    ///
    /// A device that had not yet heard of the hand-over will have believed
    /// them. Given the proof it puts the space back, empty, to be filled
    /// again by the members it meets.
    fn reopen(&self, id: &[u8; 16], record: &mut Record, sealed: &[u8]) -> Result<bool> {
        let keys = record.keys()?;
        let Some((
            author,
            Event::Handover {
                statement,
                signature,
                ..
            },
        )) = Self::open_any(id, &keys, sealed)
        else {
            return Ok(false);
        };
        let link = Handover {
            statement,
            signature,
        };
        let mut longer = record.chain.clone();
        longer.push(link.clone());
        let proves = read_chain(&hexcode::encode(id), &record.owner, &longer)
            .is_some_and(|said| said.last().is_some_and(|last| last.from == author));
        if !proves {
            return Ok(false);
        }
        // Only if the word of deletion this device holds is theirs.
        let stored = self.stored(id)?;
        let deleted_by =
            stored
                .iter()
                .find_map(|(_, _, bytes)| match Self::open_any(id, &keys, bytes) {
                    Some((who, Event::Closed { .. })) => Some(who),
                    _ => None,
                });
        if deleted_by.as_deref() != Some(author.as_str()) {
            return Ok(false);
        }
        self.vault.batch(|tx| {
            for (item, _, _) in &stored {
                tx.delete(ITEM, &[id.as_slice(), item.as_slice()].concat())?;
            }
            Ok(())
        })?;
        let mut place = id.to_vec();
        place.extend_from_slice(&item_id(sealed));
        let mut value = record.next_arrival.to_be_bytes().to_vec();
        value.extend_from_slice(sealed);
        self.vault.put(ITEM, &place, &value)?;
        record.next_arrival += 1;
        record.closed = false;
        record.chain.push(link);
        Ok(true)
    }

    /// Writes something of the user's own into a space. Returns the sealed
    /// item, to pass to members in range.
    fn write(&self, id: &[u8; 16], record: &mut Record, event: &Event) -> Result<Vec<u8>> {
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        if !allowed(event, &self.my_key(), record, &manifest) {
            return Err(invalid("that cannot be written here"));
        }
        let sealed = self.seal_item(id, &record.key()?, event)?;
        self.take(id, record, &manifest, &sealed)?;
        self.save(id, record)?;
        Ok(sealed)
    }

    /// The time to put on something the user writes now: later than
    /// anything already seen in the space, and never the same twice.
    fn stamp(record: &mut Record) -> u64 {
        record.clock = now().max(record.clock + 1);
        record.clock
    }

    /// What the user goes by in a space: the name they chose for it, or
    /// else their usual one.
    fn name_in(&self, record: &Record) -> String {
        record
            .nick
            .clone()
            .unwrap_or_else(|| self.my_name.trim().to_string())
    }

    fn member_event(&self, record: &mut Record) -> Event {
        Event::Member {
            name: self.name_in(record),
            identity: hexcode::encode(&self.me.public().to_bytes()),
            sent_at: Self::stamp(record),
            // Too big to go in one item, and it is left out.
            photo: self
                .my_photo
                .filter(|photo| photo.len() <= MAX_SPACE_PHOTO_BYTES * 2)
                .unwrap_or_default()
                .to_string(),
        }
    }

    /// Each member's profile photo, hex, from what they last said.
    fn member_photos(items: &[Item]) -> BTreeMap<&str, &str> {
        let mut latest: BTreeMap<&str, (u64, &str)> = BTreeMap::new();
        for item in items {
            if let Event::Member { sent_at, photo, .. } = &item.event {
                let known = latest.entry(item.author.as_str()).or_insert((0, ""));
                if *sent_at >= known.0 {
                    *known = (*sent_at, photo.as_str());
                }
            }
        }
        latest
            .into_iter()
            .filter(|(_, (_, photo))| !photo.is_empty())
            .map(|(key, (_, photo))| (key, photo))
            .collect()
    }

    /// Tells every space the user is in what they look like now, after
    /// their photo changed or they chose whether to show it.
    pub fn show_photo_again(&self) -> Result<Vec<(String, Vec<u8>)>> {
        let me = self.my_key();
        let mut said = Vec::new();
        for (id, mut record) in self.all()? {
            if record.status != Status::Joined
                || record.kind == Kind::Channel
                || record.manifest.is_empty()
            {
                continue;
            }
            if !Self::members(&self.items(&id, &record)?).contains_key(&me) {
                continue;
            }
            let event = self.member_event(&mut record);
            said.push((hexcode::encode(&id), self.write(&id, &mut record, &event)?));
        }
        Ok(said)
    }

    /// Who is in a space: each person's latest word on it, by key.
    fn members(items: &[Item]) -> BTreeMap<String, Membership> {
        let mut latest: BTreeMap<&str, (u64, Option<Membership>)> = BTreeMap::new();
        for item in items {
            let (at, state) = match &item.event {
                Event::Member {
                    name,
                    identity,
                    sent_at,
                    ..
                } => (*sent_at, Some((name.trim().to_string(), identity.clone()))),
                Event::Left { sent_at } => (*sent_at, None),
                _ => continue,
            };
            match latest.get(item.author.as_str()) {
                // Older news. And leaving wins a tie, so "joined and left
                // in the same second" ends as left.
                Some((known, was)) if *known > at || (*known == at && was.is_none()) => {}
                _ => {
                    latest.insert(item.author.as_str(), (at, state));
                }
            }
        }
        latest
            .into_iter()
            .filter_map(|(key, (_, state))| state.map(|s| (key.to_string(), s)))
            .collect()
    }

    // What the app asks for

    pub fn create(&self, name: &str, kind: &str, description: &str) -> Result<Value> {
        let kind: Kind = serde_json::from_value(json!(kind))
            .map_err(|_| invalid("there is no such kind of space"))?;
        let (name, description) = (name.trim(), description.trim());
        if name.is_empty() || too_long(name, MAX_NAME_CHARS) {
            return Err(invalid(
                "a space's name must be between 1 and 64 characters",
            ));
        }
        if too_long(description, MAX_DESCRIPTION_CHARS) {
            return Err(invalid("the description is too long"));
        }
        let id = *random_bytes::<16>()?;
        let manifest = Manifest {
            id: hexcode::encode(&id),
            name: name.to_string(),
            kind,
            description: description.to_string(),
            owner: self.my_key(),
            channels: default_channels(kind)?,
            version: 0,
            chain: Vec::new(),
            founder: String::new(),
            banned: Vec::new(),
            banned_since: 0,
            words_off: false,
            welcome: String::new(),
            rules: String::new(),
            roles: Vec::new(),
            icon: String::new(),
        };
        let bytes = serde_json::to_vec(&manifest).expect("a manifest is plain data");
        let mut record = Record {
            key: hexcode::encode(random_bytes::<32>()?.as_slice()),
            owner: self.my_key(),
            status: Status::Joined,
            name: manifest.name.clone(),
            kind,
            description: manifest.description.clone(),
            manifest: hexcode::encode(&bytes),
            signature: hexcode::encode(&self.me.sign(&signed_manifest(&bytes))),
            invited_by: None,
            next_arrival: 0,
            read: BTreeMap::new(),
            joined_at: now(),
            clock: 0,
            muted: false,
            old_keys: Vec::new(),
            epoch: 0,
            closed: false,
            nick: None,
            chain: Vec::new(),
        };
        if kind != Kind::Channel {
            let event = self.member_event(&mut record);
            let joined = self.seal_item(&id, &record.key()?, &event)?;
            self.take(&id, &mut record, &manifest, &joined)?;
        }
        self.save(&id, &record)?;
        Ok(json!({ "id": manifest.id }))
    }

    /// Every space this device knows of, sorted into the three lists the
    /// app shows. `peers` says which spaces each device in range shares.
    pub fn list<'p>(&self, peers: impl Iterator<Item = &'p PeerSpaces> + Clone) -> Result<Value> {
        let (mut joined, mut invited, mut nearby) = (Vec::new(), Vec::new(), Vec::new());
        for (id, record) in self.all()? {
            let hex = hexcode::encode(&id);
            // A deleted space is listed nowhere.
            if record.closed {
                continue;
            }
            let icon = self.icon_of(&id, &record)?;
            let mut view = json!({
                "id": hex,
                "name": record.name,
                "kind": record.kind,
                "description": record.description,
                "icon": icon.map(|bytes| hexcode::encode(&bytes)),
            });
            match record.status {
                Status::Nearby => nearby.push(view),
                Status::Invited => {
                    view["invited_by"] = json!(record.invited_by);
                    invited.push(view);
                }
                Status::Joined => {
                    let items = self.items(&id, &record)?;
                    let me = self.my_key();
                    let manifest = record.manifest();
                    let nothing = Manifest {
                        id: hex.clone(),
                        name: String::new(),
                        kind: record.kind,
                        description: String::new(),
                        owner: record.owner.clone(),
                        channels: Vec::new(),
                        version: 0,
                        chain: Vec::new(),
                        founder: String::new(),
                        banned: Vec::new(),
                        banned_since: 0,
                        words_off: false,
                        welcome: String::new(),
                        rules: String::new(),
                        roles: Vec::new(),
                        icon: String::new(),
                    };
                    let standing =
                        Standing::of(&items, &record, manifest.as_ref().unwrap_or(&nothing));
                    let channels: Vec<Value> = manifest
                        .as_ref()
                        .map(|m| m.channels.as_slice())
                        .unwrap_or_default()
                        .iter()
                        .map(|channel| {
                            let read = record.read.get(&channel.id).copied().unwrap_or(0);
                            let news: Vec<&Item> = items
                                .iter()
                                .filter(|item| item.arrival >= read && item.author != me)
                                .filter(|item| {
                                    // Under a public channel's posts are
                                    // comments, which are not news.
                                    matches!(&item.event, Event::Post { id, channel: c, sent_at, reply_to, .. }
                                        if *c == channel.id
                                            && *sent_at >= record.joined_at
                                            && (record.kind != Kind::Channel || reply_to.is_none())
                                            && standing.shows(id, &item.author, c, *sent_at))
                                })
                                .collect();
                            let unread = news.len();
                            let mentioned = news
                                .iter()
                                .filter(|item| standing.calls(&me, &item.author, &item.event))
                                .count();
                            json!({
                                "id": channel.id,
                                "name": channel.name,
                                "kind": channel.kind,
                                "group": channel.group,
                                "slow": channel.slow,
                                "no_links": channel.no_links,
                                "unread": unread,
                                "mentions": mentioned,
                                "disappear": channel.disappear,
                                "max_len": channel.max_len,
                                "writers": channel.writers,
                                "can_write": standing.writes_in(&me, &channel.id, u64::MAX)
                                    && (channel.group != "info" || standing.may(&me, "announce")),
                            })
                        })
                        .collect();
                    view["channels"] = json!(channels);
                    view["banned"] = json!(manifest
                        .as_ref()
                        .map(|m| m.banned.clone())
                        .unwrap_or_default());
                    view["word_filter"] = json!(manifest.as_ref().is_none_or(|m| !m.words_off));
                    view["welcome"] = json!(manifest
                        .as_ref()
                        .map(|m| m.welcome.as_str())
                        .unwrap_or_default());
                    view["rules"] = json!(manifest
                        .as_ref()
                        .map(|m| m.rules.as_str())
                        .unwrap_or_default());
                    view["mine"] = json!(record.owner_now() == me);
                    view["my_name"] = json!(record.nick);
                    view["role"] = json!(standing.role(&me));
                    view["roles"] = json!(manifest
                        .as_ref()
                        .map(|m| m.roles.clone())
                        .unwrap_or_default());
                    view["powers"] = json!(ROLE_POWERS
                        .iter()
                        .filter(|power| standing.may(&me, power))
                        .collect::<Vec<_>>());
                    view["members"] = json!(standing.present(&items).len());
                    // A public channel's owner is not shown who is there.
                    let in_range = match record.kind {
                        Kind::Channel => 0,
                        _ => peers
                            .clone()
                            .filter(|peer| peer.shared.contains(&hex))
                            .count(),
                    };
                    view["nearby"] = json!(in_range);
                    view["muted"] = json!(record.muted);
                    // False until a member has been met and the space's
                    // channels are known.
                    view["ready"] = json!(!record.manifest.is_empty());
                    joined.push(view);
                }
            }
        }
        for list in [&mut joined, &mut invited, &mut nearby] {
            list.sort_by_key(|space| space["name"].as_str().unwrap_or_default().to_lowercase());
        }
        Ok(json!({ "joined": joined, "invited": invited, "nearby": nearby }))
    }

    #[cfg(test)]
    pub fn member_list(&self, space: &str) -> Result<Value> {
        self.member_list_with(space, |_| None)
    }

    /// The members of a space, each with how they say they are:
    /// `status_of` gives what a member in range said, and anyone who said
    /// nothing, is out of range or chose to be invisible is "offline".
    pub fn member_list_with(
        &self,
        space: &str,
        status_of: impl Fn(&str) -> Option<String>,
    ) -> Result<Value> {
        let (id, record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let items = self.items(&id, &record)?;
        let standing = Standing::of(&items, &record, &manifest);
        let photos = Self::member_photos(&items);
        let mut members: Vec<Value> = standing
            .present(&items)
            .into_iter()
            .map(|(key, (name, identity))| {
                json!({
                    "key": key,
                    "name": name,
                    "identity": identity,
                    "role": standing.role(&key),
                    "roles": standing.roles_of(&key),
                    "renamed": standing.nicks.contains_key(&key),
                    "photo": photos.get(key.as_str()),
                    "status": status_of(&key).unwrap_or_else(|| "offline".to_string()),
                })
            })
            .collect();
        members.sort_by_key(|member| member["name"].as_str().unwrap_or_default().to_lowercase());
        Ok(json!(members))
    }

    /// The name of a space the user is in that `person` is in too.
    pub fn common_space(&self, person: &str) -> Result<Option<String>> {
        for (id, record) in self.all()? {
            if record.status == Status::Joined
                && record.kind != Kind::Channel
                && Self::members(&self.items(&id, &record)?).contains_key(person)
            {
                return Ok(Some(record.name));
            }
        }
        Ok(None)
    }

    /// Every post in a space, as the app is shown it.
    fn shown(&self, record: &Record, manifest: &Manifest, items: &[Item]) -> Vec<Shown> {
        let me = self.my_key();
        let standing = Standing::of(items, record, manifest);
        let members = standing.renamed(Self::members(items));

        // Each person's latest word on each reaction and each poll, and
        // the owner's latest word on each pin.
        let mut reactions: BTreeMap<(&str, &str, &str), (u64, bool)> = BTreeMap::new();
        let mut votes: BTreeMap<(&str, &str), (u64, u32)> = BTreeMap::new();
        let mut pins: BTreeMap<&str, (u64, bool)> = BTreeMap::new();
        for item in items {
            match &item.event {
                Event::React {
                    target,
                    kind,
                    on,
                    sent_at,
                } => {
                    let entry = reactions
                        .entry((target, kind, &item.author))
                        .or_insert((0, false));
                    if *sent_at >= entry.0 {
                        *entry = (*sent_at, *on);
                    }
                }
                Event::Vote {
                    target,
                    choice,
                    sent_at,
                } => {
                    let entry = votes.entry((target, &item.author)).or_insert((0, 0));
                    if *sent_at >= entry.0 {
                        *entry = (*sent_at, *choice);
                    }
                }
                // A pin counts only from someone running the space.
                Event::Pin {
                    target,
                    on,
                    sent_at,
                } if standing.may_at(&item.author, "pin", *sent_at) => {
                    let entry = pins.entry(target).or_insert((0, false));
                    if *sent_at >= entry.0 {
                        *entry = (*sent_at, *on);
                    }
                }
                _ => {}
            }
        }

        // Where the space lists its members, that is where a name comes
        // from. Elsewhere it is the one the writer put on the post.
        let name_of = |author: &str, given: &str| {
            members
                .get(author)
                .map_or_else(|| given.trim().to_string(), |(name, _)| name.clone())
        };
        let mut said: BTreeMap<&str, (&Item, &str, &str)> = items
            .iter()
            .filter_map(|item| match &item.event {
                Event::Post { id, body, name, .. } => {
                    Some((id.as_str(), (item, body.as_str(), name.as_str())))
                }
                _ => None,
            })
            .collect();

        // Each message's newest change, if its writer made one that their
        // own app would have sent: not to a poll, not from before the
        // message, not while removed or told to keep quiet, and keeping
        // to the channel's rule on links.
        let mut changes: BTreeMap<&str, (u64, u64, &str)> = BTreeMap::new();
        for item in items {
            let Event::Edit {
                target,
                body,
                sent_at,
                ..
            } = &item.event
            else {
                continue;
            };
            let Some((post, _, _)) = said.get(target.as_str()) else {
                continue;
            };
            let Event::Post {
                channel,
                options,
                sent_at: written,
                ..
            } = &post.event
            else {
                continue;
            };
            let author = item.author.as_str();
            // Kept to the owner's rules as a new message is: links, length
            // and the words the owner keeps out.
            let here = manifest.channels.iter().find(|c| c.id == *channel);
            let links_ruled_out = !standing.runs_at(author, *sent_at)
                && (here.is_some_and(|c| {
                    *sent_at >= c.since
                        && ((c.no_links && has_link(body))
                            || (c.max_len > 0 && body.chars().count() > c.max_len as usize))
                }) || (*sent_at >= manifest.banned_since
                    && has_banned(body, &manifest.banned)));
            if post.author != author
                || !options.is_empty()
                || sent_at < written
                || standing.removed_by(author, *sent_at)
                || standing.quiet_until(author, *sent_at).is_some()
                || links_ruled_out
            {
                continue;
            }
            let newest = changes.entry(target).or_insert((0, 0, ""));
            if (*sent_at, item.arrival) >= (newest.0, newest.1) {
                *newest = (*sent_at, item.arrival, body.as_str());
            }
        }
        for (target, (_, _, body)) in &changes {
            if let Some(entry) = said.get_mut(target) {
                entry.1 = body;
            }
        }

        items
            .iter()
            .filter_map(|item| {
                let Event::Post { id, channel, sent_at, reply_to, options, name, mentions, file, everyone, roles, forwarded, location, sticker, .. } = &item.event else {
                    return None;
                };
                // Only people the space lists can be called on, each once.
                let mut called: Vec<&str> = Vec::new();
                for key in mentions {
                    if members.contains_key(key.as_str()) && !called.contains(&key.as_str()) {
                        called.push(key);
                    }
                }
                let body = said.get(id.as_str()).map_or("", |(_, body, _)| *body);
                if !standing.shows(id, &item.author, channel, *sent_at) {
                    return None;
                }
                let count = |kind: &str| {
                    let given: Vec<&str> = reactions
                        .iter()
                        .filter(|((target, k, _), (_, on))| *target == id && *k == kind && *on)
                        .map(|((_, _, author), _)| *author)
                        .collect();
                    json!({ "count": given.len(), "mine": given.contains(&me.as_str()) })
                };
                // The two reactions the app always had, then any emoji
                // given, the most given first, up to a limit.
                let mut emoji: BTreeMap<&str, usize> = BTreeMap::new();
                for ((target, kind, _), (_, on)) in &reactions {
                    if *target == id && *on && !REACTIONS.contains(kind) {
                        *emoji.entry(kind).or_default() += 1;
                    }
                }
                let mut emoji: Vec<(&str, usize)> = emoji.into_iter().collect();
                emoji.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
                let given: serde_json::Map<String, Value> = REACTIONS
                    .into_iter()
                    .chain(emoji.into_iter().take(MAX_REACTION_KINDS).map(|(kind, _)| kind))
                    .map(|kind| (kind.to_string(), count(kind)))
                    .collect();
                let replied = reply_to.as_ref().and_then(|target| {
                    said.get(target.as_str()).map(|(to, body, name)| {
                        json!({ "id": target, "name": name_of(&to.author, name), "body": body })
                    })
                });
                let poll = (!options.is_empty()).then(|| {
                    // A choice the poll does not have counts for nothing.
                    let cast: Vec<(&str, usize)> = votes
                        .iter()
                        .filter(|((target, _), _)| *target == id)
                        .map(|((_, author), (_, choice))| (*author, *choice as usize))
                        .filter(|(_, choice)| *choice < options.len())
                        .collect();
                    let choices: Vec<Value> = options
                        .iter()
                        .enumerate()
                        .map(|(n, text)| json!({ "text": text, "votes": cast.iter().filter(|(_, c)| *c == n).count() }))
                        .collect();
                    let mine = cast.iter().find(|(author, _)| *author == me).map(|(_, choice)| *choice);
                    json!({ "options": choices, "mine": mine })
                });
                let pinned_at = pins.get(id.as_str()).filter(|(_, on)| *on).map(|(at, _)| *at);
                Some(Shown {
                    channel: channel.clone(),
                    answers: reply_to.clone(),
                    pinned_at,
                    sent_at: *sent_at,
                    view: json!({
                        "id": id,
                        "author": item.author,
                        "name": name_of(&item.author, name),
                        "mine": item.author == me,
                        "sent_at": sent_at,
                        "body": body,
                        "edited": changes.contains_key(id.as_str()),
                        "file": file.as_ref().map(|file| self.file_view(file)),
                        "ends_at": ends_at(&item.event, Some(manifest)),
                        "mentions": called.iter().map(|key| name_of(key, "")).collect::<Vec<_>>(),
                        "mentions_me": standing.calls(&me, &item.author, &item.event),
                        // Only from someone who could call on everyone.
                        "everyone": *everyone && standing.may_at(&item.author, "mention_everyone", *sent_at),
                        "roles": manifest
                            .roles
                            .iter()
                            .filter(|role| roles.contains(&role.id))
                            .map(|role| role.name.as_str())
                            .collect::<Vec<_>>(),
                        "forwarded": forwarded,
                        "location": location.and_then(Place::checked),
                        "reply_to": replied,
                        "reactions": given,
                        "sticker": sticker,
                        "poll": poll,
                        "pinned": pinned_at.is_some(),
                        "comments": items
                            .iter()
                            .filter(|other| {
                                matches!(&other.event, Event::Post { id: answer, channel, sent_at, reply_to: Some(to), .. }
                                    if to == id && standing.shows(answer, &other.author, channel, *sent_at))
                            })
                            .count(),
                    }),
                })
            })
            .collect()
    }

    /// What has been said in one channel, oldest first, and what the owner
    /// has pinned there.
    pub fn channel(&self, space: &str, channel: &str) -> Result<Value> {
        let (id, record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        if !manifest.channels.iter().any(|c| c.id == channel) {
            return Err(invalid("there is no such channel"));
        }
        // In a public channel the feed is the owner's posts. Answers to
        // them are counted under the post, not listed beside it.
        let feed = record.kind == Kind::Channel;
        let all = self.shown(&record, &manifest, &self.items(&id, &record)?);
        let carried: HashSet<String> = all
            .iter()
            .filter_map(|shown| shown.view["file"]["sha256"].as_str().map(str::to_string))
            .collect();
        self.shelf().sweep(space, &carried)?;
        let mut here: Vec<Shown> = all
            .into_iter()
            .filter(|shown| shown.channel == channel && (!feed || shown.answers.is_none()))
            .collect();
        // Every device shows them in the same order, whatever order they
        // arrived in.
        here.sort_by(by_time);
        let pinned = here.iter().filter(|shown| shown.pinned_at.is_some()).max_by_key(|shown| shown.pinned_at).map(
            |shown| json!({ "id": shown.view["id"], "name": shown.view["name"], "body": shown.view["body"] }),
        );
        let messages: Vec<Value> = here.into_iter().map(|shown| shown.view).collect();
        Ok(json!({ "messages": messages, "pinned": pinned }))
    }

    /// What has been said under one post, oldest first.
    pub fn comments(&self, space: &str, post: &str) -> Result<Value> {
        let (id, record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let mut under: Vec<Shown> = self
            .shown(&record, &manifest, &self.items(&id, &record)?)
            .into_iter()
            .filter(|shown| shown.answers.as_deref() == Some(post))
            .collect();
        under.sort_by(by_time);
        Ok(Value::Array(
            under.into_iter().map(|shown| shown.view).collect(),
        ))
    }

    /// A post that calls on nobody. Used by the tests.
    #[cfg(test)]
    pub fn post(
        &self,
        space: &str,
        channel: &str,
        body: &str,
        reply_to: Option<String>,
        options: Vec<String>,
    ) -> Result<(String, Vec<u8>)> {
        let new = NewPost {
            body: body.to_string(),
            reply_to,
            options,
            ..NewPost::default()
        };
        self.post_mentioning(space, channel, new)
    }

    /// Posts a file. It is copied into this device's folder for files in
    /// channels, from where members who want it fetch it.
    pub fn post_file(
        &self,
        space: &str,
        channel: &str,
        new: NewPost,
        file: FileToPost,
    ) -> Result<(String, Vec<u8>)> {
        self.joined(space)?;
        if !FILE_KINDS.contains(&file.kind.as_str()) {
            return Err(invalid(
                "a channel takes pictures, videos, voice messages and files",
            ));
        }
        let name = file.name.clone().unwrap_or_else(|| {
            file.path
                .file_name()
                .map(|name| name.to_string_lossy().to_string())
                .unwrap_or_default()
        });
        let (sha256, size) = self.shelf().add_own(&file.path, space)?;
        let attached = Attached {
            sha256,
            name: crate::file::safe_name(&name),
            size,
            kind: file.kind,
            seconds: file.seconds,
        };
        self.post_with(space, channel, new, Some(Box::new(attached)))
    }

    /// Returns the new post's id and the sealed item.
    /// With `options` it is a poll, and `body` is its question.
    /// `mentions` are members it calls on, by signing key. Anyone not in
    /// the space is left out, and nobody is named twice.
    pub fn post_mentioning(
        &self,
        space: &str,
        channel: &str,
        new: NewPost,
    ) -> Result<(String, Vec<u8>)> {
        self.post_with(space, channel, new, None)
    }

    /// A new post, with the file it carries if any.
    fn post_with(
        &self,
        space: &str,
        channel: &str,
        new: NewPost,
        file: Option<Box<Attached>>,
    ) -> Result<(String, Vec<u8>)> {
        let NewPost {
            body,
            reply_to,
            options,
            mentions,
            everyone,
            roles,
            forwarded,
            location,
            sticker,
        } = new;
        if sticker.as_ref().is_some_and(|sticker| {
            !sticker.sound() || !options.is_empty() || file.is_some() || location.is_some()
        }) {
            return Err(invalid("a sticker is posted on its own"));
        }
        // A sticker has no words.
        let body = if sticker.is_some() {
            String::new()
        } else {
            body
        };
        let location = match location {
            Some(spot) => Some(
                spot.checked()
                    .ok_or_else(|| invalid("that is not a place on Earth"))?,
            ),
            None => None,
        };
        if location.is_some() && (!options.is_empty() || file.is_some()) {
            return Err(invalid("a place is posted on its own"));
        }
        // The words with a place are the place.
        let body = location.map_or(body, |spot| spot.text());
        let body = body.as_str();
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let Some(place) = manifest.channels.iter().find(|c| c.id == channel) else {
            return Err(invalid("there is no such channel"));
        };
        let runs = self.i_run(&id, &record, &manifest)?;
        {
            let items = self.items(&id, &record)?;
            let standing = Standing::of(&items, &record, &manifest);
            let me = self.my_key();
            // Info channels are for the owner, admins and roles allowed to.
            if place.group == "info" && !standing.may(&me, "announce") {
                return Err(invalid("only the owner and admins write here"));
            }
            if !standing.writes_in(&me, channel, u64::MAX) {
                return Err(invalid("rule:role"));
            }
            // Calling on everyone is for the owner, admins and roles
            // allowed to. Every other device ignores it from anyone else.
            if everyone && !standing.may(&me, "mention_everyone") {
                return Err(invalid("rule:everyone"));
            }
        }
        let sent_at = Self::stamp(&mut record);
        // Someone told to keep quiet waits until it ends.
        if !runs {
            let items = self.items(&id, &record)?;
            let quiet =
                Standing::of(&items, &record, &manifest).quiet_until(&self.my_key(), sent_at);
            if let Some(until) = quiet {
                return Err(invalid(&format!(
                    "rule:timeout:{}",
                    (until - sent_at).div_ceil(1000)
                )));
            }
        }
        // The owner's rules for this channel bind everyone else. The
        // reason is given in a form the app can turn into words.
        if !runs && place.no_links && post_has_link(body, &options) {
            return Err(invalid("rule:links"));
        }
        if !runs && !manifest.words_off && has_banned(body, &manifest.banned) {
            return Err(invalid("rule:banned"));
        }
        if !runs && place.max_len > 0 && body.trim().chars().count() > place.max_len as usize {
            return Err(invalid(&format!("rule:long:{}", place.max_len)));
        }
        if !runs && place.slow > 0 {
            let me = self.my_key();
            let items = self.items(&id, &record)?;
            let standing = Standing::of(&items, &record, &manifest);
            let last = items
                .iter()
                .filter_map(|item| match &item.event {
                    Event::Post {
                        id: said,
                        channel: c,
                        sent_at,
                        ..
                    } if c == channel
                        && item.author == me
                        && *sent_at >= place.since
                        && standing.shows(said, &me, c, *sent_at) =>
                    {
                        Some(*sent_at)
                    }
                    _ => None,
                })
                .max();
            let wait = last.map_or(0, |last| {
                (last + place.slow as u64 * 1000).saturating_sub(sent_at)
            });
            if wait > 0 {
                return Err(invalid(&format!("rule:slow:{}", wait.div_ceil(1000))));
            }
        }
        if !runs {
            let me = self.my_key();
            let items = self.items(&id, &record)?;
            let standing = Standing::of(&items, &record, &manifest);
            let mine: Vec<(u64, &str, String)> = items
                .iter()
                .filter_map(|item| match &item.event {
                    Event::Post {
                        id: said,
                        channel: c,
                        body: b,
                        sent_at: at,
                        file: f,
                        sticker: s,
                        ..
                    } if item.author == me && standing.shows(said, &me, c, *at) => {
                        Some((*at, c.as_str(), post_words(b, f.as_deref(), s.as_ref())))
                    }
                    _ => None,
                })
                .collect();
            let words = post_words(body, file.as_deref(), sticker.as_ref());
            if let Some(why) = spam_of(&mine, sent_at, channel, &words) {
                return Err(invalid(&format!("rule:{why}")));
            }
        }
        let post = hexcode::encode(random_bytes::<16>()?.as_slice());
        // A public channel keeps no list of who follows it, so someone
        // commenting there says what they go by on the comment itself.
        let name = match (record.kind, &reply_to) {
            (Kind::Channel, Some(_)) => self.name_in(&record),
            _ => String::new(),
        };
        let present = Standing::of(&self.items(&id, &record)?, &record, &manifest)
            .present(&self.items(&id, &record)?);
        let mut called: Vec<String> = Vec::new();
        for key in mentions {
            if present.contains_key(&key) && !called.contains(&key) {
                called.push(key);
            }
        }
        called.truncate(MAX_MENTIONS);
        // Only roles the space has, each once, within what one post may
        // call on.
        let mut called_roles: Vec<String> = Vec::new();
        for role in roles {
            if manifest.roles.iter().any(|r| r.id == role) && !called_roles.contains(&role) {
                called_roles.push(role);
            }
        }
        called_roles.truncate(MAX_MENTIONS - called.len());
        let event = Event::Post {
            id: post.clone(),
            channel: channel.to_string(),
            body: body.trim().to_string(),
            sent_at,
            reply_to,
            options: options
                .iter()
                .map(|choice| choice.trim().to_string())
                .collect(),
            name,
            lasts: place.disappear,
            mentions: called,
            file,
            everyone,
            roles: called_roles,
            forwarded,
            location,
            sticker,
        };
        let sealed = self.write(&id, &mut record, &event)?;
        Ok((post, sealed))
    }

    /// Notes that the user wants the file a post carries. Returns the
    /// file's SHA-256 and the piece to ask for next, or None if it is on
    /// this device already.
    pub fn file_get(&self, space: &str, post: &str) -> Result<Option<(String, u64)>> {
        let file = self.file_of(space, post)?;
        Ok(self
            .shelf()
            .want(&file.sha256, file.size, space)?
            .map(|from| (file.sha256, from)))
    }

    /// Copies the file a post carries to `dir` for the user.
    pub fn file_save(&self, space: &str, post: &str, dir: &Path) -> Result<std::path::PathBuf> {
        let file = self.file_of(space, post)?;
        self.shelf().save_copy(&file.sha256, &file.name, dir)
    }

    /// The file a post this device shows carries.
    fn file_of(&self, space: &str, post: &str) -> Result<Attached> {
        let (id, record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let items = self.items(&id, &record)?;
        let standing = Standing::of(&items, &record, &manifest);
        items
            .iter()
            .find_map(|item| match &item.event {
                Event::Post {
                    id: said,
                    channel,
                    sent_at,
                    file: Some(file),
                    ..
                } if said == post && standing.shows(said, &item.author, channel, *sent_at) => {
                    Some(file.as_ref().clone())
                }
                _ => None,
            })
            .ok_or_else(|| invalid("there is no such file"))
    }

    /// Whether `target` is something said in this space, and how many
    /// choices it offers if it is a poll.
    fn choices_of(&self, id: &[u8; 16], record: &Record, target: &str) -> Result<Option<usize>> {
        Ok(self
            .items(id, record)?
            .iter()
            .find_map(|item| match &item.event {
                Event::Post { id, options, .. } if id == target => Some(options.len()),
                _ => None,
            }))
    }

    /// Whether the user may do `power` in a space now.
    fn i_may(
        &self,
        id: &[u8; 16],
        record: &Record,
        manifest: &Manifest,
        power: &str,
    ) -> Result<bool> {
        let items = self.items(id, record)?;
        Ok(Standing::of(&items, record, manifest).may(&self.my_key(), power))
    }

    /// Whether the user is the owner of a space or one of its admins.
    fn i_run(&self, id: &[u8; 16], record: &Record, manifest: &Manifest) -> Result<bool> {
        let items = self.items(id, record)?;
        Ok(Standing::of(&items, record, manifest).runs(&self.my_key()))
    }

    /// Pins a message to the top of its channel, or takes it down. Only
    /// the owner and admins may.
    pub fn pin(&self, space: &str, target: &str, on: bool) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        if self.choices_of(&id, &record, target)?.is_none() {
            return Err(invalid("there is no such message"));
        }
        if !self.i_may(&id, &record, &manifest, "pin")? {
            return Err(invalid(
                "only the owner, admins and roles allowed to can pin",
            ));
        }
        let event = Event::Pin {
            target: target.to_string(),
            on,
            sent_at: Self::stamp(&mut record),
        };
        self.write(&id, &mut record, &event)
    }

    /// Chooses in a poll. Choosing again moves the vote.
    pub fn vote(&self, space: &str, target: &str, choice: u32) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        if !self
            .choices_of(&id, &record, target)?
            .is_some_and(|choices| (choice as usize) < choices)
        {
            return Err(invalid("that is not a choice in a poll here"));
        }
        let event = Event::Vote {
            target: target.to_string(),
            choice,
            sent_at: Self::stamp(&mut record),
        };
        self.write(&id, &mut record, &event)
    }

    /// After the user changed their name: says it again in every space
    /// they are in, so members see the new one. Returns each space's id
    /// with the sealed item to pass on.
    pub fn say_name_again(&self) -> Result<Vec<(String, Vec<u8>)>> {
        let me = self.my_key();
        let mut said = Vec::new();
        for (id, mut record) in self.all()? {
            // A public channel keeps no list of who follows it. And where
            // the user goes by a name of their own, nothing has changed.
            if record.status != Status::Joined
                || record.kind == Kind::Channel
                || record.manifest.is_empty()
                || record.nick.is_some()
            {
                continue;
            }
            if !Self::members(&self.items(&id, &record)?).contains_key(&me) {
                continue;
            }
            let event = self.member_event(&mut record);
            said.push((hexcode::encode(&id), self.write(&id, &mut record, &event)?));
        }
        Ok(said)
    }

    /// Sets what the user goes by in one space, or with an empty name goes
    /// back to their usual one. Everyone in the space is told. Elsewhere
    /// they are who they were.
    pub fn go_by(&self, space: &str, name: &str) -> Result<Option<Vec<u8>>> {
        let (id, mut record) = self.joined(space)?;
        let name = name.trim();
        if name.chars().count() > 64 {
            return Err(invalid("a name can be at most 64 characters"));
        }
        record.nick = (!name.is_empty() && name != self.my_name.trim()).then(|| name.to_string());
        // A public channel keeps no list of who follows it, so there is
        // nobody to tell: the name goes on the user's next comment.
        if record.kind == Kind::Channel
            || !Self::members(&self.items(&id, &record)?).contains_key(&self.my_key())
        {
            self.save(&id, &record)?;
            return Ok(None);
        }
        let event = self.member_event(&mut record);
        self.write(&id, &mut record, &event).map(Some)
    }

    /// Sets what a member is called in this space, for everyone, or with an
    /// empty name lets them go by their own again. The owner and admins
    /// may; an admin not for the owner or another admin.
    pub fn nick(&self, space: &str, member: &str, name: &str) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let name = name.trim();
        if too_long(name, MAX_NAME_CHARS) {
            return Err(invalid("a name can be at most 64 characters"));
        }
        if record.kind == Kind::Channel {
            return Err(invalid("a public channel lists nobody to rename"));
        }
        let me = self.my_key();
        {
            let items = self.items(&id, &record)?;
            let standing = Standing::of(&items, &record, &manifest);
            if !standing.runs(&me) {
                return Err(invalid("only the owner and admins change names"));
            }
            if member == standing.owner || (me != standing.owner && standing.runs(member)) {
                return Err(invalid(
                    "an admin does not rename the owner or another admin",
                ));
            }
            if !standing.present(&items).contains_key(member) {
                return Err(invalid("they are not in this space"));
            }
        }
        let sent_at = Self::stamp(&mut record);
        let event = Event::Nick {
            member: member.to_string(),
            name: name.to_string(),
            sent_at,
        };
        self.write(&id, &mut record, &event)
    }

    /// Takes a message down for everyone. Its writer may, and so may the
    /// owner and admins.
    pub fn delete(&self, space: &str, target: &str) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let items = self.items(&id, &record)?;
        let writer = items.iter().find_map(|item| match &item.event {
            Event::Post { id, .. } if id == target => Some(item.author.as_str()),
            _ => None,
        });
        let me = self.my_key();
        let may = match writer {
            None => return Err(invalid("there is no such message")),
            Some(writer) => {
                writer == me || Standing::of(&items, &record, &manifest).may(&me, "delete")
            }
        };
        if !may {
            return Err(invalid("that is not yours to take down"));
        }
        let event = Event::Delete {
            target: target.to_string(),
            sent_at: Self::stamp(&mut record),
        };
        self.write(&id, &mut record, &event)
    }

    /// Changes the words of something the user wrote. Not a poll, whose
    /// question was voted on as it was. The channel's rules hold as they
    /// do for a new message.
    pub fn edit_post(&self, space: &str, target: &str, body: &str) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let body = body.trim();
        if body.is_empty() || too_long(body, MAX_BODY_CHARS) {
            return Err(invalid("a message needs words, and not too many"));
        }
        // Stamped first: what is judged below holds on to the record.
        let sent_at = Self::stamp(&mut record);
        let items = self.items(&id, &record)?;
        let standing = Standing::of(&items, &record, &manifest);
        let me = self.my_key();
        let found = items.iter().find_map(|item| match &item.event {
            Event::Post {
                id: said,
                channel,
                options,
                sent_at,
                ..
            } if said == target => Some((item.author.as_str(), channel, options, *sent_at)),
            _ => None,
        });
        let Some((writer, channel, options, written)) = found else {
            return Err(invalid("there is no such message"));
        };
        if writer != me || !standing.shows(target, writer, channel, written) {
            return Err(invalid("only its writer changes a message"));
        }
        if !options.is_empty() {
            return Err(invalid("a poll cannot be changed"));
        }
        if !standing.runs_at(&me, sent_at) {
            if let Some(until) = standing.quiet_until(&me, sent_at) {
                return Err(invalid(&format!(
                    "rule:timeout:{}",
                    (until - sent_at).div_ceil(1000)
                )));
            }
            let here = manifest.channels.iter().find(|c| c.id == *channel);
            if here.is_some_and(|c| c.no_links) && has_link(body) {
                return Err(invalid("rule:links"));
            }
            if has_banned(body, &manifest.banned) {
                return Err(invalid("rule:banned"));
            }
            if let Some(longest) = here.map(|c| c.max_len).filter(|max| *max > 0) {
                if body.chars().count() > longest as usize {
                    return Err(invalid(&format!("rule:long:{longest}")));
                }
            }
        }
        let until = items
            .iter()
            .find(|item| matches!(&item.event, Event::Post { id: said, .. } if said == target))
            .and_then(|item| ends_at(&item.event, Some(&manifest)))
            .unwrap_or(0);
        let event = Event::Edit {
            target: target.to_string(),
            body: body.to_string(),
            sent_at,
            until,
        };
        self.write(&id, &mut record, &event)
    }

    /// Deletes a space for everyone in it. Only the owner can. Members in
    /// range lose it at once, and the rest when they next meet anyone who
    /// has heard.
    pub fn close(&self, space: &str) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let event = Event::Closed {
            sent_at: Self::stamp(&mut record),
        };
        self.write(&id, &mut record, &event)
    }

    /// Hands a space to another member. From then on it is theirs, and
    /// the user is a member like any other. It cannot be taken back: only
    /// the new owner can hand it on again.
    pub fn hand_over(&self, space: &str, to: &str) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let me = self.my_key();
        if record.owner_now() != me {
            return Err(invalid("only the owner can hand a space over"));
        }
        if record.kind == Kind::Channel {
            return Err(invalid("a public channel cannot be handed over"));
        }
        if to == me || record.chain.len() >= MAX_HANDOVERS {
            return Err(invalid("this space cannot be handed over that way"));
        }
        let items = self.items(&id, &record)?;
        if !Standing::of(&items, &record, &manifest)
            .present(&items)
            .contains_key(to)
        {
            return Err(invalid("that person is not in this space"));
        }
        // Everything the user decided as owner. After this it is all of
        // theirs that counts.
        let log: Vec<Event> = items
            .iter()
            .filter(|item| item.author == me)
            .filter(|item| {
                matches!(
                    item.event,
                    Event::Role { .. } | Event::Remove { .. } | Event::Grant { .. }
                )
            })
            .map(|item| item.event.clone())
            .collect();
        if log.len() > MAX_HANDOVER_LOG {
            return Err(invalid("this space has too long a history to hand over"));
        }
        let at = Self::stamp(&mut record);
        let statement = serde_json::to_vec(&Handed {
            space: manifest.id.clone(),
            index: record.chain.len() as u32,
            from: me,
            to: to.to_string(),
            at,
            log,
        })
        .expect("a hand-over is plain data");
        let event = Event::Handover {
            signature: hexcode::encode(&self.me.sign(&signed_handover(&statement))),
            statement: hexcode::encode(&statement),
            sent_at: at,
        };
        self.write(&id, &mut record, &event)
    }

    /// If the space has been handed to the user and what says what the
    /// space is has not been signed by them yet, signs it. Until they do,
    /// someone who joins later is handed the old owner's word and has to
    /// find the hand-over among everything else. Returns what was written.
    fn take_up(&self, id: &[u8; 16], record: &mut Record) -> Result<Option<Vec<u8>>> {
        let me = self.my_key();
        let mine_now = !record.closed && !record.chain.is_empty() && record.owner_now() == me;
        if !mine_now
            || record
                .manifest()
                .is_none_or(|manifest| manifest.owner == me)
        {
            return Ok(None);
        }
        self.resign(id, record, |_| Ok(())).map(Some)
    }

    /// Signs a changed manifest and writes it into the space, where every
    /// member's device will find it. Only the owner can: nobody else can
    /// sign for the space.
    fn resign(
        &self,
        id: &[u8; 16],
        record: &mut Record,
        change: impl FnOnce(&mut Manifest) -> Result<()>,
    ) -> Result<Vec<u8>> {
        if record.owner_now() != self.my_key() {
            return Err(invalid("only the owner can change this"));
        }
        let mut manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        change(&mut manifest)?;
        manifest.version += 1;
        // Signed by the owner now, with every hand-over that made them so.
        manifest.owner = self.my_key();
        manifest.chain = record.chain.clone();
        manifest.founder = match record.chain.is_empty() {
            true => String::new(),
            false => record.owner.clone(),
        };
        let bytes = serde_json::to_vec(&manifest).expect("a manifest is plain data");
        let (bytes, signature) = (
            hexcode::encode(&bytes),
            hexcode::encode(&self.me.sign(&signed_manifest(&bytes))),
        );
        // The same checks every other device will make.
        if read_manifest(&bytes, &signature).is_none() {
            return Err(invalid(
                "that name cannot be used, or a space would be left with no channel",
            ));
        }
        let event = Event::Manifest {
            manifest: bytes,
            signature,
            sent_at: Self::stamp(record),
        };
        self.write(id, record, &event)
    }

    /// Changes a space's name, its description, or both.
    pub fn edit(
        &self,
        space: &str,
        name: Option<String>,
        description: Option<String>,
    ) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        self.resign(&id, &mut record, |manifest| {
            if let Some(name) = name {
                manifest.name = name.trim().to_string();
            }
            if let Some(description) = description {
                manifest.description = description.trim().to_string();
            }
            Ok(())
        })
    }

    /// Sets what the owner says to everyone who joins, the space's rules,
    /// or both. What is not given is left as it is; empty takes it away.
    /// Signed with the rest of what the space is. Owner only.
    pub fn welcome(
        &self,
        space: &str,
        welcome: Option<String>,
        rules: Option<String>,
    ) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        if welcome
            .as_ref()
            .is_some_and(|text| too_long(text.trim(), MAX_WELCOME_CHARS))
            || rules
                .as_ref()
                .is_some_and(|text| too_long(text.trim(), MAX_RULES_CHARS))
        {
            return Err(invalid(
                "a welcome is up to 500 characters, rules up to 2000",
            ));
        }
        self.resign(&id, &mut record, |manifest| {
            if let Some(welcome) = welcome {
                manifest.welcome = welcome.trim().to_string();
            }
            if let Some(rules) = rules {
                manifest.rules = rules.trim().to_string();
            }
            Ok(())
        })
    }

    /// Sets the space's icon, a small picture or GIF in hex, or with none
    /// takes it away. Only its fingerprint is signed with the rest of what
    /// the space is; the picture is kept here, for members and anyone
    /// nearby who asks. Owner only.
    pub fn set_icon(&self, space: &str, icon: Option<&str>) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let bytes = match icon {
            None => None,
            Some(hex) => {
                let bytes = hexcode::decode(hex).unwrap_or_default();
                if bytes.is_empty()
                    || bytes.len() > MAX_ICON_BYTES
                    || !crate::chat::sound_photo(hex)
                {
                    return Err(invalid(
                        "a space icon is one small picture or GIF, up to 24 KB",
                    ));
                }
                Some(bytes)
            }
        };
        let named = bytes
            .as_ref()
            .map(|bytes| hexcode::encode(&Sha256::digest(bytes)))
            .unwrap_or_default();
        let sealed = self.resign(&id, &mut record, |manifest| {
            manifest.icon = named;
            Ok(())
        })?;
        match bytes {
            Some(bytes) => self.vault.put(ICON, &id, &bytes)?,
            None => self.vault.delete(ICON, &id)?,
        }
        Ok(sealed)
    }

    /// Makes a role. `may` is some of "pin", "announce", "delete" and
    /// "timeout". Returns its id. Owner only.
    pub fn role_add(&self, space: &str, name: &str, may: Vec<String>) -> Result<(String, Vec<u8>)> {
        let (id, mut record) = self.joined(space)?;
        let role = hexcode::encode(random_bytes::<8>()?.as_slice());
        let sealed = self.resign(&id, &mut record, |manifest| {
            manifest.roles.push(RoleDef {
                id: role.clone(),
                name: name.trim().to_string(),
                may: Self::powers_in(may)?,
            });
            Ok(())
        })?;
        Ok((role, sealed))
    }

    /// Renames a role, or changes what it may do, or both. Owner only.
    pub fn role_edit(
        &self,
        space: &str,
        role: &str,
        name: Option<String>,
        may: Option<Vec<String>>,
    ) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        self.resign(&id, &mut record, |manifest| {
            let Some(found) = manifest.roles.iter_mut().find(|r| r.id == role) else {
                return Err(invalid("there is no such role"));
            };
            if let Some(name) = name {
                found.name = name.trim().to_string();
            }
            if let Some(may) = may {
                found.may = Self::powers_in(may)?;
            }
            Ok(())
        })
    }

    /// Deletes a role. Nobody holds it any more, and channels kept for it
    /// are open again unless they were kept for other roles too. Owner
    /// only.
    pub fn role_remove(&self, space: &str, role: &str) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        self.resign(&id, &mut record, |manifest| {
            let before = manifest.roles.len();
            manifest.roles.retain(|r| r.id != role);
            if manifest.roles.len() == before {
                return Err(invalid("there is no such role"));
            }
            for channel in &mut manifest.channels {
                channel.writers.retain(|r| r != role);
            }
            Ok(())
        })
    }

    /// What a role may do, checked, without repeats, in the app's order.
    fn powers_in(may: Vec<String>) -> Result<Vec<String>> {
        if may
            .iter()
            .any(|power| !ROLE_POWERS.contains(&power.as_str()))
        {
            return Err(invalid(
                "a role may pin, announce, delete, time out or call on everyone",
            ));
        }
        Ok(ROLE_POWERS
            .iter()
            .filter(|power| may.iter().any(|p| p == *power))
            .map(|power| power.to_string())
            .collect())
    }

    /// Gives a member one of the space's roles, or takes it back. Owner
    /// only.
    pub fn grant(&self, space: &str, member: &str, role: &str, on: bool) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let owner = record.owner_now();
        if owner != self.my_key() {
            return Err(invalid("only the owner gives roles"));
        }
        if !manifest.roles.iter().any(|r| r.id == role) {
            return Err(invalid("there is no such role"));
        }
        let items = self.items(&id, &record)?;
        if member == owner
            || !Standing::of(&items, &record, &manifest)
                .present(&items)
                .contains_key(member)
        {
            return Err(invalid("that person is not a member here"));
        }
        let event = Event::Grant {
            member: member.to_string(),
            role: role.to_string(),
            on,
            sent_at: Self::stamp(&mut record),
        };
        self.write(&id, &mut record, &event)
    }

    /// Sets the words and phrases members may not use anywhere in the
    /// space. Blank ones and repeats are dropped. Owner only.
    pub fn banned_words(&self, space: &str, words: Vec<String>) -> Result<Vec<u8>> {
        let mut kept: Vec<String> = Vec::new();
        for word in words {
            let word = words_of(&word).join(" ");
            if !word.is_empty() && !kept.contains(&word) {
                kept.push(word);
            }
        }
        if kept.len() > MAX_BANNED || kept.iter().any(|w| too_long(w, MAX_BANNED_CHARS)) {
            return Err(invalid("up to 50 words, of up to 32 characters each"));
        }
        let (id, mut record) = self.joined(space)?;
        let since = Self::stamp(&mut record);
        self.resign(&id, &mut record, |manifest| {
            manifest.banned = kept;
            manifest.banned_since = since;
            Ok(())
        })
    }

    /// Switches the word filter off, keeping the list, or on again. On
    /// again, it binds what is written from then: what was said while it
    /// was off stays.
    pub fn word_filter(&self, space: &str, on: bool) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let since = Self::stamp(&mut record);
        self.resign(&id, &mut record, |manifest| {
            if on && manifest.words_off {
                manifest.banned_since = since;
            }
            manifest.words_off = !on;
            Ok(())
        })
    }

    /// Adds a channel. `group` is "text", or "info" for one only the owner
    /// and admins write in. Returns the new channel's id.
    pub fn channel_add(&self, space: &str, name: &str, group: &str) -> Result<(String, Vec<u8>)> {
        let (id, mut record) = self.joined(space)?;
        if !["text", "info", "voice"].contains(&group) || record.kind == Kind::Channel {
            return Err(invalid("that kind of channel cannot be added here"));
        }
        let channel = hexcode::encode(random_bytes::<8>()?.as_slice());
        let sealed = self.resign(&id, &mut record, |manifest| {
            manifest.channels.push(ChannelDef {
                id: channel.clone(),
                name: name.trim().to_string(),
                kind: match group {
                    "info" => "announcements",
                    "voice" => "voice",
                    _ => "text",
                }
                .to_string(),
                group: group.to_string(),
                slow: 0,
                no_links: false,
                since: 0,
                disappear: 0,
                max_len: 0,
                writers: Vec::new(),
            });
            Ok(())
        })?;
        Ok((channel, sealed))
    }

    /// Sets the owner's rules for one channel: slow mode, no links, and
    /// whether only the owner and admins write there. What is not given is
    /// left as it is. The rules bind what is written from now on.
    pub fn channel_rules(
        &self,
        space: &str,
        channel: &str,
        rules: ChannelRules,
    ) -> Result<Vec<u8>> {
        let ChannelRules {
            slow,
            no_links,
            owners_only,
            disappear,
            max_len,
            writers,
        } = rules;
        if disappear.is_some_and(|d| d != 0 && !DISAPPEAR_CHOICES.contains(&d)) {
            return Err(invalid("messages last an hour, a day or a week"));
        }
        if max_len.is_some_and(|n| n != 0 && !LENGTH_CHOICES.contains(&n)) {
            return Err(invalid("a channel allows 200, 500 or 2000 characters"));
        }
        let (id, mut record) = self.joined(space)?;
        let since = Self::stamp(&mut record);
        self.resign(&id, &mut record, |manifest| {
            let Some(found) = manifest.channels.iter_mut().find(|c| c.id == channel) else {
                return Err(invalid("there is no such channel"));
            };
            found.slow = slow.unwrap_or(found.slow);
            found.no_links = no_links.unwrap_or(found.no_links);
            found.disappear = disappear.unwrap_or(found.disappear);
            found.max_len = max_len.unwrap_or(found.max_len);
            if let Some(writers) = writers {
                found.writers = writers;
            }
            if let Some(only) = owners_only {
                found.group = if only { "info" } else { "text" }.to_string();
                found.kind = if only { "announcements" } else { "text" }.to_string();
            }
            found.since = since;
            Ok(())
        })
    }

    pub fn channel_rename(&self, space: &str, channel: &str, name: &str) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        self.resign(&id, &mut record, |manifest| {
            let Some(found) = manifest.channels.iter_mut().find(|c| c.id == channel) else {
                return Err(invalid("there is no such channel"));
            };
            found.name = name.trim().to_string();
            Ok(())
        })
    }

    /// Removes a channel. What was said in it stays on the devices that
    /// hold it but is no longer shown.
    pub fn channel_remove(&self, space: &str, channel: &str) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        self.resign(&id, &mut record, |manifest| {
            if !manifest.channels.iter().any(|c| c.id == channel) {
                return Err(invalid("there is no such channel"));
            }
            manifest.channels.retain(|c| c.id != channel);
            Ok(())
        })
    }

    /// Makes a member an admin, or no longer one. Only the owner can.
    pub fn set_role(&self, space: &str, member: &str, admin: bool) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        if !Self::members(&self.items(&id, &record)?).contains_key(member) {
            return Err(invalid("that person is not in this space"));
        }
        let event = Event::Role {
            member: member.to_string(),
            admin,
            sent_at: Self::stamp(&mut record),
        };
        self.write(&id, &mut record, &event)
    }

    /// Puts someone out of a space. Only the owner can.
    ///
    /// Returns the sealed word of it, to pass to members in range. For a
    /// private space it also changes the space's key and returns the new
    /// one for each member who is staying, with their identity, to be
    /// sealed to each of them alone. Whoever was removed keeps what they
    /// already had and gets nothing written afterwards.
    ///
    /// A public space's key is given to anyone nearby, so there the
    /// removal can only mean that nothing they write is shown any more.
    pub fn remove(&self, space: &str, member: &str) -> Result<(Vec<u8>, Vec<Rekeying>)> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let me = self.my_key();
        let staying: Vec<(String, String)> = {
            let items = self.items(&id, &record)?;
            let present = Standing::of(&items, &record, &manifest).present(&items);
            if !present.contains_key(member) {
                return Err(invalid("that person is not in this space"));
            }
            present
                .into_iter()
                .filter(|(key, _)| key != member && *key != me)
                .map(|(key, (_, identity))| (key, identity))
                .collect()
        };
        let event = Event::Remove {
            member: member.to_string(),
            on: true,
            sent_at: Self::stamp(&mut record),
        };
        let sealed = self.write(&id, &mut record, &event)?;
        if record.kind != Kind::Private {
            return Ok((sealed, Vec::new()));
        }
        let key = hexcode::encode(random_bytes::<32>()?.as_slice());
        record
            .old_keys
            .insert(0, std::mem::replace(&mut record.key, key.clone()));
        record.epoch += 1;
        self.save(&id, &record)?;
        let rekeying = staying
            .into_iter()
            .map(|(to, identity)| {
                (
                    to,
                    identity,
                    Wire::Rekey {
                        space: space.to_string(),
                        epoch: record.epoch,
                        key: key.clone(),
                    },
                )
            })
            .collect();
        Ok((sealed, rekeying))
    }

    /// Tells a member to keep quiet for `seconds`, or with 0 lets them
    /// speak again. The owner and admins can. What they write meanwhile
    /// is refused by their own app and shown by nobody else's.
    pub fn timeout(&self, space: &str, member: &str, seconds: u64) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        if !self.i_may(&id, &record, &manifest, "timeout")? || seconds > 7 * 24 * 60 * 60 {
            return Err(invalid(
                "only the owner, admins and roles allowed to can, and for a week at most",
            ));
        }
        {
            let items = self.items(&id, &record)?;
            let standing = Standing::of(&items, &record, &manifest);
            if !standing.runs(&self.my_key()) && standing.runs(member) {
                return Err(invalid("a role does not reach the owner's admins"));
            }
        }
        if !Self::members(&self.items(&id, &record)?).contains_key(member) {
            return Err(invalid("that person is not in this space"));
        }
        let sent_at = Self::stamp(&mut record);
        let event = Event::Timeout {
            member: member.to_string(),
            until: sent_at + seconds * 1000,
            sent_at,
        };
        self.write(&id, &mut record, &event)
    }

    /// Changes a private space's key and sends the new one to everyone in
    /// it, so that every invite link made before stops working. Nobody is
    /// removed. Only the owner can.
    pub fn reset_links(&self, space: &str) -> Result<Vec<Rekeying>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let me = self.my_key();
        if record.owner_now() != me || record.kind != Kind::Private {
            return Err(invalid("only the owner of a private space can do this"));
        }
        let staying: Vec<(String, String)> = {
            let items = self.items(&id, &record)?;
            let present = Standing::of(&items, &record, &manifest).present(&items);
            present
                .into_iter()
                .filter(|(key, _)| *key != me)
                .map(|(key, (_, identity))| (key, identity))
                .collect()
        };
        let key = hexcode::encode(random_bytes::<32>()?.as_slice());
        record
            .old_keys
            .insert(0, std::mem::replace(&mut record.key, key.clone()));
        record.epoch += 1;
        self.save(&id, &record)?;
        Ok(staying
            .into_iter()
            .map(|(to, identity)| {
                (
                    to,
                    identity,
                    Wire::Rekey {
                        space: space.to_string(),
                        epoch: record.epoch,
                        key: key.clone(),
                    },
                )
            })
            .collect())
    }

    /// If the owner is inviting someone they once removed, lets them back.
    /// Returns the sealed word of it, if there was any to write.
    pub fn allow_back(&self, space: &str, person: &str) -> Result<Option<Vec<u8>>> {
        let (id, mut record) = self.joined(space)?;
        let Some(manifest) = record.manifest() else {
            return Ok(None);
        };
        let removed = {
            let items = self.items(&id, &record)?;
            Standing::of(&items, &record, &manifest)
                .removed
                .contains_key(person)
        };
        if !removed || record.owner_now() != self.my_key() {
            return Ok(None);
        }
        let event = Event::Remove {
            member: person.to_string(),
            on: false,
            sent_at: Self::stamp(&mut record),
        };
        self.write(&id, &mut record, &event).map(Some)
    }

    pub fn react(&self, space: &str, target: &str, kind: &str, on: bool) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let event = Event::React {
            target: target.to_string(),
            kind: kind.to_string(),
            on,
            sent_at: Self::stamp(&mut record),
        };
        self.write(&id, &mut record, &event)
    }

    pub fn mark_read(&self, space: &str, channel: &str) -> Result<()> {
        let (id, mut record) = self.joined(space)?;
        record.read.insert(channel.to_string(), record.next_arrival);
        self.save(&id, &record)
    }

    pub fn mute(&self, space: &str, on: bool) -> Result<()> {
        let (id, mut record) = self.joined(space)?;
        record.muted = on;
        self.save(&id, &record)
    }

    /// Joins a space the user was invited to, or a public one nearby.
    pub fn join(&self, space: &str) -> Result<()> {
        let id = space_id(space)?;
        let mut record = match self.load(&id)? {
            Some(record) if record.status != Status::Joined => record,
            Some(_) => return Ok(()),
            None => return Err(invalid("there is no such space to join")),
        };
        record.status = Status::Joined;
        record.joined_at = now();
        self.announce_membership(&id, &mut record)?;
        self.save(&id, &record)
    }

    /// Says "I am here" in a space, once its manifest is known. Returns the
    /// sealed item if one was written. The caller saves `record`.
    fn announce_membership(&self, id: &[u8; 16], record: &mut Record) -> Result<Option<Vec<u8>>> {
        let Some(manifest) = record.manifest() else {
            return Ok(None);
        };
        if record.kind == Kind::Channel
            || Self::members(&self.items(id, record)?).contains_key(&self.my_key())
        {
            return Ok(None);
        }
        let event = self.member_event(record);
        let joined = self.seal_item(id, &record.key()?, &event)?;
        self.take(id, record, &manifest, &joined)?;
        Ok(Some(joined))
    }

    /// Leaves a space, or turns down an invite. Returns the sealed "I have
    /// left" to pass to members in range, if there is one to pass.
    pub fn leave(&self, space: &str) -> Result<Option<Vec<u8>>> {
        let id = space_id(space)?;
        let Some(mut record) = self.load(&id)? else {
            return Ok(None);
        };
        let goodbye = match record.status {
            Status::Joined if record.kind != Kind::Channel && !record.manifest.is_empty() => {
                let left = Event::Left {
                    sent_at: Self::stamp(&mut record),
                };
                Some(self.write(&id, &mut record, &left)?)
            }
            _ => None,
        };
        self.forget(&id)?;
        Ok(goodbye)
    }

    /// An invite as text, for pasting. Whoever has it can join, so it is
    /// only as private as the way it is passed on.
    /// A link that never runs out. Used by the tests.
    #[cfg(test)]
    pub fn link(&self, space: &str) -> Result<String> {
        self.link_until(space, None)
    }

    /// A link that lets people in for `lasts` seconds, or for good with
    /// none. Returns it and when it ends.
    ///
    /// Running out is kept by every honest app, which will not join with
    /// it afterwards. The link holds the space's key, so a changed app
    /// that kept a copy could still use it; changing the key ("reset
    /// invite links") is what stops that.
    pub fn link_lasting(&self, space: &str, lasts: Option<u64>) -> Result<(String, Option<u64>)> {
        let expires = match lasts {
            None => None,
            Some(seconds) if (LINK_SHORTEST..=LINK_LONGEST).contains(&seconds) => {
                Some(now() + seconds * 1000)
            }
            Some(_) => return Err(invalid("a link lasts from an hour to thirty days")),
        };
        Ok((self.link_until(space, expires)?, expires))
    }

    fn link_until(&self, space: &str, expires: Option<u64>) -> Result<String> {
        let (id, record) = self.joined(space)?;
        let mut bytes = vec![if expires.is_some() { 2u8 } else { 1u8 }];
        bytes.extend_from_slice(&id);
        bytes.extend_from_slice(&record.key()?);
        bytes.extend_from_slice(&hexcode::decode(&record.owner)?);
        bytes.push(record.kind.byte());
        if let Some(end) = expires {
            bytes.extend_from_slice(&end.to_be_bytes());
            bytes.extend_from_slice(&self.me.signing_public());
            let signed = [LINK_CONTEXT, &bytes, record.name.as_bytes()].concat();
            bytes.extend_from_slice(&self.me.sign(&signed));
        }
        bytes.extend_from_slice(record.name.as_bytes());
        Ok(format!("{LINK_PREFIX}{}", hexcode::encode(&bytes)))
    }

    /// What a pasted invite is for, and whether it has run out, without
    /// joining.
    pub fn check_link(&self, link: &str) -> Result<Value> {
        let invite = read_link(link)?;
        Ok(json!({
            "space": hexcode::encode(&invite.id),
            "name": invite.name,
            "expires_at": invite.expires,
            "expired": invite.expires.is_some_and(|end| end <= now()),
        }))
    }

    /// Joins by a pasted invite. The space is empty until a member is met.
    pub fn join_link(&self, link: &str) -> Result<String> {
        let Invite {
            id,
            key,
            owner,
            kind,
            name,
            expires,
        } = read_link(link)?;
        let known = self.load(&id)?;
        if known
            .as_ref()
            .is_some_and(|record| record.status == Status::Joined)
        {
            return Ok(hexcode::encode(&id));
        }
        if expires.is_some_and(|end| end <= now()) {
            return Err(invalid("expired"));
        }
        let name = name.as_str();
        // A manifest already heard from an announcement or an invite is
        // kept only if it is for this same space and owner.
        let heard = known.filter(|record| record.owner == owner && record.key == key);
        let mut record = Record {
            key,
            owner,
            status: Status::Joined,
            name: name.to_string(),
            kind,
            description: heard
                .as_ref()
                .map(|r| r.description.clone())
                .unwrap_or_default(),
            manifest: heard
                .as_ref()
                .map(|r| r.manifest.clone())
                .unwrap_or_default(),
            signature: heard
                .as_ref()
                .map(|r| r.signature.clone())
                .unwrap_or_default(),
            invited_by: None,
            next_arrival: 0,
            read: BTreeMap::new(),
            joined_at: now(),
            clock: 0,
            muted: false,
            old_keys: Vec::new(),
            epoch: 0,
            closed: false,
            nick: None,
            chain: Vec::new(),
        };
        self.announce_membership(&id, &mut record)?;
        self.save(&id, &record)?;
        Ok(hexcode::encode(&id))
    }

    /// The invite to send a contact.
    pub fn invite(&self, space: &str) -> Result<Wire> {
        let (_, record) = self.joined(space)?;
        if record.manifest.is_empty() {
            return Err(invalid("this space has not arrived yet"));
        }
        Ok(Wire::Invite {
            space: record.announcement(),
        })
    }

    /// Whether `who` is a member of `space` now and `channel` is one of
    /// its voice rooms. A public channel has none.
    fn voice_room_of(&self, who: &str, space: &str, channel: &str) -> Result<bool> {
        let Ok((id, record)) = self.joined(space) else {
            return Ok(false);
        };
        let Some(manifest) = record.manifest() else {
            return Ok(false);
        };
        if record.kind == Kind::Channel || record.closed {
            return Ok(false);
        }
        if !manifest
            .channels
            .iter()
            .any(|c| c.id == channel && c.kind == "voice")
        {
            return Ok(false);
        }
        let items = self.items(&id, &record)?;
        let standing = Standing::of(&items, &record, &manifest);
        Ok(standing.present(&items).contains_key(who))
    }

    /// Who whoever runs the space has muted, and deafened, in its voice
    /// rooms. Refused unless the user may go into `channel`: a member,
    /// and it a voice room.
    pub fn voice_standing(
        &self,
        space: &str,
        channel: &str,
    ) -> Result<(HashSet<String>, HashSet<String>)> {
        if !self.voice_room_of(&self.my_key(), space, channel)? {
            return Err(invalid("that is not a voice room the user is in"));
        }
        let (id, record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        let items = self.items(&id, &record)?;
        let standing = Standing::of(&items, &record, &manifest);
        let (mut muted, mut deaf) = (HashSet::new(), HashSet::new());
        for (member, (_, mute, deafen)) in &standing.voice {
            if *mute {
                muted.insert(member.to_string());
            }
            if *deafen {
                deaf.insert(member.to_string());
            }
        }
        Ok((muted, deaf))
    }

    /// Whoever runs the space mutes a member in its voice rooms, or
    /// deafens them so they hear nothing there, or lets them be. The owner
    /// reaches anyone; an admin reaches anyone but the owner and the other
    /// admins.
    pub fn voice(&self, space: &str, member: &str, mute: bool, deafen: bool) -> Result<Vec<u8>> {
        let (id, mut record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        if record.kind == Kind::Channel {
            return Err(invalid("a public channel has no voice rooms"));
        }
        let me = self.my_key();
        {
            let items = self.items(&id, &record)?;
            let standing = Standing::of(&items, &record, &manifest);
            if !standing.runs(&me) {
                return Err(invalid("only the owner and admins can"));
            }
            if member == standing.owner || (me != standing.owner && standing.runs(member)) {
                return Err(invalid(
                    "an admin does not reach the owner or another admin",
                ));
            }
            if !Self::members(&items).contains_key(member) {
                return Err(invalid("that person is not in this space"));
            }
        }
        let sent_at = Self::stamp(&mut record);
        let event = Event::Voice {
            member: member.to_string(),
            mute,
            deafen,
            sent_at,
        };
        self.write(&id, &mut record, &event)
    }

    /// What to tell members in range while the user writes in a channel.
    /// Only where they may write, and never in a public channel, which
    /// keeps no list of who follows it. The caller has checked the user's
    /// switch.
    pub fn typing(&self, space: &str, channel: &str) -> Result<Wire> {
        let (id, record) = self.joined(space)?;
        let manifest = record
            .manifest()
            .ok_or_else(|| invalid("this space has not arrived yet"))?;
        if record.kind == Kind::Channel || record.closed {
            return Err(invalid("nobody is told who writes here"));
        }
        let items = self.items(&id, &record)?;
        if !Self::may_write(&self.my_key(), channel, &items, &record, &manifest) {
            return Err(invalid("the user cannot write in this channel"));
        }
        Ok(Wire::Typing {
            space: space.to_string(),
            channel: channel.to_string(),
        })
    }

    /// Whether `who` can write in `channel` now: a member who is not
    /// timed out, in a text channel they are allowed to write in.
    fn may_write(
        who: &str,
        channel: &str,
        items: &[Item],
        record: &Record,
        manifest: &Manifest,
    ) -> bool {
        let Some(place) = manifest.channels.iter().find(|c| c.id == channel) else {
            return false;
        };
        let standing = Standing::of(items, record, manifest);
        place.kind != "voice"
            && standing.present(items).contains_key(who)
            && standing.writes_in(who, channel, u64::MAX)
            && (place.group != "info" || standing.may(who, "announce"))
            && standing.quiet_until(who, now()).is_none()
    }

    // What devices say to each other

    /// What to say to a device on meeting it, or after the user's own
    /// spaces change. Also works out again which spaces the two share.
    pub fn hello(&self, peer: &str, known: &mut PeerSpaces, sync: bool) -> Result<Wire> {
        let (me, them) = (self.me.signing_public(), hexcode::decode(peer)?);
        let (mut tags, mut public) = (Vec::new(), Vec::new());
        known.shared.clear();
        for (id, record) in self.all()? {
            if record.status != Status::Joined {
                continue;
            }
            let key = record.key()?;
            tags.push(tag(&key, &id, &me, &them));
            if known.tags.contains(&tag(&key, &id, &them, &me)) {
                known.shared.insert(hexcode::encode(&id));
            }
            if record.kind != Kind::Private
                && !record.closed
                && !record.manifest.is_empty()
                && public.len() < MAX_ANNOUNCED
            {
                public.push(record.announcement());
            }
        }
        Ok(Wire::Hello { tags, public, sync })
    }

    fn have(&self, known: &PeerSpaces, want: bool) -> Result<Option<Wire>> {
        let mut spaces = Vec::new();
        for shared in &known.shared {
            let Ok((id, record)) = self.joined(shared) else {
                continue;
            };
            // What has run out is deleted before anything is offered.
            self.items(&id, &record)?;
            let mut held = self.stored(&id)?;
            // The newest, if there are more than can be offered at once.
            held.sort_by_key(|(_, arrival, _)| std::cmp::Reverse(*arrival));
            spaces.push(HaveSpace {
                id: shared.clone(),
                ids: held
                    .iter()
                    .take(MAX_OFFERED)
                    .map(|(item, _, _)| hexcode::encode(item))
                    .collect(),
                has_manifest: !record.manifest.is_empty(),
            });
        }
        Ok((!spaces.is_empty()).then_some(Wire::Have { spaces, want }))
    }

    /// Takes in one sync message from the device whose key is `from`.
    /// `may_invite` says whether this person's invites are welcome.
    pub fn receive(
        &self,
        from: &str,
        wire: Wire,
        known: &mut PeerSpaces,
        may_invite: bool,
    ) -> Result<Outcome> {
        let mut outcome = Outcome::default();
        match wire {
            // Only a fellow member is told, so only one is believed.
            Wire::Status { status, away } => {
                if known.shared.is_empty() {
                    return Ok(outcome);
                }
                let said = match status.as_str() {
                    "online" | "idle" | "dnd" => Some(status),
                    "offline" => None,
                    _ => return Ok(outcome),
                };
                // Away holds only while they say how they are, and only
                // with a short reason on one line.
                let away = away
                    .filter(|_| said.is_some())
                    .map(|note| note.split_whitespace().collect::<Vec<_>>().join(" "))
                    .filter(|note| note.chars().count() <= crate::chat::MAX_AWAY_CHARS);
                outcome.changed = known.status != said || known.away != away;
                known.status = said;
                known.away = away;
            }
            // Only from a member, about one of the space's voice rooms.
            Wire::Room {
                space,
                channel,
                call,
            } => {
                if known.shared.contains(&space) && self.voice_room_of(from, &space, &channel)? {
                    outcome.room = Some((space, channel, call));
                }
            }
            Wire::Typing { space, channel } => {
                if !known.shared.contains(&space) {
                    return Ok(outcome);
                }
                let Ok((id, record)) = self.joined(&space) else {
                    return Ok(outcome);
                };
                let Some(manifest) = record.manifest() else {
                    return Ok(outcome);
                };
                // Someone who could not post there now is not shown as
                // writing there.
                let items = self.items(&id, &record)?;
                if record.kind != Kind::Channel
                    && Self::may_write(from, &channel, &items, &record, &manifest)
                {
                    outcome.typing = Some((space, channel));
                }
            }
            // A public space's icon is given to anyone who asks, as the
            // space itself is announced to them. A private one's only to a
            // fellow member.
            Wire::IconWant { space, icon } => {
                let Ok(id) = space_id(&space) else {
                    return Ok(outcome);
                };
                let Some(record) = self.load(&id)? else {
                    return Ok(outcome);
                };
                if record.closed || (record.kind == Kind::Private && !known.shared.contains(&space))
                {
                    return Ok(outcome);
                }
                let held = self
                    .vault
                    .get(ICON, &id)?
                    .filter(|bytes| hexcode::encode(&Sha256::digest(bytes)) == icon);
                if let Some(bytes) = held {
                    outcome.replies.push(Wire::Icon {
                        space,
                        icon: hexcode::encode(&bytes),
                    });
                }
            }
            // Taken only if it is the picture the owner's latest word on the
            // space names, and only while this device lacks it.
            Wire::Icon { space, icon } => {
                let Ok(id) = space_id(&space) else {
                    return Ok(outcome);
                };
                let Some(record) = self.load(&id)? else {
                    return Ok(outcome);
                };
                let Some(named) = self.lacks_icon(&id, &record)? else {
                    return Ok(outcome);
                };
                let bytes = hexcode::decode(&icon).unwrap_or_default();
                if bytes.len() <= MAX_ICON_BYTES
                    && crate::chat::sound_photo(&icon)
                    && hexcode::encode(&Sha256::digest(&bytes)) == named
                {
                    self.vault.put(ICON, &id, &bytes)?;
                    outcome.changed = true;
                }
            }
            Wire::Hello { tags, public, sync } => {
                // Each space it announced, with the icon it names.
                let mut offered = BTreeMap::new();
                for announced in public.into_iter().take(MAX_ANNOUNCED) {
                    outcome.changed |= self.hear_of(&announced, Status::Nearby, None)?;
                    let said = hexcode::decode(&announced.manifest)
                        .ok()
                        .and_then(|bytes| serde_json::from_slice::<Manifest>(&bytes).ok());
                    if let Some(said) = said.filter(|said| !said.icon.is_empty()) {
                        offered.insert(said.id, said.icon);
                    }
                }
                known.tags = tags
                    .into_iter()
                    .filter(|t| hexcode::decode_exact::<16>(t).is_ok())
                    .collect();
                let before = known.shared.clone();
                // Works out the shared spaces afresh. What it returns is
                // only wanted when starting a conversation.
                self.hello(from, known, false)?;
                outcome.changed |= before != known.shared;
                // Icons this device lacks, asked of a device that should
                // have them: a fellow member, or one that announced the
                // space with that icon.
                for (id, record) in self.all()? {
                    let hex = hexcode::encode(&id);
                    let Some(icon) = self.lacks_icon(&id, &record)? else {
                        continue;
                    };
                    if known.shared.contains(&hex) || offered.get(&hex) == Some(&icon) {
                        outcome.replies.push(Wire::IconWant { space: hex, icon });
                    }
                }
                // Files the user is waiting for, from a member of the
                // same space who may have them.
                for (sha, kept) in self.shelf().waiting()? {
                    if let Some(space) = kept.spaces.iter().find(|s| known.shared.contains(*s)) {
                        outcome.replies.push(Wire::FileWant {
                            space: space.clone(),
                            file: sha,
                            from: kept.have,
                        });
                    }
                }
                if sync {
                    outcome.replies.extend(self.have(known, true)?);
                }
            }
            Wire::Have { spaces, want } => {
                for theirs in spaces {
                    if !known.shared.contains(&theirs.id) {
                        continue;
                    }
                    let Ok((id, record)) = self.joined(&theirs.id) else {
                        continue;
                    };
                    let held: HashSet<&str> = theirs.ids.iter().map(String::as_str).collect();
                    self.items(&id, &record)?;
                    let mut missing: Vec<(u64, Vec<u8>)> = self
                        .stored(&id)?
                        .into_iter()
                        .filter(|(item, _, _)| !held.contains(hexcode::encode(item).as_str()))
                        .map(|(_, arrival, sealed)| (arrival, sealed))
                        .collect();
                    missing.sort_by_key(|(arrival, _)| *arrival);
                    let lacks_manifest = !theirs.has_manifest && !record.manifest.is_empty();
                    let mut first = true;
                    let mut batches =
                        batch(missing.into_iter().map(|(_, sealed)| sealed).collect());
                    if batches.is_empty() && lacks_manifest {
                        batches.push(Vec::new());
                    }
                    for items in batches {
                        let with = (first && lacks_manifest)
                            .then(|| (record.manifest.clone(), record.signature.clone()));
                        first = false;
                        outcome.replies.push(Wire::Items {
                            space: theirs.id.clone(),
                            manifest: with.as_ref().map(|(m, _)| m.clone()),
                            signature: with.map(|(_, s)| s),
                            items: items.iter().map(|sealed| hexcode::encode(sealed)).collect(),
                        });
                    }
                }
                if want {
                    outcome.replies.extend(self.have(known, false)?);
                }
            }
            Wire::Items {
                space,
                manifest,
                signature,
                items,
            } => {
                if !known.shared.contains(&space) {
                    return Ok(outcome);
                }
                let Ok((id, mut record)) = self.joined(&space) else {
                    return Ok(outcome);
                };
                let icon_before = record.manifest().map(|m| m.icon);
                let mut fresh = Vec::new();
                if record.manifest.is_empty() {
                    // The first thing a newcomer needs: what the space is.
                    let arrived = manifest
                        .zip(signature)
                        .and_then(|(m, s)| read_manifest(&m, &s).map(|read| (m, s, read)));
                    let Some((bytes, signature, read)) = arrived else {
                        return Ok(outcome);
                    };
                    // For this space, made by who this device was told
                    // made it, and telling no other story of who it has
                    // been handed to than the one held here.
                    let fits = read.id == space
                        && read.founder() == record.owner
                        && read.kind == record.kind
                        && (extends(&read.chain, &record.chain)
                            || extends(&record.chain, &read.chain));
                    if !fits {
                        return Ok(outcome);
                    }
                    record.manifest = bytes;
                    record.signature = signature;
                    record.name = read.name;
                    record.description = read.description;
                    if read.chain.len() > record.chain.len() {
                        record.chain = read.chain;
                    }
                    outcome.changed = true;
                    // Now the newcomer can say "I am here". That goes back
                    // to whoever let them in, and on to anyone else.
                    if let Some(joined) = self.announce_membership(&id, &mut record)? {
                        outcome
                            .replies
                            .extend(Self::push(&space, std::slice::from_ref(&joined)));
                        fresh.push(joined);
                    }
                }
                let Some(known_manifest) = record.manifest() else {
                    return Ok(outcome);
                };
                // A space this device had been told was deleted may be put
                // back by something in the middle of what arrived. What
                // came before it was turned away, so it is gone through a
                // second time.
                let was_deleted = record.closed;
                for round in 0..2 {
                    if round == 1 && !(was_deleted && !record.closed) {
                        break;
                    }
                    for item in &items {
                        let Ok(sealed) = hexcode::decode(item) else {
                            continue;
                        };
                        if self.take(&id, &mut record, &known_manifest, &sealed)? {
                            fresh.push(sealed);
                        }
                    }
                }
                // If what arrived hands the space to the user, they sign
                // for it from here on. That goes back to whoever brought
                // the news, and on to everyone else.
                if let Some(signed) = self.take_up(&id, &mut record)? {
                    outcome
                        .replies
                        .extend(Self::push(&space, std::slice::from_ref(&signed)));
                    fresh.push(signed);
                }
                // A new icon is asked of whoever brought the news of it.
                if record.manifest().map(|m| m.icon) != icon_before {
                    if let Some(icon) = self.lacks_icon(&id, &record)? {
                        outcome.replies.push(Wire::IconWant {
                            space: space.clone(),
                            icon,
                        });
                    }
                }
                outcome.changed |= !fresh.is_empty();
                self.save(&id, &record)?;
                // If what arrived says the owner has removed the user, the
                // space goes from this device.
                if !fresh.is_empty() {
                    let gone = {
                        let items = self.items(&id, &record)?;
                        let manifest = record.manifest().unwrap_or(known_manifest);
                        Standing::of(&items, &record, &manifest)
                            .removed
                            .contains_key(self.my_key().as_str())
                    };
                    if gone {
                        self.forget(&id)?;
                        known.shared.remove(&space);
                    }
                    outcome.fresh.push((space, fresh));
                }
            }
            Wire::Rekey { space, epoch, key } => {
                let Ok((id, mut record)) = self.joined(&space) else {
                    return Ok(outcome);
                };
                // Only the owner changes the key, and only a private space
                // has one worth changing.
                let sound = from == record.owner_now()
                    && record.kind == Kind::Private
                    && hexcode::decode_exact::<32>(&key).is_ok()
                    && key != record.key
                    && !record.old_keys.contains(&key);
                if !sound {
                    return Ok(outcome);
                }
                if epoch > record.epoch {
                    record
                        .old_keys
                        .insert(0, std::mem::replace(&mut record.key, key));
                    record.epoch = epoch;
                    outcome.rekeyed = true;
                } else {
                    // An earlier change arriving late. Kept, to open what
                    // was written under it.
                    record.old_keys.push(key);
                }
                self.save(&id, &record)?;
                outcome.changed = true;
            }
            // Only to a device that shares the space, and only a file one
            // of the space's posts carries.
            Wire::FileWant { space, file, from } => {
                if known.shared.contains(&space) && self.joined(&space).is_ok() {
                    let pieces = self.shelf().serve(&file, &space, from)?;
                    if !pieces.is_empty() {
                        outcome.replies.push(Wire::FilePieces {
                            space,
                            file,
                            from,
                            pieces: pieces.iter().map(|piece| hexcode::encode(piece)).collect(),
                        });
                    }
                }
            }
            Wire::FilePieces {
                space,
                file,
                from,
                pieces,
            } => {
                if !known.shared.contains(&space) || pieces.len() as u64 > shelf::PER_ANSWER {
                    return Ok(outcome);
                }
                let Some(pieces) = pieces
                    .iter()
                    .map(|piece| hexcode::decode(piece).ok())
                    .collect::<Option<Vec<Vec<u8>>>>()
                else {
                    return Ok(outcome);
                };
                match self.shelf().take(&file, from, &pieces)? {
                    Taken::More(next) => {
                        outcome.replies.push(Wire::FileWant {
                            space,
                            file,
                            from: next,
                        });
                        outcome.changed = true;
                    }
                    Taken::Done | Taken::Failed => outcome.changed = true,
                    Taken::Ignored => {}
                }
            }
            Wire::Invite { space } => {
                if may_invite {
                    outcome.changed = self.hear_of(&space, Status::Invited, Some(from))?;
                }
            }
        }
        Ok(outcome)
    }

    /// Records a space someone has told this device about, if what they
    /// said holds together. Never touches a space the user is already in.
    fn hear_of(&self, told: &Announcement, status: Status, from: Option<&str>) -> Result<bool> {
        let Some(manifest) = read_manifest(&told.manifest, &told.signature) else {
            return Ok(false);
        };
        if hexcode::decode_exact::<32>(&told.key).is_err() {
            return Ok(false);
        }
        // A private space is never something to be told about in passing.
        if status == Status::Nearby && manifest.kind == Kind::Private {
            return Ok(false);
        }
        let id = space_id(&manifest.id)?;
        match self.load(&id)? {
            Some(known) if known.status == Status::Joined => return Ok(false),
            // An invite outranks having merely seen the space nearby.
            Some(known) if known.status == Status::Invited && status == Status::Nearby => {
                return Ok(false)
            }
            _ => {}
        }
        let record = Record {
            key: told.key.clone(),
            owner: manifest.founder().to_string(),
            status,
            name: manifest.name.trim().to_string(),
            kind: manifest.kind,
            description: manifest.description.clone(),
            manifest: told.manifest.clone(),
            signature: told.signature.clone(),
            invited_by: from.map(str::to_string),
            next_arrival: 0,
            read: BTreeMap::new(),
            joined_at: 0,
            clock: 0,
            muted: false,
            old_keys: Vec::new(),
            epoch: 0,
            closed: false,
            nick: None,
            chain: manifest.chain.clone(),
        };
        self.save(&id, &record)?;
        Ok(true)
    }

    /// Wraps sealed items for sending to a member in range.
    pub fn push(space: &str, items: &[Vec<u8>]) -> Vec<Wire> {
        batch(items.to_vec())
            .into_iter()
            .map(|items| Wire::Items {
                space: space.to_string(),
                manifest: None,
                signature: None,
                items: items.iter().map(|sealed| hexcode::encode(sealed)).collect(),
            })
            .collect()
    }
}

/// Splits items into groups small enough to send.
fn batch(items: Vec<Vec<u8>>) -> Vec<Vec<Vec<u8>>> {
    let mut batches: Vec<Vec<Vec<u8>>> = Vec::new();
    let mut size = 0;
    for item in items {
        // Hex doubles it.
        let weight = item.len() * 2;
        if batches.is_empty() || size + weight > MAX_BATCH_BYTES {
            batches.push(Vec::new());
            size = 0;
        }
        size += weight;
        batches.last_mut().expect("one was just pushed").push(item);
    }
    batches
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The same list is in app/test/link_rule_test.dart: the app and the
    /// core must agree on what is a link.
    #[test]
    fn a_link_is_found_in_every_form_it_can_be_written() {
        for link in [
            "look: HTTPS://example.com/x",
            "http://192.168.4.1/setup",
            "ftp://files.example.org",
            "at www.example.com",
            "WWW.EXAMPLE.COM",
            "example.com",
            "go to maps.example.org/trail now",
            "(example.com)",
            "[the map](example.com)",
            "[the map](https://example.com/map)",
            "<https://example.com>",
            "shop.co.uk!",
            "EVIL.COM",
            "пример.рф.xn--p1ai",
            "notes.zip",
            "join dnet:space/0102",
            "ask me dnet:invite/abcd",
            "x.io",
        ] {
            assert!(has_link(link), "{link}");
        }
        for plain in [
            "no link here",
            "e.g. this, i.e. that",
            "U.S.A. and Ph.D.",
            "at 3.14 or v1.2.3",
            "wait...what",
            "home.It was late",
            "St.Ives",
            "write to asha@example.com",
            "photo.jpg and file.txt",
            "a smile :// and ://x",
            "",
        ] {
            assert!(!has_link(plain), "{plain}");
        }
        assert!(post_has_link(
            "Where?",
            &["here".into(), "example.com".into()]
        ));
        assert!(!post_has_link("Where?", &["here".into(), "there".into()]));
    }

    fn person() -> (tempfile::TempDir, Vault, IdentitySecret) {
        let dir = tempfile::tempdir().unwrap();
        let vault = Vault::open(dir.path(), &[7u8; 32]).unwrap();
        (dir, vault, IdentitySecret::generate().unwrap())
    }

    fn spaces<'a>(vault: &'a Vault, me: &'a IdentitySecret, name: &'a str) -> Spaces<'a> {
        Spaces {
            vault,
            me,
            my_name: name,
            my_photo: None,
            files: Path::new("unit-test-files-are-never-written"),
        }
    }

    /// Asha's public space, and the announcement another device would hear.
    fn announced(asha: &Spaces) -> (String, Announcement) {
        let id = asha.create("Open Radio", "public", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let record = asha.load(&space_id(&id).unwrap()).unwrap().unwrap();
        (id, record.announcement())
    }

    fn names(who: &Spaces, list: &str) -> Vec<String> {
        who.list(std::iter::empty()).unwrap()[list]
            .as_array()
            .unwrap()
            .iter()
            .map(|s| s["name"].as_str().unwrap().to_string())
            .collect()
    }

    #[test]
    fn an_honest_announcement_is_listed_as_nearby() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, noor) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Noor"));
        let (_, told) = announced(&asha);
        assert!(noor.hear_of(&told, Status::Nearby, None).unwrap());
        assert_eq!(names(&noor, "nearby"), ["Open Radio"]);
    }

    #[test]
    fn an_announcement_someone_altered_is_not_listed() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, noor) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Noor"));
        let (_, honest) = announced(&asha);
        // The same space, renamed by someone who is not its owner.
        let renamed = String::from_utf8(hexcode::decode(&honest.manifest).unwrap())
            .unwrap()
            .replace("Open Radio", "Free Money");
        let forged = Announcement {
            manifest: hexcode::encode(renamed.as_bytes()),
            ..honest
        };
        assert!(!noor.hear_of(&forged, Status::Nearby, None).unwrap());
        assert!(names(&noor, "nearby").is_empty());
    }

    #[test]
    fn nobody_can_take_over_a_space_by_signing_it_themselves() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, _v3, eve) = person();
        let (asha, noor) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Noor"));
        let (id, honest) = announced(&asha);
        let link = asha.link(&id).unwrap();
        noor.join_link(&link).unwrap();

        // Eve rewrites the manifest with herself as owner and signs it
        // properly with her own key.
        let mut manifest: Manifest =
            serde_json::from_slice(&hexcode::decode(&honest.manifest).unwrap()).unwrap();
        manifest.owner = hexcode::encode(&eve.signing_public());
        manifest.name = "Eve's now".to_string();
        let bytes = serde_json::to_vec(&manifest).unwrap();
        let wire = Wire::Items {
            space: id.clone(),
            manifest: Some(hexcode::encode(&bytes)),
            signature: Some(hexcode::encode(&eve.sign(&signed_manifest(&bytes)))),
            items: vec![],
        };
        let mut known = PeerSpaces::default();
        known.shared.insert(id.clone());
        noor.receive(
            &hexcode::encode(&eve.signing_public()),
            wire,
            &mut known,
            false,
        )
        .unwrap();
        // Noor knows the owner from the invite, and it is not Eve.
        assert_eq!(names(&noor, "joined"), ["Open Radio"]);
        assert_eq!(
            noor.list(std::iter::empty()).unwrap()["joined"][0]["ready"],
            false
        );
    }

    #[test]
    fn an_invite_is_taken_only_from_someone_allowed_to_invite() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, noor) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Noor"));
        let id = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let from = hexcode::encode(&k1.signing_public());
        let invite = || asha.invite(&id).unwrap();

        let refused = noor
            .receive(&from, invite(), &mut PeerSpaces::default(), false)
            .unwrap();
        assert!(!refused.changed);
        assert!(names(&noor, "invited").is_empty());

        let welcome = noor
            .receive(&from, invite(), &mut PeerSpaces::default(), true)
            .unwrap();
        assert!(welcome.changed);
        assert_eq!(names(&noor, "invited"), ["Trek Team"]);
        // Invited is not joined: nothing is shared or synced yet.
        assert!(names(&noor, "joined").is_empty());
    }

    #[test]
    fn items_for_a_space_the_sender_has_not_shown_a_tag_for_are_dropped() {
        // Knowing a space's number is not enough to write into it.
        let (_d1, v1, k1) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id_hex = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let id = space_id(&id_hex).unwrap();
        let record = asha.load(&id).unwrap().unwrap();
        let channel = record.manifest().unwrap().channels[2].id.clone();
        let event = Event::Post {
            id: "00".repeat(16),
            channel: channel.clone(),
            body: "hi".into(),
            sent_at: 1,
            reply_to: None,
            options: vec![],
            name: String::new(),
            mentions: vec![],
            lasts: 0,
            file: None,
            everyone: false,
            roles: vec![],
            forwarded: false,
            location: None,
            sticker: None,
        };
        let item = asha.seal_item(&id, &record.key().unwrap(), &event).unwrap();
        let wire = || Wire::Items {
            space: id_hex.clone(),
            manifest: None,
            signature: None,
            items: vec![hexcode::encode(&item)],
        };

        let mut stranger = PeerSpaces::default();
        asha.receive("aa", wire(), &mut stranger, false).unwrap();
        assert_eq!(
            asha.channel(&id_hex, &channel).unwrap()["messages"]
                .as_array()
                .unwrap()
                .len(),
            0
        );

        let mut member = PeerSpaces::default();
        member.shared.insert(id_hex.clone());
        asha.receive("aa", wire(), &mut member, false).unwrap();
        assert_eq!(
            asha.channel(&id_hex, &channel).unwrap()["messages"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn a_post_by_someone_who_does_not_run_the_space_is_not_shown_where_only_they_write() {
        // Mira holds the key and signs honestly as herself. Her own app
        // would have refused; this is what Asha's device does with it. It
        // is kept, because Mira may turn out to have been made an admin by
        // something that has not arrived yet, and it is not shown.
        let (_d1, v1, k1) = person();
        let (_d2, _v2, mira) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id_hex = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let id = space_id(&id_hex).unwrap();
        let mut record = asha.load(&id).unwrap().unwrap();
        let manifest = record.manifest().unwrap();
        let sealed_by_mira = |channel: &str| {
            let event = serde_json::to_vec(&Event::Post {
                id: hexcode::encode(random_bytes::<16>().unwrap().as_slice()),
                channel: channel.to_string(),
                body: "from Mira".into(),
                sent_at: 1,
                reply_to: None,
                options: vec![],
                name: String::new(),
                mentions: vec![],
                lasts: 0,
                file: None,
                everyone: false,
                roles: vec![],
                forwarded: false,
                location: None,
                sticker: None,
            })
            .unwrap();
            let mut inner = mira.signing_public().to_vec();
            inner.extend_from_slice(&mira.sign(&signed_item(&id, &event)));
            inner.extend_from_slice(&event);
            seal::seal(
                &derive::<32>(&record.key().unwrap(), &[ITEM_KEY_CONTEXT]),
                &id,
                &inner,
            )
            .unwrap()
        };
        let (announcements, general) = (
            manifest.channels[0].id.clone(),
            manifest.channels[2].id.clone(),
        );
        let (in_info, in_general) = (sealed_by_mira(&announcements), sealed_by_mira(&general));
        assert!(asha.take(&id, &mut record, &manifest, &in_info).unwrap());
        assert!(asha.take(&id, &mut record, &manifest, &in_general).unwrap());
        asha.save(&id, &record).unwrap();
        let said = |channel: &str| {
            asha.channel(&id_hex, channel).unwrap()["messages"]
                .as_array()
                .unwrap()
                .len()
        };
        assert_eq!(said(&announcements), 0);
        assert_eq!(said(&general), 1);
        assert_eq!(
            asha.list(std::iter::empty()).unwrap()["joined"][0]["channels"][0]["unread"],
            0
        );
    }

    #[test]
    fn a_pin_or_a_deletion_by_someone_who_does_not_run_the_space_counts_for_nothing() {
        let (_d1, v1, k1) = person();
        let (_d2, _v2, mira) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id_hex = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let id = space_id(&id_hex).unwrap();
        let general = asha
            .load(&id)
            .unwrap()
            .unwrap()
            .manifest()
            .unwrap()
            .channels[2]
            .id
            .clone();
        let (post, _) = asha
            .post(&id_hex, &general, "Start is at 6:00.", None, vec![])
            .unwrap();

        let mut record = asha.load(&id).unwrap().unwrap();
        let manifest = record.manifest().unwrap();
        for event in [
            Event::Pin {
                target: post.clone(),
                on: true,
                sent_at: record.clock + 1,
            },
            Event::Delete {
                target: post.clone(),
                sent_at: record.clock + 2,
            },
        ] {
            let event = serde_json::to_vec(&event).unwrap();
            let mut inner = mira.signing_public().to_vec();
            inner.extend_from_slice(&mira.sign(&signed_item(&id, &event)));
            inner.extend_from_slice(&event);
            let sealed = seal::seal(
                &derive::<32>(&record.key().unwrap(), &[ITEM_KEY_CONTEXT]),
                &id,
                &inner,
            )
            .unwrap();
            assert!(asha.take(&id, &mut record, &manifest, &sealed).unwrap());
        }
        asha.save(&id, &record).unwrap();

        let shown = asha.channel(&id_hex, &general).unwrap();
        assert_eq!(
            shown["messages"].as_array().unwrap().len(),
            1,
            "still there"
        );
        assert!(shown["pinned"].is_null());
    }

    #[test]
    fn a_new_key_is_taken_only_from_the_owner() {
        let (_d1, v1, k1) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id_hex = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let id = space_id(&id_hex).unwrap();
        let before = asha.load(&id).unwrap().unwrap().key;
        let rekey = || Wire::Rekey {
            space: id_hex.clone(),
            epoch: 9,
            key: "ab".repeat(32),
        };

        let stranger = "cd".repeat(32);
        let outcome = asha
            .receive(&stranger, rekey(), &mut PeerSpaces::default(), true)
            .unwrap();
        assert!(!outcome.changed);
        assert_eq!(asha.load(&id).unwrap().unwrap().key, before);

        let owner = asha.my_key();
        let outcome = asha
            .receive(&owner, rekey(), &mut PeerSpaces::default(), false)
            .unwrap();
        assert!(outcome.rekeyed);
        let after = asha.load(&id).unwrap().unwrap();
        assert_eq!(after.key, "ab".repeat(32));
        assert_eq!(
            after.old_keys,
            [before],
            "the old key still opens what was said under it"
        );
    }

    #[test]
    fn a_member_never_tells_passers_by_about_a_private_space() {
        // What is announced includes the space's key. For a private space
        // that would hand the key to anyone in range, whatever an honest
        // receiver then did with it.
        let (_d1, v1, k1) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let private = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        asha.create("Open Radio", "public", "").unwrap();
        asha.create("City Signal", "channel", "").unwrap();
        let secret = asha
            .load(&space_id(&private).unwrap())
            .unwrap()
            .unwrap()
            .key;

        let Wire::Hello { tags, public, .. } = asha
            .hello(&"ab".repeat(32), &mut PeerSpaces::default(), true)
            .unwrap()
        else {
            panic!("hello must be a hello");
        };
        assert_eq!(
            tags.len(),
            3,
            "a tag for each space, readable only by members"
        );
        let told: Vec<String> = public
            .iter()
            .map(|a| read_manifest(&a.manifest, &a.signature).unwrap().name)
            .collect();
        assert_eq!(told.len(), 2);
        assert!(
            told.contains(&"Open Radio".to_string()) && told.contains(&"City Signal".to_string())
        );
        let sent = serde_json::to_string(&Wire::Hello {
            tags,
            public,
            sync: true,
        })
        .unwrap();
        assert!(
            !sent.contains(&secret),
            "the private space's key must not leave"
        );
        assert!(!sent.contains(&private), "nor its number");
        assert!(!sent.contains("Trek Team"), "nor its name");
    }

    #[test]
    fn a_private_space_cannot_be_announced_to_passers_by() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, noor) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Noor"));
        let id = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let told = asha
            .load(&space_id(&id).unwrap())
            .unwrap()
            .unwrap()
            .announcement();
        assert!(!noor.hear_of(&told, Status::Nearby, None).unwrap());
    }

    #[test]
    fn an_item_sealed_with_another_key_is_refused() {
        let (_d1, v1, k1) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id_hex = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let id = space_id(&id_hex).unwrap();
        let mut record = asha.load(&id).unwrap().unwrap();
        let manifest = record.manifest().unwrap();
        let channel = manifest.channels[2].id.clone();
        let event = Event::Post {
            id: "00".repeat(16),
            channel,
            body: "hi".into(),
            sent_at: 1,
            reply_to: None,
            options: vec![],
            name: String::new(),
            mentions: vec![],
            lasts: 0,
            file: None,
            everyone: false,
            roles: vec![],
            forwarded: false,
            location: None,
            sticker: None,
        };

        let wrong_key = asha.seal_item(&id, &[9u8; 32], &event).unwrap();
        assert!(!asha.take(&id, &mut record, &manifest, &wrong_key).unwrap());
        // Sealed for a different space, even with the right key.
        let wrong_space = asha
            .seal_item(&[1u8; 16], &record.key().unwrap(), &event)
            .unwrap();
        assert!(!asha
            .take(&id, &mut record, &manifest, &wrong_space)
            .unwrap());
        let honest = asha.seal_item(&id, &record.key().unwrap(), &event).unwrap();
        assert!(asha.take(&id, &mut record, &manifest, &honest).unwrap());
        assert!(
            !asha.take(&id, &mut record, &manifest, &honest).unwrap(),
            "the same item twice is one item"
        );
    }

    #[test]
    fn nobody_can_write_under_someone_elses_name() {
        // Eve holds the space key, so she can seal. She cannot sign as Asha.
        let (_d1, v1, k1) = person();
        let (_d3, _v3, eve) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id_hex = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let id = space_id(&id_hex).unwrap();
        let mut record = asha.load(&id).unwrap().unwrap();
        let manifest = record.manifest().unwrap();
        let event = serde_json::to_vec(&Event::Post {
            id: "00".repeat(16),
            channel: manifest.channels[2].id.clone(),
            body: "I said this".into(),
            sent_at: 1,
            reply_to: None,
            options: vec![],
            name: String::new(),
            mentions: vec![],
            lasts: 0,
            file: None,
            everyone: false,
            roles: vec![],
            forwarded: false,
            location: None,
            sticker: None,
        })
        .unwrap();
        let mut inner = k1.signing_public().to_vec();
        inner.extend_from_slice(&eve.sign(&signed_item(&id, &event)));
        inner.extend_from_slice(&event);
        let forged = seal::seal(
            &derive::<32>(&record.key().unwrap(), &[ITEM_KEY_CONTEXT]),
            &id,
            &inner,
        )
        .unwrap();
        assert!(!asha.take(&id, &mut record, &manifest, &forged).unwrap());
    }

    #[test]
    fn a_tag_means_nothing_to_someone_without_the_key() {
        let space = [3u8; 16];
        let (asha, mira, eve) = ([1u8; 32], [2u8; 32], [5u8; 32]);
        let shown = tag(&[7u8; 32], &space, &asha, &mira);
        assert_eq!(shown, tag(&[7u8; 32], &space, &asha, &mira));
        assert_ne!(shown, tag(&[8u8; 32], &space, &asha, &mira), "another key");
        assert_ne!(
            shown,
            tag(&[7u8; 32], &space, &asha, &eve),
            "shown to someone else"
        );
        assert_ne!(
            shown,
            tag(&[7u8; 32], &space, &mira, &asha),
            "the other direction"
        );
    }

    #[test]
    fn a_vote_for_a_choice_the_poll_does_not_have_counts_for_nothing() {
        // The app refuses to cast one. A changed app could still send it.
        let (_d1, v1, k1) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id_hex = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let id = space_id(&id_hex).unwrap();
        let mut record = asha.load(&id).unwrap().unwrap();
        let channel = record.manifest().unwrap().channels[2].id.clone();
        let (poll, _) = asha
            .post(
                &id_hex,
                &channel,
                "Start time?",
                None,
                vec!["5:30".into(), "6:00".into()],
            )
            .unwrap();

        let mut record_now = asha.load(&id).unwrap().unwrap();
        record.clock = record_now.clock;
        let vote = Event::Vote {
            target: poll,
            choice: 5,
            sent_at: Spaces::stamp(&mut record_now),
        };
        asha.write(&id, &mut record_now, &vote).unwrap();

        let shown = asha.channel(&id_hex, &channel).unwrap()["messages"][0]["poll"].clone();
        assert_eq!(
            shown,
            json!({"options": [{"text": "5:30", "votes": 0}, {"text": "6:00", "votes": 0}], "mine": null})
        );
    }

    #[test]
    fn what_breaks_a_channels_rules_is_shown_to_nobody_even_from_a_changed_app() {
        // Mira's own app would refuse to send these. This is what every
        // other device does if a changed app sends them anyway.
        let (_d1, v1, k1) = person();
        let (_d2, _v2, mira) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id_hex = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let id = space_id(&id_hex).unwrap();
        let general = asha
            .load(&id)
            .unwrap()
            .unwrap()
            .manifest()
            .unwrap()
            .channels[2]
            .id
            .clone();
        asha.channel_rules(
            &id_hex,
            &general,
            ChannelRules {
                slow: Some(60),
                no_links: Some(true),
                ..Default::default()
            },
        )
        .unwrap();

        let mut record = asha.load(&id).unwrap().unwrap();
        let manifest = record.manifest().unwrap();
        let start = record.clock + 1_000;
        let from_mira = [
            (start, "first"),
            (start + 5_000, "too soon"),
            (start + 61_000, "after a minute"),
            (start + 200_000, "a link: https://example.com"),
        ];
        for (at, body) in from_mira {
            let event = serde_json::to_vec(&Event::Post {
                id: hexcode::encode(random_bytes::<16>().unwrap().as_slice()),
                channel: general.clone(),
                body: body.into(),
                sent_at: at,
                reply_to: None,
                options: vec![],
                name: String::new(),
                mentions: vec![],
                lasts: 0,
                file: None,
                everyone: false,
                roles: vec![],
                forwarded: false,
                location: None,
                sticker: None,
            })
            .unwrap();
            let mut inner = mira.signing_public().to_vec();
            inner.extend_from_slice(&mira.sign(&signed_item(&id, &event)));
            inner.extend_from_slice(&event);
            let sealed = seal::seal(
                &derive::<32>(&record.key().unwrap(), &[ITEM_KEY_CONTEXT]),
                &id,
                &inner,
            )
            .unwrap();
            assert!(asha.take(&id, &mut record, &manifest, &sealed).unwrap());
        }
        asha.save(&id, &record).unwrap();

        let shown: Vec<String> = asha.channel(&id_hex, &general).unwrap()["messages"]
            .as_array()
            .unwrap()
            .iter()
            .map(|m| m["body"].as_str().unwrap().to_string())
            .collect();
        assert_eq!(shown, ["first", "after a minute"]);
    }

    #[test]
    fn a_change_from_a_changed_app_counts_only_if_an_honest_one_would_have_made_it() {
        // Each of these is refused by the app that would send it. This is
        // what every other device does if a changed app sends it anyway.
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let space = space_with(&asha, &[&mira]);
        let id = space_id(&space).unwrap();
        let general = asha
            .load(&id)
            .unwrap()
            .unwrap()
            .manifest()
            .unwrap()
            .channels[2]
            .id
            .clone();
        let (water, sealed) = mira
            .post(&space, &general, "Bring water.", None, vec![])
            .unwrap();
        hand(&asha, &mira.my_key(), &space, None, vec![sealed]);
        let (asked, sealed) = mira
            .post(
                &space,
                &general,
                "Which trail?",
                None,
                vec!["North".into(), "South".into()],
            )
            .unwrap();
        hand(&asha, &mira.my_key(), &space, None, vec![sealed]);
        let rule = asha
            .channel_rules(
                &space,
                &general,
                ChannelRules {
                    no_links: Some(true),
                    ..Default::default()
                },
            )
            .unwrap();
        hand(&mira, &asha.my_key(), &space, None, vec![rule]);

        let later = asha.load(&id).unwrap().unwrap().clock + 1_000;
        let change = |target: &str, body: &str, sent_at: u64| Event::Edit {
            target: target.to_string(),
            body: body.to_string(),
            sent_at,
            until: 0,
        };
        // The owner, changing someone else's words.
        hand(
            &mira,
            &asha.my_key(),
            &space,
            None,
            vec![forged(&asha, &space, &change(&water, "Bring beer.", later))],
        );
        // Mira, changing a poll's question after the votes, and putting a
        // link where links are not allowed.
        hand(
            &asha,
            &mira.my_key(),
            &space,
            None,
            vec![
                forged(&mira, &space, &change(&asked, "Which day?", later)),
                forged(
                    &mira,
                    &space,
                    &change(&water, "see www.example.com", later + 1),
                ),
            ],
        );

        for who in [&asha, &mira] {
            let messages = who.channel(&space, &general).unwrap()["messages"].clone();
            let bodies: Vec<&str> = messages
                .as_array()
                .unwrap()
                .iter()
                .map(|m| m["body"].as_str().unwrap())
                .collect();
            assert_eq!(bodies, ["Bring water.", "Which trail?"]);
            assert_eq!(messages[0]["edited"], false);
        }
    }

    /// A link for Asha's space that ran out a minute ago.
    fn run_out(asha: &Spaces) -> (String, String) {
        let space = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let link = asha.link_until(&space, Some(now() - 60_000)).unwrap();
        (space, link)
    }

    #[test]
    fn a_link_that_has_run_out_is_refused_and_says_so() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, noor) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Noor"));
        let (_, link) = run_out(&asha);
        assert_eq!(noor.check_link(&link).unwrap()["expired"], true);
        let refused = noor.join_link(&link).unwrap_err();
        assert!(refused.to_string().contains("expired"), "{refused}");
        assert!(names(&noor, "joined").is_empty());
    }

    #[test]
    fn nobody_passing_a_link_on_can_make_it_last_longer() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, noor) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Noor"));
        let (_, link) = run_out(&asha);
        // The end time sits just after the kind byte. Push it far ahead.
        let mut bytes = hexcode::decode(link.strip_prefix(LINK_PREFIX).unwrap()).unwrap();
        bytes[82..90].copy_from_slice(&u64::MAX.to_be_bytes());
        let stretched = format!("{LINK_PREFIX}{}", hexcode::encode(&bytes));
        assert!(noor.check_link(&stretched).is_err());
        assert!(noor.join_link(&stretched).is_err());
        assert!(names(&noor, "joined").is_empty());
    }

    /// Asha and Mira in a space, and the id of its general channel.
    fn pair_with_general<'a>(asha: &Spaces<'a>, mira: &Spaces<'a>) -> (String, String) {
        let space = space_with(asha, &[mira]);
        let general = asha
            .load(&space_id(&space).unwrap())
            .unwrap()
            .unwrap()
            .manifest()
            .unwrap()
            .channels[2]
            .id
            .clone();
        (space, general)
    }

    fn said_in(who: &Spaces, space: &str, channel: &str) -> Vec<String> {
        who.channel(space, channel).unwrap()["messages"]
            .as_array()
            .unwrap()
            .iter()
            .map(|m| m["body"].as_str().unwrap().to_string())
            .collect()
    }

    fn lasting(channel: &str, body: &str, sent_at: u64, lasts: u32) -> Event {
        Event::Post {
            id: hexcode::encode(random_bytes::<16>().unwrap().as_slice()),
            channel: channel.to_string(),
            body: body.into(),
            sent_at,
            reply_to: None,
            options: vec![],
            name: String::new(),
            mentions: vec![],
            lasts,
            file: None,
            everyone: false,
            roles: vec![],
            forwarded: false,
            location: None,
            sticker: None,
        }
    }

    #[test]
    fn a_message_that_has_run_out_is_deleted_with_its_changes_and_not_taken_back() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let (space, general) = pair_with_general(&asha, &mira);
        let id = space_id(&space).unwrap();
        let hour = 3_600_000;
        let held = asha.stored(&id).unwrap().len();

        let ran_out = lasting(&general, "ran out", now() - hour - 1_000, 3_600);
        let nearly = lasting(&general, "nearly", now() - hour + 400, 3_600);
        let Event::Post { id: target, .. } = &nearly else {
            unreachable!()
        };
        let change = Event::Edit {
            target: target.clone(),
            body: "nearly gone".into(),
            sent_at: now() - hour + 500,
            until: now() + 400,
        };
        let nearly = forged(&mira, &space, &nearly);
        hand(
            &asha,
            &mira.my_key(),
            &space,
            None,
            vec![
                forged(&mira, &space, &ran_out),
                nearly.clone(),
                forged(&mira, &space, &change),
            ],
        );
        // What had run out on arrival was never kept.
        assert_eq!(said_in(&asha, &space, &general), ["nearly gone"]);
        assert_eq!(asha.stored(&id).unwrap().len(), held + 2);

        std::thread::sleep(std::time::Duration::from_millis(600));
        assert!(said_in(&asha, &space, &general).is_empty());
        assert_eq!(
            asha.stored(&id).unwrap().len(),
            held,
            "gone from the device, the change with it"
        );
        // A device that still holds it cannot hand it back.
        hand(&asha, &mira.my_key(), &space, None, vec![nearly]);
        assert_eq!(asha.stored(&id).unwrap().len(), held);
    }

    #[test]
    fn a_message_from_a_changed_app_goes_when_the_channel_says_whatever_it_says() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let (space, general) = pair_with_general(&asha, &mira);
        let rule = asha
            .channel_rules(
                &space,
                &general,
                ChannelRules {
                    disappear: Some(3_600),
                    ..Default::default()
                },
            )
            .unwrap();
        hand(&mira, &asha.my_key(), &space, None, vec![rule]);
        let sent_at = asha
            .load(&space_id(&space).unwrap())
            .unwrap()
            .unwrap()
            .clock
            + 1_000;
        for lasts in [0, 604_800] {
            hand(
                &asha,
                &mira.my_key(),
                &space,
                None,
                vec![forged(
                    &mira,
                    &space,
                    &lasting(&general, "forever", sent_at, lasts),
                )],
            );
        }
        for shown in asha.channel(&space, &general).unwrap()["messages"]
            .as_array()
            .unwrap()
        {
            assert_eq!(shown["ends_at"].as_u64(), Some(sent_at + 3_600_000));
        }
    }

    #[test]
    fn a_banned_word_or_a_message_too_long_from_a_changed_app_is_shown_to_nobody() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let (space, general) = pair_with_general(&asha, &mira);
        let rules = asha
            .channel_rules(
                &space,
                &general,
                ChannelRules {
                    max_len: Some(200),
                    ..Default::default()
                },
            )
            .unwrap();
        let words = asha.banned_words(&space, vec!["spoiler".into()]).unwrap();
        hand(&mira, &asha.my_key(), &space, None, vec![rules, words]);
        let sent_at = asha
            .load(&space_id(&space).unwrap())
            .unwrap()
            .unwrap()
            .clock
            + 1_000;
        let long = "a".repeat(201);
        for (n, body) in ["the SPOILER is", long.as_str(), "fine"]
            .into_iter()
            .enumerate()
        {
            hand(
                &asha,
                &mira.my_key(),
                &space,
                None,
                vec![forged(
                    &mira,
                    &space,
                    &lasting(&general, body, sent_at + n as u64, 0),
                )],
            );
        }
        assert_eq!(said_in(&asha, &space, &general), ["fine"]);
    }

    #[test]
    fn repeats_and_floods_from_a_changed_app_are_shown_to_nobody() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let (space, general) = pair_with_general(&asha, &mira);
        let sent_at = asha
            .load(&space_id(&space).unwrap())
            .unwrap()
            .unwrap()
            .clock
            + 1_000;
        let mut bodies: Vec<String> = vec!["buy now".into(), "BUY NOW!".into()];
        bodies.extend((0..25).map(|n| format!("message {n}")));
        for (n, body) in bodies.iter().enumerate() {
            hand(
                &asha,
                &mira.my_key(),
                &space,
                None,
                vec![forged(
                    &mira,
                    &space,
                    &lasting(&general, body, sent_at + n as u64, 0),
                )],
            );
        }
        let shown = said_in(&asha, &space, &general);
        // The repeat is gone, and only twenty fit in the minute.
        assert_eq!(shown.len(), MAX_PER_MINUTE);
        assert_eq!(shown[0], "buy now");
        assert!(!shown.contains(&"BUY NOW!".to_string()));
    }

    #[test]
    fn calling_on_everyone_from_a_changed_app_counts_only_from_someone_who_may() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let (space, general) = pair_with_general(&asha, &mira);
        let at = asha
            .load(&space_id(&space).unwrap())
            .unwrap()
            .unwrap()
            .clock
            + 1_000;
        // Mira's own app refuses to send this; a changed one could.
        let mut shout = lasting(&general, "look at me", at, 0);
        if let Event::Post { everyone, .. } = &mut shout {
            *everyone = true;
        }
        hand(
            &asha,
            &mira.my_key(),
            &space,
            None,
            vec![forged(&mira, &space, &shout)],
        );
        let seen = asha.channel(&space, &general).unwrap()["messages"][0].clone();
        assert_eq!(seen["body"], "look at me", "the words are still shown");
        assert_eq!(seen["everyone"], false);
        assert_eq!(seen["mentions_me"], false);
        let listed = asha.list(std::iter::empty()).unwrap();
        let channel = listed["joined"][0]["channels"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["id"] == general.as_str())
            .unwrap()
            .clone();
        assert_eq!(channel["mentions"], 0);
    }

    #[test]
    fn a_status_or_typing_is_believed_only_from_a_fellow_member() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let (space, general) = pair_with_general(&asha, &mira);

        // A device that shares no space is not believed.
        let mut stranger = PeerSpaces::default();
        let outcome = asha
            .receive(
                &mira.my_key(),
                Wire::Status {
                    status: "dnd".into(),
                    away: None,
                },
                &mut stranger,
                false,
            )
            .unwrap();
        assert!(!outcome.changed);
        assert_eq!(stranger.status, None);
        let outcome = asha
            .receive(
                &mira.my_key(),
                Wire::Typing {
                    space: space.clone(),
                    channel: general.clone(),
                },
                &mut stranger,
                false,
            )
            .unwrap();
        assert_eq!(outcome.typing, None);

        // A fellow member is, and only with a status the app has.
        let mut member = PeerSpaces::default();
        member.shared.insert(space.clone());
        for (said, kept) in [
            ("idle", Some("idle")),
            ("busy", Some("idle")),
            ("invisible", Some("idle")),
            ("offline", None),
        ] {
            asha.receive(
                &mira.my_key(),
                Wire::Status {
                    status: said.into(),
                    away: None,
                },
                &mut member,
                false,
            )
            .unwrap();
            assert_eq!(member.status.as_deref(), kept, "after {said}");
        }
        let outcome = asha
            .receive(
                &mira.my_key(),
                Wire::Typing {
                    space: space.clone(),
                    channel: general.clone(),
                },
                &mut member,
                false,
            )
            .unwrap();
        assert_eq!(outcome.typing, Some((space.clone(), general)));
    }

    #[test]
    fn a_role_given_by_anyone_but_the_owner_or_a_message_where_a_role_is_needed_counts_for_nothing()
    {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let (space, general) = pair_with_general(&asha, &mira);
        let (role, made) = asha
            .role_add(&space, "Crew", vec!["delete".into()])
            .unwrap();
        let kept = asha
            .channel_rules(
                &space,
                &general,
                ChannelRules {
                    writers: Some(vec![role.clone()]),
                    ..Default::default()
                },
            )
            .unwrap();
        hand(&mira, &asha.my_key(), &space, None, vec![made, kept]);
        let (said, sealed) = asha
            .post(&space, &general, "From the owner.", None, vec![])
            .unwrap();
        hand(&mira, &asha.my_key(), &space, None, vec![sealed]);

        // Mira gives herself the role, takes the owner's message down, and
        // writes where the role is needed. Her own app would refuse all of
        // it.
        let at = asha
            .load(&space_id(&space).unwrap())
            .unwrap()
            .unwrap()
            .clock
            + 1_000;
        let forged_items = vec![
            forged(
                &mira,
                &space,
                &Event::Grant {
                    member: mira.my_key(),
                    role: role.clone(),
                    on: true,
                    sent_at: at,
                },
            ),
            forged(
                &mira,
                &space,
                &Event::Delete {
                    target: said,
                    sent_at: at + 1,
                },
            ),
            forged(
                &mira,
                &space,
                &lasting(&general, "crew only, but not crew", at + 2, 0),
            ),
        ];
        hand(&asha, &mira.my_key(), &space, None, forged_items);
        assert_eq!(said_in(&asha, &space, &general), ["From the owner."]);
        let members = asha.member_list(&space).unwrap();
        assert!(members
            .as_array()
            .unwrap()
            .iter()
            .all(|m| m["roles"].as_array().unwrap().is_empty()));
    }

    #[test]
    fn a_device_that_does_not_share_the_space_is_sent_no_pieces() {
        let (_d1, v1, k1) = person();
        let folder = tempfile::tempdir().unwrap();
        let asha = Spaces {
            vault: &v1,
            me: &k1,
            my_name: "Asha",
            my_photo: None,
            files: folder.path(),
        };
        let space = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let general = asha
            .load(&space_id(&space).unwrap())
            .unwrap()
            .unwrap()
            .manifest()
            .unwrap()
            .channels[2]
            .id
            .clone();
        let original = folder.path().join("map.gpx");
        std::fs::write(&original, vec![5u8; 40_000]).unwrap();
        let file = FileToPost {
            path: original,
            kind: "file".into(),
            name: None,
            seconds: 0,
        };
        let (post, _) = asha
            .post_file(&space, &general, NewPost::default(), file)
            .unwrap();
        let sha = asha.file_of(&space, &post).unwrap().sha256;
        let ask = || Wire::FileWant {
            space: space.clone(),
            file: sha.clone(),
            from: 0,
        };

        // A device shown to share the space is sent pieces.
        let mut member = PeerSpaces::default();
        member.shared.insert(space.clone());
        let outcome = asha
            .receive(&"ab".repeat(32), ask(), &mut member, false)
            .unwrap();
        assert_eq!(outcome.replies.len(), 1);

        // One that is not gets nothing back, not even word that the space
        // is here.
        let mut stranger = PeerSpaces::default();
        let outcome = asha
            .receive(&"cd".repeat(32), ask(), &mut stranger, false)
            .unwrap();
        assert!(outcome.replies.is_empty());
    }

    #[test]
    fn many_items_are_split_into_sendable_batches() {
        let items: Vec<Vec<u8>> = (0..100).map(|_| vec![0u8; 10_000]).collect();
        let batches = batch(items);
        assert!(batches.len() > 1);
        assert_eq!(batches.iter().map(Vec::len).sum::<usize>(), 100);
        assert!(batches
            .iter()
            .all(|b| b.iter().map(|i| i.len() * 2).sum::<usize>() <= MAX_BATCH_BYTES));
        assert!(batch(Vec::new()).is_empty());
    }

    // Handing a space over. The tests in tests/space.rs cover what the
    // app can ask for. These cover what a changed copy of the app might
    // send: here someone who has handed a space over signs things they no
    // longer may.

    /// Hands `to` everything `from` holds of a space, as meeting would.
    fn pass(from: &Spaces, to: &Spaces, space: &str) {
        let id = space_id(space).unwrap();
        let record = from.load(&id).unwrap().unwrap();
        let mut stored = from.stored(&id).unwrap();
        stored.sort_by_key(|(_, arrival, _)| *arrival);
        hand(
            to,
            &from.my_key(),
            space,
            Some((record.manifest, record.signature)),
            stored.iter().map(|(_, _, sealed)| sealed.clone()).collect(),
        );
    }

    /// Puts sealed items in front of a device, as if `from` had sent them.
    fn hand(
        to: &Spaces,
        from: &str,
        space: &str,
        manifest: Option<(String, String)>,
        items: Vec<Vec<u8>>,
    ) {
        let mut known = PeerSpaces::default();
        known.shared.insert(space.to_string());
        let wire = Wire::Items {
            space: space.to_string(),
            manifest: manifest.as_ref().map(|(bytes, _)| bytes.clone()),
            signature: manifest.map(|(_, signature)| signature),
            items: items.iter().map(|sealed| hexcode::encode(sealed)).collect(),
        };
        to.receive(from, wire, &mut known, false).unwrap();
    }

    /// Asha's private space, with everyone in `others` joined to it and
    /// known to each other.
    fn space_with(asha: &Spaces, others: &[&Spaces]) -> String {
        let space = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let link = asha.link(&space).unwrap();
        for other in others {
            other.join_link(&link).unwrap();
            pass(asha, other, &space);
            pass(other, asha, &space);
        }
        for other in others {
            pass(asha, other, &space);
        }
        space
    }

    /// Something signed by `who` as if written into the space, whether or
    /// not they may write it.
    fn forged(who: &Spaces, space: &str, event: &Event) -> Vec<u8> {
        let id = space_id(space).unwrap();
        let key = who.load(&id).unwrap().unwrap().key().unwrap();
        who.seal_item(&id, &key, event).unwrap()
    }

    /// What `who` is in a space as `seen_by` has it, or None if they are
    /// not in it.
    fn role_of(seen_by: &Spaces, space: &str, who: &Spaces) -> Option<String> {
        seen_by
            .member_list(space)
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .find_map(|member| {
                (member["key"] == who.my_key().as_str())
                    .then(|| member["role"].as_str().unwrap().to_string())
            })
    }

    #[test]
    fn nothing_an_old_owner_signs_as_owner_counts_after_the_hand_over() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, v3, k3) = person();
        let (asha, mira, noor) = (
            spaces(&v1, &k1, "Asha"),
            spaces(&v2, &k2, "Mira"),
            spaces(&v3, &k3, "Noor"),
        );
        let space = space_with(&asha, &[&mira, &noor]);
        asha.hand_over(&space, &mira.my_key()).unwrap();
        pass(&asha, &mira, &space);
        pass(&mira, &noor, &space);
        assert_eq!(role_of(&noor, &space, &mira).as_deref(), Some("owner"));

        // Asha, with a changed app, puts Mira out and makes herself an
        // admin, and dates both before she handed over.
        let out = forged(
            &asha,
            &space,
            &Event::Remove {
                member: mira.my_key(),
                on: true,
                sent_at: 5,
            },
        );
        let up = forged(
            &asha,
            &space,
            &Event::Role {
                member: noor.my_key(),
                admin: true,
                sent_at: 5,
            },
        );
        hand(&noor, &asha.my_key(), &space, None, vec![out, up]);
        assert_eq!(role_of(&noor, &space, &mira).as_deref(), Some("owner"));
        assert_eq!(role_of(&noor, &space, &noor).as_deref(), Some("member"));
    }

    #[test]
    fn a_device_that_heard_the_old_owner_first_puts_it_right_on_learning_of_the_hand_over() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, v3, k3) = person();
        let (asha, mira, noor) = (
            spaces(&v1, &k1, "Asha"),
            spaces(&v2, &k2, "Mira"),
            spaces(&v3, &k3, "Noor"),
        );
        let space = space_with(&asha, &[&mira, &noor]);
        asha.hand_over(&space, &mira.my_key()).unwrap();
        pass(&asha, &mira, &space);

        // Noor has not heard. To her Asha is still the owner, so she takes
        // Asha's word that Noor is an admin now.
        let up = forged(
            &asha,
            &space,
            &Event::Role {
                member: noor.my_key(),
                admin: true,
                sent_at: 5,
            },
        );
        hand(&noor, &asha.my_key(), &space, None, vec![up]);
        assert_eq!(role_of(&noor, &space, &noor).as_deref(), Some("admin"));

        // Then she meets Mira. The hand-over lists what Asha decided as
        // owner, and that is not in it.
        pass(&mira, &noor, &space);
        assert_eq!(role_of(&noor, &space, &mira).as_deref(), Some("owner"));
        assert_eq!(role_of(&noor, &space, &asha).as_deref(), Some("member"));
        assert_eq!(role_of(&noor, &space, &noor).as_deref(), Some("member"));
    }

    #[test]
    fn a_space_handed_to_one_person_cannot_then_be_handed_to_another_by_the_old_owner() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, v3, k3) = person();
        let (_d4, _v4, eve) = person();
        let (asha, mira, noor) = (
            spaces(&v1, &k1, "Asha"),
            spaces(&v2, &k2, "Mira"),
            spaces(&v3, &k3, "Noor"),
        );
        let space = space_with(&asha, &[&mira, &noor]);
        asha.hand_over(&space, &mira.my_key()).unwrap();
        pass(&asha, &mira, &space);
        pass(&mira, &noor, &space);

        // Asha signs a second first hand-over, to Eve, dated earlier.
        let statement = serde_json::to_vec(&Handed {
            space: space.clone(),
            index: 0,
            from: asha.my_key(),
            to: hexcode::encode(&eve.signing_public()),
            at: 1,
            log: Vec::new(),
        })
        .unwrap();
        let other = Event::Handover {
            signature: hexcode::encode(&k1.sign(&signed_handover(&statement))),
            statement: hexcode::encode(&statement),
            sent_at: 1,
        };
        hand(
            &noor,
            &asha.my_key(),
            &space,
            None,
            vec![forged(&asha, &space, &other)],
        );
        assert_eq!(role_of(&noor, &space, &mira).as_deref(), Some("owner"));
        let id = space_id(&space).unwrap();
        assert_eq!(noor.load(&id).unwrap().unwrap().owner_now(), mira.my_key());
    }

    #[test]
    fn an_old_owner_cannot_delete_the_space_and_a_device_that_believed_them_gets_it_back() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, v3, k3) = person();
        let (asha, mira, noor) = (
            spaces(&v1, &k1, "Asha"),
            spaces(&v2, &k2, "Mira"),
            spaces(&v3, &k3, "Noor"),
        );
        let space = space_with(&asha, &[&mira, &noor]);
        asha.hand_over(&space, &mira.my_key()).unwrap();
        pass(&asha, &mira, &space);

        let gone = forged(&asha, &space, &Event::Closed { sent_at: 5 });
        // Mira knows it is hers, and takes no such word from Asha.
        hand(&mira, &asha.my_key(), &space, None, vec![gone.clone()]);
        assert_eq!(names(&mira, "joined"), ["Trek Team"]);

        // Noor has not heard of the hand-over, and loses the space.
        hand(&noor, &asha.my_key(), &space, None, vec![gone]);
        assert!(names(&noor, "joined").is_empty());
        // Until she meets Mira, whose proof that Asha no longer could
        // puts it back.
        pass(&mira, &noor, &space);
        assert_eq!(names(&noor, "joined"), ["Trek Team"]);
        assert_eq!(role_of(&noor, &space, &mira).as_deref(), Some("owner"));
    }

    #[test]
    fn a_space_its_owner_really_deleted_stays_deleted() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, v3, k3) = person();
        let (asha, mira, noor) = (
            spaces(&v1, &k1, "Asha"),
            spaces(&v2, &k2, "Mira"),
            spaces(&v3, &k3, "Noor"),
        );
        let space = space_with(&asha, &[&mira, &noor]);
        asha.hand_over(&space, &mira.my_key()).unwrap();
        pass(&asha, &mira, &space);
        pass(&mira, &noor, &space);
        // Mira, the owner now, deletes it. Nothing Asha or anyone else
        // holds from before brings it back.
        mira.close(&space).unwrap();
        pass(&mira, &noor, &space);
        assert!(names(&noor, "joined").is_empty());
        pass(&asha, &noor, &space);
        assert!(names(&noor, "joined").is_empty());
    }

    #[test]
    fn the_old_owners_word_on_what_the_space_is_is_no_longer_taken() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, v3, k3) = person();
        let (asha, mira, noor) = (
            spaces(&v1, &k1, "Asha"),
            spaces(&v2, &k2, "Mira"),
            spaces(&v3, &k3, "Noor"),
        );
        let space = space_with(&asha, &[&mira, &noor]);
        let id = space_id(&space).unwrap();
        let before = asha.load(&id).unwrap().unwrap().manifest().unwrap();
        asha.hand_over(&space, &mira.my_key()).unwrap();
        pass(&asha, &mira, &space);
        pass(&mira, &noor, &space);

        // Asha signs the space under a new name, as if it were still hers.
        let mut renamed = before;
        renamed.name = "Mine again".to_string();
        renamed.version = 99;
        let bytes = serde_json::to_vec(&renamed).unwrap();
        let event = Event::Manifest {
            signature: hexcode::encode(&k1.sign(&signed_manifest(&bytes))),
            manifest: hexcode::encode(&bytes),
            sent_at: 5,
        };
        hand(
            &noor,
            &asha.my_key(),
            &space,
            None,
            vec![forged(&asha, &space, &event)],
        );
        assert_eq!(names(&noor, "joined"), ["Trek Team"]);
        assert_eq!(
            noor.load(&id).unwrap().unwrap().manifest().unwrap().owner,
            mira.my_key()
        );
    }

    #[test]
    fn a_new_key_is_taken_only_from_whoever_owns_the_space_now() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, v3, k3) = person();
        let (asha, mira, noor) = (
            spaces(&v1, &k1, "Asha"),
            spaces(&v2, &k2, "Mira"),
            spaces(&v3, &k3, "Noor"),
        );
        let space = space_with(&asha, &[&mira, &noor]);
        let id = space_id(&space).unwrap();
        asha.hand_over(&space, &mira.my_key()).unwrap();
        pass(&asha, &mira, &space);
        pass(&mira, &noor, &space);
        let before = noor.load(&id).unwrap().unwrap().key;
        let rekey = |key: &str| Wire::Rekey {
            space: space.clone(),
            epoch: 9,
            key: key.repeat(32),
        };

        noor.receive(
            &asha.my_key(),
            rekey("ab"),
            &mut PeerSpaces::default(),
            false,
        )
        .unwrap();
        assert_eq!(noor.load(&id).unwrap().unwrap().key, before);
        noor.receive(
            &mira.my_key(),
            rekey("cd"),
            &mut PeerSpaces::default(),
            false,
        )
        .unwrap();
        assert_eq!(noor.load(&id).unwrap().unwrap().key, "cd".repeat(32));
    }

    #[test]
    fn a_hand_over_holds_only_if_each_link_is_signed_by_the_owner_before_it() {
        let (_d1, _v1, asha) = person();
        let (_d2, _v2, mira) = person();
        let (_d3, _v3, eve) = person();
        let key = |who: &IdentitySecret| hexcode::encode(&who.signing_public());
        let space = "ab".repeat(16);
        let link = |signer: &IdentitySecret, handed: &Handed| {
            let statement = serde_json::to_vec(handed).unwrap();
            Handover {
                signature: hexcode::encode(&signer.sign(&signed_handover(&statement))),
                statement: hexcode::encode(&statement),
            }
        };
        let honest = Handed {
            space: space.clone(),
            index: 0,
            from: key(&asha),
            to: key(&mira),
            at: 1000,
            log: vec![Event::Role {
                member: key(&eve),
                admin: true,
                sent_at: 900,
            }],
        };
        let holds = |chain: &[Handover]| read_chain(&space, &key(&asha), chain).is_some();
        assert!(holds(&[link(&asha, &honest)]));
        assert!(holds(&[]), "a space never handed over has nothing to check");

        // Signed by someone who did not own it, even the one it goes to.
        assert!(!holds(&[link(&eve, &honest)]));
        assert!(!holds(&[link(&mira, &honest)]));
        // Saying it is from someone other than the owner.
        assert!(!holds(&[link(
            &asha,
            &Handed {
                from: key(&eve),
                ..honest.clone()
            }
        )]));
        // For another space, out of place, or to themselves.
        assert!(!holds(&[link(
            &asha,
            &Handed {
                space: "cd".repeat(16),
                ..honest.clone()
            }
        )]));
        assert!(!holds(&[link(
            &asha,
            &Handed {
                index: 1,
                ..honest.clone()
            }
        )]));
        assert!(!holds(&[link(
            &asha,
            &Handed {
                to: key(&asha),
                ..honest.clone()
            }
        )]));
        // Carrying anything but who was made an admin or removed, or a
        // decision dated after the space was no longer theirs.
        let with = |log: Vec<Event>| {
            link(
                &asha,
                &Handed {
                    log,
                    ..honest.clone()
                },
            )
        };
        assert!(!holds(&[with(vec![Event::Closed { sent_at: 900 }])]));
        assert!(!holds(&[with(vec![Event::Remove {
            member: key(&eve),
            on: true,
            sent_at: 1001
        }])]));
        assert!(holds(&[with(vec![Event::Remove {
            member: key(&eve),
            on: true,
            sent_at: 1000
        }])]));
        // Altered after signing.
        let mut altered = link(&asha, &honest);
        let said = String::from_utf8(hexcode::decode(&altered.statement).unwrap()).unwrap();
        assert!(said.contains(&key(&mira)));
        altered.statement = hexcode::encode(said.replace(&key(&mira), &key(&eve)).as_bytes());
        assert!(!holds(&[altered]));

        // A second link is signed by the first's new owner, and no other.
        let onward = Handed {
            index: 1,
            from: key(&mira),
            to: key(&eve),
            at: 2000,
            log: Vec::new(),
            space: space.clone(),
        };
        assert!(holds(&[link(&asha, &honest), link(&mira, &onward)]));
        assert!(!holds(&[link(&asha, &honest), link(&asha, &onward)]));
        assert!(!holds(&[
            link(&asha, &honest),
            link(
                &mira,
                &Handed {
                    at: 999,
                    ..onward.clone()
                }
            )
        ]));
    }

    #[test]
    fn a_manifest_that_tells_another_story_of_who_made_the_space_is_refused() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (_d3, _v3, eve) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let space = space_with(&asha, &[&mira]);
        let id = space_id(&space).unwrap();
        let honest = asha.load(&id).unwrap().unwrap().manifest().unwrap();
        let eve_key = hexcode::encode(&eve.signing_public());

        // Eve makes up a hand-over from herself to herself-as-owner: a
        // manifest saying she made the space and still has it.
        let mut hers = honest.clone();
        hers.owner = eve_key.clone();
        hers.version = 50;
        let bytes = serde_json::to_vec(&hers).unwrap();
        let signature = hexcode::encode(&eve.sign(&signed_manifest(&bytes)));
        assert!(
            read_manifest(&hexcode::encode(&bytes), &signature).is_some(),
            "it holds together by itself"
        );
        let event = Event::Manifest {
            manifest: hexcode::encode(&bytes),
            signature,
            sent_at: 5,
        };
        // But Mira was told who made this space, and it was not Eve.
        let record = mira.load(&id).unwrap().unwrap();
        assert!(!allowed(&event, &eve_key, &record, &honest));

        // Nor does naming Asha as the maker help without Asha's signature
        // on the hand-over.
        let statement = serde_json::to_vec(&Handed {
            space: space.clone(),
            index: 0,
            from: asha.my_key(),
            to: eve_key.clone(),
            at: 1,
            log: Vec::new(),
        })
        .unwrap();
        hers.founder = asha.my_key();
        hers.chain = vec![Handover {
            signature: hexcode::encode(&eve.sign(&signed_handover(&statement))),
            statement: hexcode::encode(&statement),
        }];
        let bytes = serde_json::to_vec(&hers).unwrap();
        let signature = hexcode::encode(&eve.sign(&signed_manifest(&bytes)));
        assert!(read_manifest(&hexcode::encode(&bytes), &signature).is_none());
    }

    #[test]
    fn a_public_channel_cannot_be_handed_over() {
        let (_d1, v1, k1) = person();
        let (_d2, _v2, k2) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let space = asha.create("City Signal", "channel", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        assert!(asha
            .hand_over(&space, &hexcode::encode(&k2.signing_public()))
            .is_err());
    }

    #[test]
    fn a_place_is_posted_on_its_own_and_only_if_it_is_on_the_globe() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, mira) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Mira"));
        let space = space_with(&asha, &[&mira]);
        let id = space_id(&space).unwrap();
        let manifest = asha.load(&id).unwrap().unwrap().manifest().unwrap();
        let general = manifest
            .channels
            .iter()
            .find(|c| c.name == "general")
            .unwrap()
            .id
            .clone();
        let here = Place {
            lat: 48.858_370_1,
            lon: 2.294_481,
            accuracy: 9,
        };
        let new = |location: Option<Place>, options: Vec<String>| NewPost {
            body: "ignored for a place".into(),
            options,
            location,
            ..NewPost::default()
        };
        // The words are the place, whatever was written.
        asha.post_mentioning(&space, &general, new(Some(here), vec![]))
            .unwrap();
        let shown = &asha.channel(&space, &general).unwrap()["messages"][0];
        assert_eq!(shown["body"], "48.858370, 2.294481");
        assert_eq!(
            shown["location"],
            json!({"lat": 48.85837, "lon": 2.294481, "accuracy": 9})
        );
        // Not a poll, and not off the globe.
        let poll = vec!["a".to_string(), "b".to_string()];
        assert!(asha
            .post_mentioning(&space, &general, new(Some(here), poll.clone()))
            .is_err());
        let nowhere = Place { lat: 95.0, ..here };
        assert!(asha
            .post_mentioning(&space, &general, new(Some(nowhere), vec![]))
            .is_err());

        // Another device drops one that breaks either rule.
        let record = mira.load(&id).unwrap().unwrap();
        let post = |location: Option<Place>, options: Vec<String>| Event::Post {
            id: "c1".repeat(16),
            channel: general.clone(),
            body: "48.858370, 2.294481".into(),
            sent_at: 5,
            reply_to: None,
            options,
            name: String::new(),
            mentions: vec![],
            lasts: 0,
            file: None,
            everyone: false,
            roles: vec![],
            forwarded: false,
            location,
            sticker: None,
        };
        let asha_key = hexcode::encode(&k1.signing_public());
        assert!(allowed(
            &post(Some(here), vec![]),
            &asha_key,
            &record,
            &manifest
        ));
        assert!(!allowed(
            &post(Some(nowhere), vec![]),
            &asha_key,
            &record,
            &manifest
        ));
        assert!(!allowed(
            &post(Some(here), poll),
            &asha_key,
            &record,
            &manifest
        ));
    }

    /// A picture of `size` bytes, as far as the core can tell.
    fn icon_hex(size: usize, fill: u8) -> String {
        let mut bytes = b"GIF89a".to_vec();
        bytes.resize(size, fill);
        hexcode::encode(&bytes)
    }

    #[test]
    fn what_is_announced_nearby_stays_small_with_an_icon() {
        let (_d1, v1, k1) = person();
        let (_d2, _v2, k2) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let (id, _) = announced(&asha);
        let icon = icon_hex(MAX_ICON_BYTES, 9);
        asha.set_icon(&id, Some(&icon)).unwrap();

        let peer = hexcode::encode(&k2.signing_public());
        let hello = asha
            .hello(&peer, &mut PeerSpaces::default(), false)
            .unwrap();
        let Wire::Hello { public, .. } = &hello else {
            panic!("a hello");
        };
        assert_eq!(public.len(), 1, "the space is announced");
        let said = serde_json::to_string(&hello).unwrap();
        assert!(!said.contains(&icon[..64]), "the picture is not in it");
        assert!(said.len() < 4 * 1024, "a hello of {} bytes", said.len());
        // Its fingerprint is, signed by the owner.
        let manifest = read_manifest(&public[0].manifest, &public[0].signature).unwrap();
        assert_eq!(
            manifest.icon,
            hexcode::encode(&Sha256::digest(hexcode::decode(&icon).unwrap()))
        );
    }

    #[test]
    fn only_the_icon_the_owner_signed_is_taken() {
        let (_d1, v1, k1) = person();
        let (_d2, v2, k2) = person();
        let (asha, noor) = (spaces(&v1, &k1, "Asha"), spaces(&v2, &k2, "Noor"));
        let (id, _) = announced(&asha);
        let icon = icon_hex(2000, 4);
        asha.set_icon(&id, Some(&icon)).unwrap();
        let from = hexcode::encode(&k1.signing_public());
        let mut known = PeerSpaces::default();

        // Hearing of the space, Noor asks the device that announced it.
        let hello = asha
            .hello(
                &hexcode::encode(&k2.signing_public()),
                &mut PeerSpaces::default(),
                false,
            )
            .unwrap();
        let asked = noor.receive(&from, hello, &mut known, false).unwrap();
        assert!(matches!(
            asked.replies.as_slice(),
            [Wire::IconWant { space, .. }] if *space == id
        ));
        assert!(noor.list(std::iter::empty()).unwrap()["nearby"][0]["icon"].is_null());

        // Another picture, or one too big, is turned away.
        let wrong = noor
            .receive(
                &from,
                Wire::Icon {
                    space: id.clone(),
                    icon: icon_hex(2000, 5),
                },
                &mut known,
                false,
            )
            .unwrap();
        assert!(!wrong.changed);
        assert!(noor.list(std::iter::empty()).unwrap()["nearby"][0]["icon"].is_null());

        let right = noor
            .receive(
                &from,
                Wire::Icon {
                    space: id.clone(),
                    icon: icon.clone(),
                },
                &mut known,
                false,
            )
            .unwrap();
        assert!(right.changed);
        assert_eq!(
            noor.list(std::iter::empty()).unwrap()["nearby"][0]["icon"],
            icon.as_str()
        );
    }

    #[test]
    fn a_private_space_icon_goes_only_to_a_fellow_member() {
        let (_d1, v1, k1) = person();
        let (_d2, _v2, k2) = person();
        let asha = spaces(&v1, &k1, "Asha");
        let id = asha.create("Trek Team", "private", "").unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let icon = icon_hex(700, 2);
        asha.set_icon(&id, Some(&icon)).unwrap();
        let named = hexcode::encode(&Sha256::digest(hexcode::decode(&icon).unwrap()));
        let from = hexcode::encode(&k2.signing_public());
        let want = || Wire::IconWant {
            space: id.clone(),
            icon: named.clone(),
        };

        let stranger = asha
            .receive(&from, want(), &mut PeerSpaces::default(), false)
            .unwrap();
        assert!(stranger.replies.is_empty());

        let mut member = PeerSpaces::default();
        member.shared.insert(id.clone());
        let answered = asha.receive(&from, want(), &mut member, false).unwrap();
        assert!(matches!(
            answered.replies.as_slice(),
            [Wire::Icon { icon: sent, .. }] if *sent == icon
        ));
    }
}
