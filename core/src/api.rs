//! The core as the app sees it: one request in, one reply out, both JSON.
//!
//! A reply is `{"ok": ...}` or `{"err": {"code": "...", "message": "..."}}`.
//! Keeping the whole surface to one function is what keeps the unsafe
//! boundary with Dart to two small functions in `lib.rs`.

use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use zeroize::Zeroizing;

use crate::call::{self, Calls, OwnerSays, RoomWire};
use crate::chat::{Chat, Sessions, Sticker};
use crate::error::{CoreError, Result};
use crate::file::{self, Files};
use crate::hexcode;
use crate::identity::{IdentitySecret, PublicIdentity, SIGNING_LEN};
use crate::keyguard;
// `Links` here is already the name of the link switches on the Network
// screen, so the table of open connections comes in under another name.
use crate::link::{Link, Links as OpenLinks};
use crate::place::Place;
use crate::proof;
use crate::relay::{self, Relay, Verdict};
use crate::space::{ChannelRules, FileToPost, NewPost, PeerSpaces, Spaces, Wire, STATUSES};

/// The folder, beside the vault, where files posted in channels are kept.
const SPACE_FILES: &str = "space_files";
use crate::vault::{Vault, SCHEMA_VERSION};
use crate::words;

const IDENTITY: (&str, &[u8]) = ("identity", b"secret");
const NAME: (&str, &[u8]) = ("profile", b"name");
const PHOTO: (&str, &[u8]) = ("profile", b"photo");

/// The user's own profile photo: a built-in picture, their own small
/// photo, or neither. `version` rises with every change, and with every
/// switch of who may see it, so contacts always keep the newest word.
#[derive(Default, Serialize, Deserialize)]
struct MyPhoto {
    preset: Option<u8>,
    photo: Option<String>,
    version: u64,
}
const SETTINGS: (&str, &[u8]) = ("settings", b"all");
/// Sealed envelopes waiting for someone who is not connected. Each is kept
/// under a random id, so the file does not show who they are for.
const OUTBOX: &str = "outbox";
/// The user's notes to self. They are never sealed to anyone and never
/// handed to a radio.
const NOTES: &str = "notes";
const MAX_NOTE_CHARS: usize = 16_000;

/// Where the key that unlocks the vault comes from.
pub enum KeySource {
    /// The core guards it itself. Windows only.
    Platform,
    /// The app unwrapped it and passed it in. This is how Android works.
    Provided(Zeroizing<[u8; 32]>),
}

impl KeySource {
    /// `master_key` is 64 hex digits, or absent to let the core guard it.
    pub fn from_request(master_key: Option<&str>) -> Result<Self> {
        let Some(hex) = master_key else {
            return Ok(KeySource::Platform);
        };
        let bytes = Zeroizing::new(hexcode::decode(hex)?);
        let key: [u8; 32] = bytes
            .as_slice()
            .try_into()
            .map_err(|_| CoreError::Invalid("the master key must be 32 bytes".into()))?;
        Ok(KeySource::Provided(Zeroizing::new(key)))
    }
}

/// The sharing choices on the Privacy screen. Off is the private setting,
/// so every one of them starts off.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Sharing {
    pub show_online: bool,
    pub find_by_name: bool,
    pub add_to_groups: bool,
    pub show_ip_in_calls: bool,
    pub read_receipts: bool,
    pub typing: bool,
    pub screenshots: bool,
    /// Contacts are sent the user's profile photo.
    pub show_photo: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Device {
    pub app_lock: bool,
    pub auto_delete: bool,
    pub erase_on_wrong_passcode: bool,
}

impl Default for Device {
    fn default() -> Self {
        Self {
            app_lock: true,
            auto_delete: false,
            erase_on_wrong_passcode: false,
        }
    }
}

/// Nearby links are the core of the app and start on. The internet path is
/// optional and starts off.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Links {
    pub bluetooth: bool,
    pub wifi_nearby: bool,
    pub long_range: bool,
    pub internet: bool,
}

impl Default for Links {
    fn default() -> Self {
        Self {
            bluetooth: true,
            wifi_nearby: true,
            long_range: false,
            internet: false,
        }
    }
}

/// Everything the user can switch. Encryption and the other protections are
/// deliberately not here: they are not a choice.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub sharing: Sharing,
    pub device: Device,
    pub links: Links,
    pub remove_location_from_photos: bool,
    /// How the user tells fellow members in range they are: one of
    /// [`STATUSES`]. "invisible" tells nobody anything.
    pub status: String,
    /// Set while the user says they are away, as with ".afk lunch": why,
    /// or empty for no reason. Told with the status, and to contacts.
    pub away: Option<String>,
    pub safety: Safety,
    /// Who may send the user a chat request: one of [`REQUESTS_FROM`].
    pub requests_from: String,
    /// How many minutes the app may be out of sight before it locks, when
    /// there is a passcode: one of [`AUTO_LOCK`]. Nought locks at once.
    pub auto_lock: u32,
}

/// Choices that keep the user safe. Each starts the way most people want.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Safety {
    /// A contact whose own device shows the user its key, by a tap or a
    /// code on its screen, is verified with no words to compare.
    pub auto_verify: bool,
    /// This device passes on sealed messages between other people in
    /// range. It cannot read them.
    pub relay: bool,
    /// Files from people who are not verified wait to be accepted, however
    /// small.
    pub verified_files_only: bool,
}

impl Default for Safety {
    fn default() -> Self {
        Self {
            auto_verify: true,
            relay: true,
            verified_files_only: false,
        }
    }
}

/// Everyone in range; only people who share a space with the user; or
/// nobody. Someone using one of the user's own links is always let ask.
pub const REQUESTS_FROM: [&str; 3] = ["everyone", "spaces", "nobody"];
pub const AUTO_LOCK: [u32; 5] = [0, 1, 5, 15, 60];

/// One slice of stamp work: short enough that the app stays smooth.
fn stamp_millis() -> u64 {
    40
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            sharing: Sharing::default(),
            device: Device::default(),
            links: Links::default(),
            remove_location_from_photos: true,
            // Being in range of a fellow member already shows them the
            // user is there, since syncing is how a space travels. So
            // "online" tells them nothing new.
            status: "online".to_string(),
            away: None,
            safety: Safety::default(),
            requests_from: "everyone".to_string(),
            auto_lock: 1,
        }
    }
}

impl Settings {
    fn switch(&mut self, group: &str, name: &str) -> Result<&mut bool> {
        let found = match (group, name) {
            ("sharing", "show_online") => &mut self.sharing.show_online,
            ("sharing", "find_by_name") => &mut self.sharing.find_by_name,
            ("sharing", "add_to_groups") => &mut self.sharing.add_to_groups,
            ("sharing", "show_ip_in_calls") => &mut self.sharing.show_ip_in_calls,
            ("sharing", "read_receipts") => &mut self.sharing.read_receipts,
            ("sharing", "typing") => &mut self.sharing.typing,
            ("sharing", "screenshots") => &mut self.sharing.screenshots,
            ("sharing", "show_photo") => &mut self.sharing.show_photo,
            ("device", "app_lock") => &mut self.device.app_lock,
            ("device", "auto_delete") => &mut self.device.auto_delete,
            ("device", "erase_on_wrong_passcode") => &mut self.device.erase_on_wrong_passcode,
            ("links", "bluetooth") => &mut self.links.bluetooth,
            ("links", "wifi_nearby") => &mut self.links.wifi_nearby,
            ("links", "long_range") => &mut self.links.long_range,
            ("links", "internet") => &mut self.links.internet,
            ("photos", "remove_location") => &mut self.remove_location_from_photos,
            ("safety", "auto_verify") => &mut self.safety.auto_verify,
            ("safety", "relay") => &mut self.safety.relay,
            ("safety", "verified_files_only") => &mut self.safety.verified_files_only,
            _ => {
                return Err(CoreError::Invalid(format!(
                    "there is no setting {group}/{name}"
                )))
            }
        };
        Ok(found)
    }
}

// Each request is named for what it does, so some names echo the type's.
#[allow(clippy::enum_variant_names)]
#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum Request {
    Open {
        dir: PathBuf,
        master_key: Option<String>,
    },
    CreateIdentity {
        name: String,
    },
    Profile,
    /// Someone's three code words at a moment, the user's own included.
    CodeWords {
        /// Their signing key.
        key: String,
        /// Seconds since 1970. Now, if not given.
        #[serde(default)]
        at: Option<u64>,
    },
    SetName {
        name: String,
    },
    Settings,
    SetSetting {
        group: String,
        name: String,
        value: bool,
    },
    Card,
    RequestChat {
        identity: String,
        note: Option<String>,
        #[serde(default)]
        scanned: bool,
        #[serde(default)]
        known_as: Option<String>,
        /// With `scanned`: "qr" or "tap", noted as how they will have been
        /// verified once they accept.
        #[serde(default)]
        how: Option<String>,
    },
    VerifyScanned {
        identity: String,
        /// "qr" (the default) or "tap".
        #[serde(default)]
        how: Option<String>,
    },
    /// Makes the user's key ahead of their identity, so its stamp can be
    /// worked out before anyone is shown they are here.
    IdentityDraft,
    /// Works on the stamp for the user's identity, or for the draft if
    /// there is no identity yet, making a draft if need be.
    StampWork {
        /// How long to work for, at most.
        #[serde(default = "stamp_millis")]
        millis: u64,
        /// How many numbers to try, at most.
        #[serde(default)]
        tries: Option<u64>,
    },
    /// Sets one of the privacy choices that is not on or off:
    /// "requests_from" or "auto_lock".
    SetChoice {
        name: String,
        value: String,
    },
    /// A contact's key, read off their screen.
    VerifyKey {
        key: String,
    },
    /// A new one-time link for asking the user to chat.
    InviteLink,
    CheckInvite {
        link: String,
    },
    RequestByInvite {
        link: String,
        #[serde(default)]
        note: Option<String>,
        /// Read off the other person's own device, by tapping phones.
        #[serde(default)]
        scanned: bool,
    },
    CancelRequest {
        to: String,
    },
    Requests,
    Accept {
        from: String,
    },
    Decline {
        from: String,
    },
    Block {
        who: String,
    },
    Unblock {
        who: String,
    },
    Blocked,
    CheckCode {
        with: String,
    },
    CheckPaste {
        with: String,
        code: String,
    },
    Contacts,
    SendText {
        to: String,
        #[serde(default)]
        body: String,
        #[serde(default)]
        options: Vec<String>,
        /// Passed on from a channel or another chat.
        #[serde(default)]
        forwarded: bool,
        /// A sticker, sent in place of words.
        #[serde(default)]
        sticker: Option<Sticker>,
    },
    SendCard {
        to: String,
        contact: String,
    },
    /// Where the user is, to one contact.
    SendLocation {
        to: String,
        location: Place,
    },
    Vote {
        with: String,
        id: String,
        choice: u32,
    },
    Thread {
        with: String,
    },
    MarkRead {
        with: String,
    },
    Held,
    SaveNote {
        body: String,
    },
    Notes,
    Purge {
        before: u64,
    },
    Expire {
        now: u64,
    },
    SetTimer {
        with: String,
        seconds: u64,
    },
    /// Sets the user's profile photo: a built-in picture or their own.
    PhotoSet {
        #[serde(default)]
        preset: Option<u8>,
        #[serde(default)]
        photo: Option<String>,
    },
    PhotoClear,
    MyPhoto,
    /// A contact's profile photo.
    PhotoOf {
        who: String,
    },
    /// Deletes messages in a chat from this device only.
    ChatDeleteMine {
        with: String,
        ids: Vec<String>,
    },
    /// Deletes the user's own recent messages for everyone.
    ChatUnsend {
        with: String,
        ids: Vec<String>,
    },
    /// Empties a chat on this device.
    ChatClear {
        with: String,
    },
    /// Empties a chat and takes it off the list until a new message.
    ChatDelete {
        with: String,
    },
    LockState,
    LockSet {
        passcode: String,
        #[serde(default)]
        current: Option<String>,
    },
    LockCheck {
        passcode: String,
    },
    LockClear {
        passcode: String,
    },
    SpaceCreate {
        name: String,
        kind: String,
        #[serde(default)]
        description: String,
    },
    Spaces,
    SpaceChannel {
        space: String,
        channel: String,
    },
    SpacePost {
        space: String,
        channel: String,
        body: String,
        #[serde(default)]
        reply_to: Option<String>,
        #[serde(default)]
        options: Vec<String>,
        /// Members it calls on, by signing key.
        #[serde(default)]
        mentions: Vec<String>,
        /// Calls on everyone in the space.
        #[serde(default)]
        everyone: bool,
        /// Roles it calls on, by id.
        #[serde(default)]
        roles: Vec<String>,
        /// Passed on from another channel or a chat.
        #[serde(default)]
        forwarded: bool,
        /// Where the user is, if that is what they post. The body is
        /// then the place in words.
        #[serde(default)]
        location: Option<Place>,
        /// A sticker, posted in place of words.
        #[serde(default)]
        sticker: Option<Sticker>,
    },
    SpaceComments {
        space: String,
        post: String,
    },
    SpaceReact {
        space: String,
        target: String,
        kind: String,
        on: bool,
    },
    SpacePin {
        space: String,
        target: String,
        on: bool,
    },
    SpaceVote {
        space: String,
        target: String,
        choice: u32,
    },
    SpaceDelete {
        space: String,
        target: String,
    },
    /// Changes the words of something the user wrote in a space.
    SpaceEditPost {
        space: String,
        target: String,
        body: String,
    },
    SpaceEdit {
        space: String,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        description: Option<String>,
    },
    /// What whoever runs the space sets a member to be called.
    SpaceNick {
        space: String,
        member: String,
        #[serde(default)]
        name: String,
    },
    /// The owner's welcome to people who join, and the space's rules.
    SpaceWelcome {
        space: String,
        #[serde(default)]
        welcome: Option<String>,
        #[serde(default)]
        rules: Option<String>,
    },
    /// The owner setting the space's icon, a small picture or GIF in hex,
    /// or with none taking it away.
    SpaceIcon {
        space: String,
        #[serde(default)]
        icon: Option<String>,
    },
    SpaceChannelAdd {
        space: String,
        name: String,
        group: String,
    },
    SpaceChannelRename {
        space: String,
        channel: String,
        name: String,
    },
    SpaceChannelRemove {
        space: String,
        channel: String,
    },
    SpaceChannelRules {
        space: String,
        channel: String,
        #[serde(default)]
        slow: Option<u32>,
        #[serde(default)]
        no_links: Option<bool>,
        #[serde(default)]
        owners_only: Option<bool>,
        /// Seconds a message lasts here; 0 for good.
        #[serde(default)]
        disappear: Option<u32>,
        /// The longest a member's message may be; 0 for no limit.
        #[serde(default)]
        max_len: Option<u32>,
        /// The roles kept to write here. Empty: everyone.
        #[serde(default)]
        writers: Option<Vec<String>>,
    },
    /// Posts a file, a picture or a voice message in a channel.
    SpacePostFile {
        space: String,
        channel: String,
        path: PathBuf,
        /// "picture", "voice" or "file".
        kind: String,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        seconds: u32,
        #[serde(default)]
        body: String,
        #[serde(default)]
        reply_to: Option<String>,
    },
    /// Fetches the file a post carries from whoever in range has it.
    SpaceFileGet {
        space: String,
        post: String,
    },
    /// Copies the file a post carries to a folder for the user.
    SpaceFileSave {
        space: String,
        post: String,
        dir: PathBuf,
    },
    /// Makes a role in a space.
    SpaceRoleAdd {
        space: String,
        name: String,
        #[serde(default)]
        may: Vec<String>,
    },
    SpaceRoleEdit {
        space: String,
        role: String,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        may: Option<Vec<String>>,
    },
    SpaceRoleRemove {
        space: String,
        role: String,
    },
    /// Gives a member a role, or takes it back.
    SpaceGrant {
        space: String,
        member: String,
        role: String,
        on: bool,
    },
    /// The words and phrases members may not use in a space.
    SpaceBannedWords {
        space: String,
        words: Vec<String>,
    },
    /// Switches a space's word filter off or on, keeping its list.
    SpaceWordFilter {
        space: String,
        on: bool,
    },
    SpaceRole {
        space: String,
        member: String,
        admin: bool,
    },
    SpaceRemove {
        space: String,
        member: String,
    },
    SpaceDeleteSpace {
        space: String,
    },
    SpaceResetLinks {
        space: String,
    },
    SpaceTimeout {
        space: String,
        member: String,
        seconds: u64,
    },
    SpaceName {
        space: String,
        name: String,
    },
    SpaceHandover {
        space: String,
        to: String,
    },
    SpaceRead {
        space: String,
        channel: String,
    },
    SpaceMute {
        space: String,
        on: bool,
    },
    SpaceMembers {
        space: String,
    },
    SpaceJoin {
        space: String,
    },
    SpaceLeave {
        space: String,
    },
    SpaceLink {
        space: String,
        /// How many seconds the link lets people in for. None: for good.
        #[serde(default)]
        lasts: Option<u64>,
    },
    /// What a pasted invite is for, and whether it has run out.
    SpaceLinkCheck {
        link: String,
    },
    SpaceJoinLink {
        link: String,
    },
    SpaceInvite {
        space: String,
        to: String,
    },
    FileSend {
        to: String,
        path: PathBuf,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        once: bool,
    },
    FileViewed {
        id: String,
    },
    FileAccept {
        id: String,
        dir: PathBuf,
    },
    FileDecline {
        id: String,
    },
    FileCancel {
        id: String,
    },
    FilePause {
        id: String,
    },
    FileResume {
        id: String,
    },
    Files,
    Carrying,
    Receive {
        envelope: String,
    },
    VerifyStart {
        with: String,
    },
    FastAsk {
        to: String,
    },
    Typing {
        to: String,
    },
    /// The user is writing in a space's channel.
    SpaceTyping {
        space: String,
        channel: String,
    },
    /// How the user tells fellow members in range they are.
    SetStatus {
        status: String,
    },
    /// Says the user is away, and why, or with no note that they are back.
    SetAway {
        #[serde(default)]
        away: Option<String>,
    },
    Here {
        to: String,
        active: bool,
    },
    FastOffer {
        to: String,
        network: String,
        pass: String,
        joins: bool,
    },
    VerifyWords {
        with: String,
    },
    VerifyConfirm {
        with: String,
        matched: bool,
    },
    /// Calls a contact in range.
    CallStart {
        to: String,
        #[serde(default)]
        video: bool,
    },
    CallAnswer {
        call: String,
    },
    /// Hangs up, or turns down a call that is ringing.
    CallEnd {
        call: String,
        #[serde(default)]
        reason: Option<String>,
    },
    /// Tells the other person the user's microphone or camera changed.
    CallTell {
        call: String,
        muted: bool,
        camera: bool,
        /// Is sharing their screen.
        #[serde(default)]
        screen: bool,
    },
    /// Seals a frame of the user's sound or picture for a call or room.
    CallMediaOut {
        call: String,
        kind: String,
        data: String,
    },
    /// Opens a frame of sound or picture that came in on a link.
    CallMediaIn {
        link: u32,
        frame: String,
    },
    Calls,
    /// Goes into a space's voice room.
    RoomJoin {
        space: String,
        channel: String,
        /// Nobody answered the ask to be let in: open the room afresh.
        #[serde(default)]
        alone: bool,
        #[serde(default)]
        muted: bool,
    },
    /// Says the user is still in the room, and how.
    RoomTick {
        space: String,
        channel: String,
        #[serde(default)]
        muted: bool,
        #[serde(default)]
        deaf: bool,
        #[serde(default)]
        camera: bool,
        #[serde(default)]
        screen: bool,
    },
    RoomLeave {
        space: String,
        channel: String,
    },
    Rooms,
    /// Whoever runs the space mutes or deafens a member in its voice
    /// rooms, or lets them be.
    SpaceVoice {
        space: String,
        member: String,
        #[serde(default)]
        mute: bool,
        #[serde(default)]
        deafen: bool,
    },
    LinkOpen {
        link: u32,
        max_frame: usize,
    },
    LinkReceive {
        link: u32,
        frame: String,
    },
    LinkSend {
        envelope: Value,
    },
    LinkClose {
        link: u32,
    },
    /// Tells the devices in range who this one hears, where that changed
    /// or is due again. `peers` is how the app hears each: by which radio
    /// and how near. See `relay.rs`.
    MeshShare {
        #[serde(default)]
        peers: Vec<relay::Neighbour>,
        /// Milliseconds since 1970, for tests. Now, if not given.
        #[serde(default)]
        now: Option<u64>,
    },
    /// The mesh as the devices in range last told it.
    Mesh {
        #[serde(default)]
        now: Option<u64>,
    },
    Poll,
    Close,
    Wipe,
    PhotoClean {
        path: String,
        dir: String,
    },
    Version,
    /// The user's own stickers and how they are arranged. See
    /// `stickers.rs`.
    StickerBook,
    StickerBookSave {
        book: Value,
    },
    StickerKeep {
        image: String,
    },
    StickerPicture {
        id: String,
    },
    StickerDrop {
        id: String,
    },
}

struct Open {
    dir: PathBuf,
    vault: Vault,
    /// Word comparisons in progress. Never saved.
    sessions: Sessions,
    /// Radio connections that are up right now.
    links: OpenLinks,
    /// Envelopes lately taken in, so a copy sent on a second link to the
    /// same device is taken in once.
    seen: crate::link::Seen,
    /// Things that happened which the app has not been told yet.
    events: Vec<Value>,
    /// The number the next kept envelope is filed under, once worked out.
    next_kept: Option<u64>,
    /// Devices in range that have proved who they are, by key.
    peers: HashMap<String, Peer>,
    /// Sealed envelopes for devices in range, waiting to be turned into
    /// frames at the end of the request that made them.
    outgoing: Vec<Value>,
    /// How far each file transfer has got since the app started.
    files: file::Live,
    /// Which packets have been seen and handed on since the app started.
    relay: relay::Live,
    /// Packets being passed on, each with the device not to hand it back
    /// to, waiting to be turned into frames.
    passing: Vec<(Vec<u8>, Option<String>)>,
    /// Frames already made for one device, by key.
    direct: Vec<(String, Vec<Value>)>,
    /// Calls and voice rooms. Never saved.
    calls: Calls,
    /// The user's signing key, hex, once looked up. Every frame of a call
    /// needs it.
    my_key: Option<String>,
}

/// A device in range that has proved who it is.
struct Peer {
    /// Its public identity, hex. What anything for it is sealed to.
    identity: String,
    spaces: PeerSpaces,
}

/// The core's state between requests.
#[derive(Default)]
pub struct Core {
    open: Option<Open>,
}

impl Core {
    pub fn new() -> Self {
        Self::default()
    }

    /// Answers one request. Never panics on bad input.
    pub fn handle(&mut self, request: Value) -> Value {
        let outcome = serde_json::from_value::<Request>(request)
            .map_err(|e| CoreError::Invalid(format!("not a request: {e}")))
            .and_then(|request| self.run(request));
        match outcome {
            Ok(value) => json!({ "ok": value }),
            Err(e) => json!({ "err": { "code": e.code(), "message": e.to_string() } }),
        }
    }

    fn vault(&self) -> Result<&Vault> {
        self.open
            .as_ref()
            .map(|open| &open.vault)
            .ok_or(CoreError::NotOpen)
    }

    fn run(&mut self, request: Request) -> Result<Value> {
        match request {
            Request::Open { dir, master_key } => {
                // Close anything already open first: the vault file can
                // only be held once.
                self.open = None;
                let key = match KeySource::from_request(master_key.as_deref())? {
                    KeySource::Provided(key) => key,
                    KeySource::Platform => keyguard::load_or_create(&dir)?,
                };
                let vault = Vault::open(&dir, &key)?;
                let has_identity = vault.get(IDENTITY.0, IDENTITY.1)?.is_some();
                self.open = Some(Open {
                    dir,
                    vault,
                    sessions: Sessions::new(),
                    links: OpenLinks::new(),
                    seen: crate::link::Seen::default(),
                    events: Vec::new(),
                    next_kept: None,
                    peers: HashMap::new(),
                    outgoing: Vec::new(),
                    files: file::Live::default(),
                    relay: relay::Live::default(),
                    passing: Vec::new(),
                    direct: Vec::new(),
                    calls: Calls::default(),
                    my_key: None,
                });
                Ok(json!({ "has_identity": has_identity }))
            }
            Request::CreateIdentity { name } => {
                let name = clean_name(&name)?;
                let vault = self.vault()?;
                if vault.get(IDENTITY.0, IDENTITY.1)?.is_some() {
                    return Err(CoreError::AlreadyExists);
                }
                // The key made ahead, if the welcome screen made one and
                // stamped it while the user waited.
                let secret = match proof::take_draft(vault)? {
                    Some(draft) => draft,
                    None => IdentitySecret::generate()?,
                };
                // The key and the name are saved together or not at all.
                vault.batch(|tx| {
                    tx.put(IDENTITY.0, IDENTITY.1, &secret.to_bytes())?;
                    tx.put(NAME.0, NAME.1, name.as_bytes())
                })?;
                // A key made just now has no stamp yet. A short start on
                // it; the app finishes it, a slice at a time.
                proof::stamp_work(
                    vault,
                    &secret.signing_public(),
                    proof::FIRST_SLICE,
                    u64::MAX,
                )?;
                self.profile()
            }
            Request::IdentityDraft => {
                let draft = proof::draft(self.vault()?)?;
                Ok(json!({ "key": hexcode::encode(&draft.signing_public()) }))
            }
            Request::StampWork { millis, tries } => {
                let vault = self.vault()?;
                let key = match vault.get(IDENTITY.0, IDENTITY.1)? {
                    Some(secret) => IdentitySecret::from_bytes(&Zeroizing::new(secret))?,
                    None => proof::draft(vault)?,
                }
                .signing_public();
                proof::stamp_work(
                    vault,
                    &key,
                    std::time::Duration::from_millis(millis.min(1000)),
                    tries.unwrap_or(u64::MAX),
                )
            }
            Request::SetChoice { name, value } => {
                let mut settings = self.settings()?;
                match name.as_str() {
                    "requests_from" if REQUESTS_FROM.contains(&value.as_str()) => {
                        settings.requests_from = value;
                    }
                    "auto_lock" => match value.parse::<u32>() {
                        Ok(minutes) if AUTO_LOCK.contains(&minutes) => settings.auto_lock = minutes,
                        _ => return Err(CoreError::Invalid(format!("{value} is not a choice"))),
                    },
                    _ => {
                        return Err(CoreError::Invalid(format!(
                            "there is no choice {name}/{value}"
                        )))
                    }
                }
                let encoded = serde_json::to_vec(&settings).expect("settings are plain data");
                self.vault()?.put(SETTINGS.0, SETTINGS.1, &encoded)?;
                Ok(serde_json::to_value(settings).expect("settings are plain data"))
            }
            Request::Profile => self.profile(),
            Request::CodeWords { key, at } => {
                let key = hexcode::decode_exact::<SIGNING_LEN>(&key)?;
                let window = words::window_of(at.unwrap_or_else(words::unix_now));
                Ok(json!({
                    "words": words::code_words(&key, window),
                    // When they change next, in seconds since 1970.
                    "until": (window + 1) * words::CODE_WORDS_LAST,
                }))
            }
            Request::SetName { name } => {
                let name = clean_name(&name)?;
                let vault = self.vault()?;
                if vault.get(IDENTITY.0, IDENTITY.1)?.is_none() {
                    return Err(CoreError::Invalid("there is no identity yet".into()));
                }
                vault.put(NAME.0, NAME.1, name.as_bytes())?;
                // Contacts are told, each in an envelope kept until their
                // device has it. So is every space the user is in.
                for envelope in self.chat()?.name_envelopes()? {
                    self.keep(&envelope)?;
                    self.open
                        .as_mut()
                        .ok_or(CoreError::NotOpen)?
                        .outgoing
                        .push(by_any_way(envelope));
                }
                for (space, sealed) in self.with_spaces(|spaces, _| spaces.say_name_again())? {
                    self.pass_on(&space, &[sealed], None)?;
                }
                let profile = self.profile()?;
                self.with_deliveries(profile)
            }
            Request::Settings => {
                Ok(serde_json::to_value(self.settings()?).expect("settings are plain data"))
            }
            Request::SetSetting { group, name, value } => {
                let mut settings = self.settings()?;
                let was = *settings.switch(&group, &name)?;
                *settings.switch(&group, &name)? = value;
                let encoded = serde_json::to_vec(&settings).expect("settings are plain data");
                self.vault()?.put(SETTINGS.0, SETTINGS.1, &encoded)?;
                // Showing the photo, or no longer: contacts are told, so
                // that switching off takes it back from them.
                if group == "sharing" && name == "show_photo" && was != value {
                    let mut mine = self.my_photo()?;
                    mine.version += 1;
                    self.save_photo(&mine)?;
                    self.send_photo(None)?;
                    self.show_photo_in_spaces()?;
                }
                let reply = serde_json::to_value(settings).expect("settings are plain data");
                self.with_deliveries(reply)
            }
            Request::PhotoSet { preset, photo } => {
                let sound = match (preset, &photo) {
                    (Some(p), None) => p < crate::chat::PRESETS,
                    (None, Some(photo)) => crate::chat::sound_photo(photo),
                    _ => false,
                };
                if !sound {
                    return Err(CoreError::Invalid(
                        "a profile photo is one built-in picture or one small picture".into(),
                    ));
                }
                let mut mine = self.my_photo()?;
                mine.preset = preset;
                mine.photo = photo;
                mine.version += 1;
                self.save_photo(&mine)?;
                self.send_photo(None)?;
                self.show_photo_in_spaces()?;
                let reply = serde_json::to_value(&mine).expect("a photo is plain data");
                self.with_deliveries(reply)
            }
            Request::PhotoClear => {
                let mut mine = self.my_photo()?;
                mine.preset = None;
                mine.photo = None;
                mine.version += 1;
                self.save_photo(&mine)?;
                self.send_photo(None)?;
                self.show_photo_in_spaces()?;
                let reply = serde_json::to_value(&mine).expect("a photo is plain data");
                self.with_deliveries(reply)
            }
            Request::MyPhoto => {
                Ok(serde_json::to_value(self.my_photo()?).expect("a photo is plain data"))
            }
            Request::PhotoOf { who } => self.chat()?.photo_of(&who),
            Request::Card => Ok(self.chat()?.card()),
            Request::RequestChat {
                identity,
                note,
                scanned,
                known_as,
                how,
            } => {
                let sent = self
                    .chat()?
                    .request_chat(&identity, note, scanned, known_as)?;
                if scanned {
                    self.note_proof_for(&identity, how.as_deref().unwrap_or("qr"))?;
                }
                Ok(sent)
            }
            Request::VerifyScanned { identity, how } => {
                let verified = self.chat()?.verify_scanned(&identity)?;
                if let (true, Some(key)) = (verified["verified"] == true, verified["key"].as_str()) {
                    proof::record(self.vault()?, key, how.as_deref().unwrap_or("qr"))?;
                }
                Ok(verified)
            }
            Request::VerifyKey { key } => {
                let verified = self.chat()?.verify_key(&key)?;
                if verified["verified"] == true {
                    proof::record(self.vault()?, &key, "qr")?;
                }
                Ok(verified)
            }
            Request::InviteLink => self.chat()?.invite_link(),
            Request::CheckInvite { link } => self.chat()?.check_invite(&link),
            Request::RequestByInvite {
                link,
                note,
                scanned,
            } => {
                let sent = self.chat()?.request_by_invite(&link, note, scanned)?;
                if scanned {
                    let identity = self.chat()?.check_invite(&link)?["identity"]
                        .as_str()
                        .unwrap_or_default()
                        .to_string();
                    self.note_proof_for(&identity, "tap")?;
                }
                Ok(sent)
            }
            Request::CancelRequest { to } => self.chat()?.cancel_request(&to),
            Request::Requests => {
                let mut requests = self.chat()?.requests()?;
                // What the user has in common with each person asking.
                for request in requests["incoming"].as_array_mut().into_iter().flatten() {
                    let key = request["key"].as_str().unwrap_or_default().to_string();
                    request["common_space"] =
                        json!(self.with_spaces(|spaces, _| spaces.common_space(&key))?);
                }
                Ok(requests)
            }
            Request::Accept { from } => {
                let reply = self.chat()?.accept(&from)?;
                // A new contact is sent the photo, if the user shows it.
                self.send_photo(Some(&from))?;
                self.with_deliveries(reply)
            }
            Request::Decline { from } => self.chat()?.decline(&from),
            Request::Block { who } => self.chat()?.block(&who),
            Request::Unblock { who } => self.chat()?.unblock(&who),
            Request::Blocked => self.chat()?.blocked(),
            Request::CheckCode { with } => self.chat()?.check_code(&with),
            Request::CheckPaste { with, code } => {
                let checked = self.chat()?.check_paste(&with, &code)?;
                if checked["matched"] == true {
                    proof::record(self.vault()?, &with, "code")?;
                }
                Ok(checked)
            }
            Request::Contacts => {
                let mut contacts = self.chat()?.contacts()?;
                // How each verified contact was verified, and when.
                for contact in contacts.as_array_mut().into_iter().flatten() {
                    if contact["verified"] != true {
                        continue;
                    }
                    let key = contact["key"].as_str().unwrap_or_default().to_string();
                    if let Some((how, at)) = proof::lookup(self.vault()?, &key)? {
                        contact["verified_by"] = json!(how);
                        contact["verified_at"] = json!(at);
                    }
                }
                Ok(contacts)
            }
            Request::SendText {
                to,
                body,
                options,
                forwarded,
                sticker,
            } => {
                if let Some(sticker) = sticker {
                    self.chat()?.send_sticker(&to, sticker)
                } else if forwarded {
                    self.chat()?.forward(&to, &body)
                } else {
                    self.chat()?.send_text(&to, &body, options)
                }
            }
            Request::SendCard { to, contact } => self.chat()?.send_card(&to, &contact),
            Request::SendLocation { to, location } => self.chat()?.send_location(&to, location),
            Request::Vote { with, id, choice } => self.chat()?.vote(&with, &id, choice),
            Request::Thread { with } => self.chat()?.thread(&with),
            Request::MarkRead { with } => {
                // Whether the other person is told is the user's switch.
                let report = self.settings()?.sharing.read_receipts;
                self.chat()?.mark_read(&with, report)
            }
            Request::Held => {
                let mut counts = std::collections::BTreeMap::<String, u64>::new();
                for (_, record) in self.vault()?.list(OUTBOX)? {
                    *counts.entry(kept(&record)?.to).or_default() += 1;
                }
                Ok(counts
                    .into_iter()
                    .map(|(to, count)| json!({ "to": to, "count": count }))
                    .collect())
            }
            Request::SaveNote { body } => {
                let body = body.trim();
                if body.is_empty() || body.chars().count() > MAX_NOTE_CHARS {
                    return Err(CoreError::Invalid(
                        "a note must be between 1 and 16000 characters".into(),
                    ));
                }
                let vault = self.vault()?;
                // Numbered in the order written, so they list in that order.
                let key = (vault.list(NOTES)?.len() as u64).to_be_bytes();
                let sent_at = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                vault.put(
                    NOTES,
                    &key,
                    json!({ "body": body, "sent_at": sent_at })
                        .to_string()
                        .as_bytes(),
                )?;
                Ok(Value::Null)
            }
            Request::StickerBook => crate::stickers::book(self.vault()?),
            Request::StickerBookSave { book } => {
                crate::stickers::save_book(self.vault()?, &book).map(|()| Value::Null)
            }
            Request::StickerKeep { image } => crate::stickers::keep(self.vault()?, &image),
            Request::StickerPicture { id } => crate::stickers::picture(self.vault()?, &id),
            Request::StickerDrop { id } => {
                crate::stickers::drop(self.vault()?, &id).map(|()| Value::Null)
            }
            Request::Notes => self
                .vault()?
                .list(NOTES)?
                .iter()
                .map(|(_, record)| {
                    serde_json::from_slice::<Value>(record)
                        .map_err(|_| CoreError::Corrupt("a saved note is unreadable".into()))
                })
                .collect::<Result<Vec<Value>>>()
                .map(Value::Array),
            Request::SpaceCreate {
                name,
                kind,
                description,
            } => {
                let made =
                    self.with_spaces(|spaces, _| spaces.create(&name, &kind, &description))?;
                self.tell_devices_in_range()?;
                self.with_deliveries(made)
            }
            Request::Spaces => {
                self.with_spaces(|spaces, peers| spaces.list(peers.values().map(|p| &p.spaces)))
            }
            Request::SpaceChannel { space, channel } => {
                self.with_spaces(|spaces, _| spaces.channel(&space, &channel))
            }
            Request::SpacePost {
                space,
                channel,
                body,
                reply_to,
                options,
                mentions,
                everyone,
                roles,
                forwarded,
                location,
                sticker,
            } => {
                let (id, sealed) = self.with_spaces(|spaces, _| {
                    let new = NewPost {
                        body,
                        reply_to,
                        options,
                        mentions,
                        everyone,
                        roles,
                        forwarded,
                        location,
                        sticker,
                    };
                    spaces.post_mentioning(&space, &channel, new)
                })?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({ "id": id }))
            }
            Request::SpaceComments { space, post } => {
                self.with_spaces(|spaces, _| spaces.comments(&space, &post))
            }
            Request::SpacePin { space, target, on } => {
                let sealed = self.with_spaces(|spaces, _| spaces.pin(&space, &target, on))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceVote {
                space,
                target,
                choice,
            } => {
                let sealed = self.with_spaces(|spaces, _| spaces.vote(&space, &target, choice))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceDelete { space, target } => {
                let sealed = self.with_spaces(|spaces, _| spaces.delete(&space, &target))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceEditPost {
                space,
                target,
                body,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.edit_post(&space, &target, &body))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceEdit {
                space,
                name,
                description,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.edit(&space, name, description))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceNick {
                space,
                member,
                name,
            } => {
                let sealed = self.with_spaces(|spaces, _| spaces.nick(&space, &member, &name))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceWelcome {
                space,
                welcome,
                rules,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.welcome(&space, welcome, rules))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceIcon { space, icon } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.set_icon(&space, icon.as_deref()))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceChannelAdd { space, name, group } => {
                let (id, sealed) =
                    self.with_spaces(|spaces, _| spaces.channel_add(&space, &name, &group))?;
                self.space_changed(&space, sealed, json!({ "id": id }))
            }
            Request::SpaceChannelRename {
                space,
                channel,
                name,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.channel_rename(&space, &channel, &name))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceChannelRules {
                space,
                channel,
                slow,
                no_links,
                owners_only,
                disappear,
                max_len,
                writers,
            } => {
                let rules = ChannelRules {
                    slow,
                    no_links,
                    owners_only,
                    disappear,
                    max_len,
                    writers,
                };
                let sealed =
                    self.with_spaces(|spaces, _| spaces.channel_rules(&space, &channel, rules))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpacePostFile {
                space,
                channel,
                path,
                kind,
                name,
                seconds,
                body,
                reply_to,
            } => {
                let new = NewPost {
                    body,
                    reply_to,
                    ..NewPost::default()
                };
                let file = FileToPost {
                    path,
                    kind,
                    name,
                    seconds,
                };
                let (id, sealed) =
                    self.with_spaces(|spaces, _| spaces.post_file(&space, &channel, new, file))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({ "id": id }))
            }
            Request::SpaceFileGet { space, post } => {
                let asks = self.with_spaces(|spaces, peers| {
                    let Some((file, from)) = spaces.file_get(&space, &post)? else {
                        return Ok(Vec::new());
                    };
                    // Asked of every member in range. Whoever answers first
                    // is asked for the rest.
                    Ok(peers
                        .iter()
                        .filter(|(_, peer)| peer.spaces.shared.contains(&space))
                        .map(|(key, _)| {
                            (
                                key.clone(),
                                Wire::FileWant {
                                    space: space.clone(),
                                    file: file.clone(),
                                    from,
                                },
                            )
                        })
                        .collect::<Vec<_>>())
                })?;
                for (to, wire) in asks {
                    self.queue_wire(&to, &wire)?;
                }
                self.with_deliveries(json!({}))
            }
            Request::SpaceFileSave { space, post, dir } => {
                let path = self.with_spaces(|spaces, _| spaces.file_save(&space, &post, &dir))?;
                Ok(json!({ "path": path.display().to_string() }))
            }
            Request::SpaceRoleAdd { space, name, may } => {
                let (role, sealed) =
                    self.with_spaces(|spaces, _| spaces.role_add(&space, &name, may))?;
                self.space_changed(&space, sealed, json!({ "id": role }))
            }
            Request::SpaceRoleEdit {
                space,
                role,
                name,
                may,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.role_edit(&space, &role, name, may))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceRoleRemove { space, role } => {
                let sealed = self.with_spaces(|spaces, _| spaces.role_remove(&space, &role))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceGrant {
                space,
                member,
                role,
                on,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.grant(&space, &member, &role, on))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceBannedWords { space, words } => {
                let sealed = self.with_spaces(|spaces, _| spaces.banned_words(&space, words))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceWordFilter { space, on } => {
                let sealed = self.with_spaces(|spaces, _| spaces.word_filter(&space, on))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceChannelRemove { space, channel } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.channel_remove(&space, &channel))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceTimeout {
                space,
                member,
                seconds,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.timeout(&space, &member, seconds))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceName { space, name } => {
                match self.with_spaces(|spaces, _| spaces.go_by(&space, &name))? {
                    Some(sealed) => self.space_changed(&space, sealed, json!({})),
                    None => Ok(json!({})),
                }
            }
            Request::SpaceHandover { space, to } => {
                let sealed = self.with_spaces(|spaces, _| spaces.hand_over(&space, &to))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceResetLinks { space } => {
                // Each member is sent the new key, sealed to them alone
                // and kept until their device has it.
                for (to, identity, wire) in
                    self.with_spaces(|spaces, _| spaces.reset_links(&space))?
                {
                    let identity = PublicIdentity::from_bytes(&hexcode::decode(&identity)?)?;
                    let wire = serde_json::to_value(wire).expect("a space message is plain data");
                    let envelope = self.chat()?.seal_space_wire(&to, &identity, wire, true)?;
                    self.keep(&envelope)?;
                    self.open
                        .as_mut()
                        .ok_or(CoreError::NotOpen)?
                        .outgoing
                        .push(by_any_way(envelope));
                }
                self.tell_devices_in_range()?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceDeleteSpace { space } => {
                let sealed = self.with_spaces(|spaces, _| spaces.close(&space))?;
                self.space_changed(&space, sealed, json!({}))
            }
            Request::SpaceRole {
                space,
                member,
                admin,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.set_role(&space, &member, admin))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceRemove { space, member } => {
                let (sealed, rekeying) =
                    self.with_spaces(|spaces, _| spaces.remove(&space, &member))?;
                // Everyone in range hears of it, the person removed too:
                // that is how their device knows to let go of the space.
                self.pass_on(&space, &[sealed], None)?;
                // Then each member who is staying is sent the new key,
                // sealed to them alone and kept until their device has it.
                for (to, identity, wire) in rekeying {
                    let identity = PublicIdentity::from_bytes(&hexcode::decode(&identity)?)?;
                    let wire = serde_json::to_value(wire).expect("a space message is plain data");
                    let envelope = self.chat()?.seal_space_wire(&to, &identity, wire, true)?;
                    self.keep(&envelope)?;
                    self.open
                        .as_mut()
                        .ok_or(CoreError::NotOpen)?
                        .outgoing
                        .push(by_any_way(envelope));
                }
                self.tell_devices_in_range()?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceReact {
                space,
                target,
                kind,
                on,
            } => {
                let sealed =
                    self.with_spaces(|spaces, _| spaces.react(&space, &target, &kind, on))?;
                self.pass_on(&space, &[sealed], None)?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceRead { space, channel } => {
                self.with_spaces(|spaces, _| spaces.mark_read(&space, &channel))?;
                Ok(Value::Null)
            }
            Request::SpaceMute { space, on } => {
                self.with_spaces(|spaces, _| spaces.mute(&space, on))?;
                Ok(Value::Null)
            }
            Request::SpaceMembers { space } => {
                let settings = self.settings()?;
                let mine = settings.status;
                let my_away = settings.away;
                let me = hexcode::encode(&self.me()?.0.signing_public());
                self.with_spaces(|spaces, peers| {
                    // The user sees their own choice, invisible included.
                    // Anyone else, as they last said, if in range and in
                    // this space.
                    let in_space = |key: &str| {
                        peers
                            .get(key)
                            .filter(|peer| peer.spaces.shared.contains(&space))
                    };
                    let mut list = spaces.member_list_with(&space, |key| {
                        if key == me {
                            return Some(mine.clone());
                        }
                        in_space(key).and_then(|peer| peer.spaces.status.clone())
                    })?;
                    // And whether each said they are away, the same way.
                    for member in list.as_array_mut().into_iter().flatten() {
                        let key = member["key"].as_str().unwrap_or_default().to_string();
                        member["away"] = json!(if key == me {
                            my_away.clone()
                        } else {
                            in_space(&key).and_then(|peer| peer.spaces.away.clone())
                        });
                    }
                    Ok(list)
                })
            }
            Request::SpaceJoin { space } => {
                self.with_spaces(|spaces, _| spaces.join(&space))?;
                self.tell_devices_in_range()?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceLeave { space } => {
                if let Some(goodbye) = self.with_spaces(|spaces, _| spaces.leave(&space))? {
                    self.pass_on(&space, &[goodbye], None)?;
                }
                self.tell_devices_in_range()?;
                self.with_deliveries(json!({}))
            }
            Request::SpaceLink { space, lasts } => {
                let (link, expires) =
                    self.with_spaces(|spaces, _| spaces.link_lasting(&space, lasts))?;
                Ok(json!({ "link": link, "expires_at": expires }))
            }
            Request::SpaceLinkCheck { link } => {
                self.with_spaces(|spaces, _| spaces.check_link(&link))
            }
            Request::SpaceJoinLink { link } => {
                let id = self.with_spaces(|spaces, _| spaces.join_link(&link))?;
                self.tell_devices_in_range()?;
                self.with_deliveries(json!({ "id": id }))
            }
            Request::SpaceInvite { space, to } => {
                // An invite hands over the space's key, so it goes only to
                // someone the user has accepted, sealed to them, and is
                // kept until their device has it.
                let identity = self.chat()?.contact_identity(&to)?;
                // Inviting someone who was removed lets them back.
                if let Some(back) = self.with_spaces(|spaces, _| spaces.allow_back(&space, &to))? {
                    self.pass_on(&space, &[back], None)?;
                }
                let invite = self.with_spaces(|spaces, _| spaces.invite(&space))?;
                let invite = serde_json::to_value(invite).expect("a space message is plain data");
                self.chat()?.seal_space_wire(&to, &identity, invite, true)
            }
            Request::FileViewed { id } => {
                let (with, seen) = self.with_files(|files| files.viewed(&id))?;
                self.say_about_file(&with, &seen)?;
                self.with_deliveries(json!({}))
            }
            Request::FileSend {
                to,
                path,
                name,
                once,
            } => {
                // Files go to contacts only, like messages.
                self.chat()?.contact_identity(&to)?;
                let (id, name, size, offer) =
                    self.with_files(|files| files.offer(&to, &path, name.as_deref(), once))?;
                self.chat()?.file_message(&to, true, &id, &name, size)?;
                self.say_about_file(&to, &offer)?;
                self.with_deliveries(json!({ "id": id }))
            }
            Request::FileAccept { id, dir } => {
                let (with, answer) = self.with_files(|files| files.accept(&id, &dir))?;
                self.say_about_file(&with, &answer)?;
                self.with_deliveries(json!({}))
            }
            Request::FileDecline { id } => {
                let (with, answer) = self.with_files(|files| files.decline(&id))?;
                self.say_about_file(&with, &answer)?;
                self.with_deliveries(json!({}))
            }
            Request::FileCancel { id } => {
                if let Some((with, cancel)) = self.with_files(|files| files.cancel(&id))? {
                    self.say_about_file(&with, &cancel)?;
                }
                self.with_deliveries(json!({}))
            }
            Request::FilePause { id } => {
                self.with_files(|files| files.pause(&id, true))?;
                Ok(Value::Null)
            }
            Request::FileResume { id } => {
                self.with_files(|files| files.pause(&id, false))?;
                let peers: Vec<String> = self
                    .open
                    .as_ref()
                    .ok_or(CoreError::NotOpen)?
                    .peers
                    .keys()
                    .cloned()
                    .collect();
                for peer in peers {
                    self.send_pieces(&peer)?;
                }
                self.with_deliveries(json!({}))
            }
            Request::Files => self.with_files(|files| files.list()),
            Request::Carrying => {
                let (packets, bytes) = self.with_relay(|relay| relay.carrying())?;
                Ok(json!({ "packets": packets, "bytes": bytes }))
            }
            Request::Purge { before } => Ok(json!({ "removed": self.chat()?.purge(before)? })),
            Request::Expire { now } => Ok(json!({ "removed": self.chat()?.expire(now)? })),
            Request::SetTimer { with, seconds } => self.chat()?.set_timer(&with, seconds),
            Request::ChatDeleteMine { with, ids } => self.chat()?.delete_mine(&with, &ids),
            Request::ChatUnsend { with, ids } => self.chat()?.unsend(&with, &ids),
            Request::ChatClear { with } => self.chat()?.clear(&with),
            Request::ChatDelete { with } => self.chat()?.delete_chat(&with),
            Request::LockState => {
                let (set, wrong) = crate::lock::state(self.vault()?)?;
                Ok(json!({ "set": set, "wrong": wrong }))
            }
            Request::LockSet { passcode, current } => {
                crate::lock::set(self.vault()?, &passcode, current.as_deref())?;
                Ok(Value::Null)
            }
            Request::LockClear { passcode } => {
                crate::lock::clear(self.vault()?, &passcode)?;
                Ok(Value::Null)
            }
            Request::LockCheck { passcode } => {
                let (ok, wrong) = crate::lock::check(self.vault()?, &passcode)?;
                // The user may have chosen to lose everything rather than
                // have it guessed at.
                let erase = !ok
                    && wrong >= crate::lock::ERASE_AFTER
                    && self.settings()?.device.erase_on_wrong_passcode;
                if erase {
                    self.run(Request::Wipe)?;
                }
                Ok(json!({ "ok": ok, "wrong": wrong, "erased": erase }))
            }
            Request::Receive { envelope } => self.take_in(&envelope),
            Request::VerifyStart { with } => self.chat()?.verify_start(&with),
            Request::FastAsk { to } => self.chat()?.fast_ask(&to),
            // Each of these is the user's to share or not. With the switch
            // off, nothing is made to send.
            Request::Typing { to } => {
                if !self.settings()?.sharing.typing {
                    return Ok(Value::Null);
                }
                self.chat()?.typing(&to)
            }
            // Told to members of the space in range, as in a chat: once,
            // and only with the switch on. Someone invisible tells nobody
            // they are writing, as that would show they are here.
            Request::SpaceTyping { space, channel } => {
                let settings = self.settings()?;
                if !settings.sharing.typing || settings.status == "invisible" {
                    return Ok(Value::Null);
                }
                let wire = self.with_spaces(|spaces, _| spaces.typing(&space, &channel))?;
                let members: Vec<String> = self
                    .open
                    .as_ref()
                    .ok_or(CoreError::NotOpen)?
                    .peers
                    .iter()
                    .filter(|(_, peer)| peer.spaces.shared.contains(&space))
                    .map(|(key, _)| key.clone())
                    .collect();
                for member in members {
                    self.queue_wire(&member, &wire)?;
                }
                self.with_deliveries(json!({}))
            }
            Request::SetAway { away } => {
                let away = away
                    .map(|note| note.split_whitespace().collect::<Vec<_>>().join(" "))
                    .map(|note| note.chars().take(crate::chat::MAX_AWAY_CHARS).collect());
                let mut settings = self.settings()?;
                if settings.away != away {
                    settings.away = away.clone();
                    let encoded = serde_json::to_vec(&settings).expect("settings are plain data");
                    self.vault()?.put(SETTINGS.0, SETTINGS.1, &encoded)?;
                    // Fellow members in range are told with the status;
                    // contacts in an envelope kept until they have it.
                    self.tell_status(None)?;
                    for envelope in self.chat()?.away_envelopes(away.as_deref())? {
                        self.keep(&envelope)?;
                        self.open
                            .as_mut()
                            .ok_or(CoreError::NotOpen)?
                            .outgoing
                            .push(by_any_way(envelope));
                    }
                }
                let reply = serde_json::to_value(settings).expect("settings are plain data");
                self.with_deliveries(reply)
            }
            Request::SetStatus { status } => {
                if !STATUSES.contains(&status.as_str()) {
                    return Err(CoreError::Invalid(format!("there is no status {status}")));
                }
                let mut settings = self.settings()?;
                settings.status = status;
                let encoded = serde_json::to_vec(&settings).expect("settings are plain data");
                self.vault()?.put(SETTINGS.0, SETTINGS.1, &encoded)?;
                self.tell_status(None)?;
                let reply = serde_json::to_value(settings).expect("settings are plain data");
                self.with_deliveries(reply)
            }
            Request::Here { to, active } => {
                let settings = self.settings()?;
                // Invisible means nobody is told the user is here.
                if !settings.sharing.show_online || settings.status == "invisible" {
                    return Ok(Value::Null);
                }
                self.chat()?.here(&to, active)
            }
            Request::FastOffer {
                to,
                network,
                pass,
                joins,
            } => self.chat()?.fast_offer(&to, &network, &pass, joins),
            Request::VerifyWords { with } => self.chat()?.verify_words(&with),
            Request::VerifyConfirm { with, matched } => {
                let answered = self.chat()?.verify_confirm(&with, matched)?;
                if matched {
                    proof::record(self.vault()?, &with, "words")?;
                }
                Ok(answered)
            }
            Request::CallStart { to, video } => {
                // Only a contact, and only one in range: a call is now or
                // never, so nothing is kept for later.
                self.chat()?.contact_identity(&to)?;
                let open = self.open.as_ref().ok_or(CoreError::NotOpen)?;
                if link_to(&open.links, &to).is_none() {
                    return Err(CoreError::Invalid("they are not in range".into()));
                }
                let (call, wire) = self.calls_mut()?.start(&to, video)?;
                self.send_call_wire(&to, &wire)?;
                self.with_deliveries(json!({ "call": call }))
            }
            Request::CallAnswer { call } => {
                let me = self.my_key()?;
                let (with, wire, words) = self.calls_mut()?.answer(&me, &call)?;
                self.send_call_wire(&with, &wire)?;
                self.with_deliveries(json!({ "call": call, "words": words }))
            }
            Request::CallEnd { call, reason } => {
                let reason = match reason.as_deref() {
                    Some(r @ ("declined" | "unanswered" | "no_wifi")) => r.to_string(),
                    _ => "hangup".to_string(),
                };
                if let Some((with, wire)) = self.calls_mut()?.end(&call, &reason) {
                    // Someone no longer a contact is simply not told.
                    let _ = self.send_call_wire(&with, &wire);
                }
                self.with_deliveries(json!({}))
            }
            Request::CallTell {
                call,
                muted,
                camera,
                screen,
            } => {
                let (with, wire) = self.calls_mut()?.tell(&call, muted, camera, screen)?;
                self.send_call_wire(&with, &wire)?;
                self.with_deliveries(json!({}))
            }
            Request::CallMediaOut { call, kind, data } => {
                let data = hexcode::decode(&data)?;
                let me = self.my_key()?;
                let (frame, to, level) = self.calls_mut()?.media_out(&me, &call, &kind, &data)?;
                Ok(json!({ "frame": hexcode::encode(&frame), "to": to, "level": level }))
            }
            Request::CallMediaIn { link, frame } => {
                let frame = hexcode::decode(&frame)?;
                let open = self.open.as_ref().ok_or(CoreError::NotOpen)?;
                // Who sent it is whoever proved who they are on this link.
                let from = open
                    .links
                    .get(&link)
                    .and_then(|l| l.peer_key())
                    .ok_or_else(|| {
                        CoreError::Invalid("nobody has proved who they are on that link".into())
                    })?;
                open.calls.media_in(&from, &frame)
            }
            Request::Calls => Ok(self.calls_mut()?.list()),
            Request::RoomJoin {
                space,
                channel,
                alone,
                muted,
            } => {
                let me = self.my_key()?;
                let (owner_muted, owner_deaf) =
                    self.with_spaces(|s, _| s.voice_standing(&space, &channel))?;
                let place = (space.clone(), channel.clone());
                let owner = OwnerSays {
                    muted: owner_muted,
                    deaf: owner_deaf,
                };
                let step = self
                    .calls_mut()?
                    .room_join(&me, place.clone(), alone, muted, owner)?;
                for (left_space, left_channel) in &step.left {
                    self.room_tell(left_space, left_channel, &RoomWire::Left, None)?;
                }
                if let Some((inside, ask)) = &step.ask {
                    self.room_tell(&space, &channel, ask, Some(inside))?;
                }
                if step.here {
                    if let Some(here) = self.calls_mut()?.here_again(&place) {
                        self.room_tell(&space, &channel, &here, None)?;
                    }
                }
                let view = self.room_view(&space, &channel)?;
                self.with_deliveries(view)
            }
            Request::RoomTick {
                space,
                channel,
                muted,
                deaf,
                camera,
                screen,
            } => {
                let place = (space.clone(), channel.clone());
                if !self.calls_mut()?.in_room(&place) {
                    return Err(CoreError::Invalid("the user is not in that room".into()));
                }
                match self.with_spaces(|s, _| s.voice_standing(&space, &channel)) {
                    Ok((owner_muted, owner_deaf)) => {
                        let owner = OwnerSays {
                            muted: owner_muted,
                            deaf: owner_deaf,
                        };
                        let here = self.calls_mut()?.room_here(
                            &place,
                            muted,
                            deaf,
                            camera,
                            screen,
                            Some(owner),
                        );
                        if let Some(here) = here {
                            self.room_tell(&space, &channel, &here, None)?;
                        }
                    }
                    // No longer a member, or the room is gone.
                    Err(_) => {
                        self.calls_mut()?.room_leave(&place);
                        self.room_tell(&space, &channel, &RoomWire::Left, None)?;
                    }
                }
                let view = self.room_view(&space, &channel)?;
                self.with_deliveries(view)
            }
            Request::RoomLeave { space, channel } => {
                if self
                    .calls_mut()?
                    .room_leave(&(space.clone(), channel.clone()))
                {
                    self.room_tell(&space, &channel, &RoomWire::Left, None)?;
                }
                self.with_deliveries(json!({}))
            }
            Request::Rooms => Ok(Value::Array(self.calls_mut()?.rooms())),
            Request::SpaceVoice {
                space,
                member,
                mute,
                deafen,
            } => {
                let sealed = self.with_spaces(|s, _| s.voice(&space, &member, mute, deafen))?;
                self.pass_on(&space, &[sealed], None)?;
                self.refresh_rooms(&[&space])?;
                self.with_deliveries(json!({}))
            }
            Request::LinkOpen { link, max_frame } => {
                let (me, name) = self.me()?;
                // A stranger only gets the name if the user allows it.
                let shared = self
                    .settings()?
                    .sharing
                    .find_by_name
                    .then_some(name.as_str());
                let (state, frames) = Link::open(max_frame, &me, shared)?;
                self.open
                    .as_mut()
                    .ok_or(CoreError::NotOpen)?
                    .links
                    .insert(link, state);
                Ok(json!({ "frames": hex_frames(&frames) }))
            }
            Request::LinkReceive { link, frame } => {
                let frame = hexcode::decode(&frame)?;
                let (me, _) = self.me()?;
                let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
                let state = open
                    .links
                    .get_mut(&link)
                    .ok_or_else(|| CoreError::Invalid(format!("link {link} is not open")))?;
                let outcome = state.receive(link, &frame, &me)?;
                let mut frames = outcome.frames;

                // If this frame is what proved who the peer is, send them
                // everything kept for them, oldest first. Each stays kept
                // until their device answers that it has it.
                let mut proved_now = Vec::new();
                for proved in outcome.events.iter().filter(|e| e["kind"] == "peer") {
                    for (_, record) in open.vault.list(OUTBOX)? {
                        let waiting = kept(&record)?;
                        if proved["key"] == waiting.to.as_str() {
                            frames.extend(
                                state.envelope_frames(&hexcode::decode(&waiting.envelope)?),
                            );
                        }
                    }
                    if let (Some(key), Some(identity)) =
                        (proved["key"].as_str(), proved["identity"].as_str())
                    {
                        proved_now.push((key.to_string(), identity.to_string()));
                    }
                }
                open.events.extend(outcome.events);

                // Then say which spaces this device is in, in a way only a
                // fellow member can read, so the two can compare notes.
                for (key, identity) in proved_now {
                    let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
                    open.peers.entry(key.clone()).or_insert(Peer {
                        identity,
                        spaces: PeerSpaces::default(),
                    });
                    // One of the two starts the comparing. Which one is
                    // settled by their keys, so both agree without asking.
                    let starts = hexcode::encode(&me.signing_public()) > key;
                    let hello = self.with_spaces(|spaces, peers| {
                        let peer = peers.get_mut(&key).expect("it was just added");
                        spaces.hello(&key, &mut peer.spaces, starts)
                    })?;
                    self.queue_wire(&key, &hello)?;
                    // And where any file between the two had got to, so
                    // it carries on from there.
                    for wire in self.with_files(|files| files.met(&key))? {
                        self.say_about_file(&key, &wire)?;
                    }
                    self.send_pieces(&key)?;
                    // And everything being carried for other people, the
                    // user's own kept envelopes among it: this device may
                    // be on the way to whoever they are for.
                    self.hand_over_carried(&key)?;
                    // Files moving to or from people out of range may be
                    // able to go by way of this device.
                    self.try_files_another_way()?;
                }

                for envelope in outcome.envelopes {
                    // The same envelope sent on Bluetooth and on Wi-Fi at
                    // once is taken in from whichever came first.
                    let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
                    let links = &open.links;
                    if !open.seen.first(link, &envelope, |l| links.contains_key(&l)) {
                        continue;
                    }
                    let result = self.take_in(&hexcode::encode(&envelope))?;
                    let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
                    if result["event"]["kind"] != "ignored" {
                        open.events.push(result["event"].clone());
                    }
                    // Whatever the core wants to answer goes to whoever
                    // wrote this. That is nearly always the device on this
                    // link, and then it goes straight back. If a device
                    // handed over something written by someone else, the
                    // answer finds its own way to the writer.
                    let peer = open.links.get(&link).and_then(|l| l.peer_key());
                    for reply in result["replies"].as_array().into_iter().flatten() {
                        match (open.links.get(&link), reply["envelope"].as_str()) {
                            (Some(state), Some(envelope))
                                if reply["to"].as_str() == peer.as_deref() =>
                            {
                                frames.extend(state.envelope_frames(&hexcode::decode(envelope)?));
                            }
                            _ => open.outgoing.push(by_any_way(reply.clone())),
                        }
                    }
                }

                // Packets other devices are passing on.
                let from = self
                    .open
                    .as_ref()
                    .and_then(|open| open.links.get(&link))
                    .and_then(|l| l.peer_key());
                for packet in outcome.relays {
                    let Some(from) = &from else { break };
                    match self.with_relay(|relay| relay.accept(from, &packet))? {
                        Verdict::Drop => {}
                        // The app redraws its map and passes the news on.
                        Verdict::Mapped => self
                            .open
                            .as_mut()
                            .ok_or(CoreError::NotOpen)?
                            .events
                            .push(json!({ "kind": "mesh" })),
                        // The user chose not to carry other people's mail.
                        Verdict::Onward(_) if !self.settings()?.safety.relay => {}
                        Verdict::Onward(onward) => {
                            self.open
                                .as_mut()
                                .ok_or(CoreError::NotOpen)?
                                .passing
                                .push((onward, Some(from.clone())));
                        }
                        Verdict::Mine { envelope, hops } => {
                            let result = self.take_in(&hexcode::encode(&envelope))?;
                            let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
                            if result["event"]["kind"] != "ignored" {
                                open.events.push(result["event"].clone());
                            }
                            // The app is told how they were reached, so
                            // it can say "2 hops, through Noor".
                            if let Some(sender) = result["event"]["from"].as_str() {
                                open.events.push(json!({ "kind": "heard", "from": sender, "hops": hops, "via": from }));
                            }
                            // The answer finds its own way back.
                            open.outgoing.extend(
                                result["replies"]
                                    .as_array()
                                    .into_iter()
                                    .flatten()
                                    .cloned()
                                    .map(by_any_way),
                            );
                        }
                    }
                }
                Ok(json!({ "frames": hex_frames(&frames), "deliveries": self.deliveries()? }))
            }
            Request::LinkSend { envelope } => {
                let to = envelope["to"].as_str().unwrap_or_default().to_string();
                let bytes = hexcode::decode(envelope["envelope"].as_str().unwrap_or_default())?;
                if to.is_empty() || bytes.is_empty() {
                    return Err(CoreError::Invalid("there is nothing to send".into()));
                }
                // An envelope that carries an answer number must not be
                // lost. It is kept, sealed as it is, before anything is
                // handed to a radio, and stays kept until the answer comes.
                let ack = envelope["ack"].as_str().map(str::to_string);
                if let Some(ack) = &ack {
                    let key = self.next_kept_key()?;
                    let record = Kept {
                        to: to.clone(),
                        envelope: hexcode::encode(&bytes),
                        ack: ack.clone(),
                    };
                    let record =
                        serde_json::to_vec(&record).expect("a kept envelope is plain data");
                    self.vault()?.put(OUTBOX, &key, &record)?;
                }
                let open = self.open.as_ref().ok_or(CoreError::NotOpen)?;
                // Direct, if a device in range has proved it is this
                // person: on every link that reaches them, so whichever
                // gets there first counts.
                let mut found = crate::link::deliveries_for(&open.links, &to, &bytes, None);
                if !found.is_empty() {
                    let first = found.remove(0);
                    return Ok(json!({
                        "delivered": true,
                        "link": first["link"],
                        "class": first["class"],
                        "frames": first["frames"],
                        "deliveries": found,
                    }));
                }
                // Otherwise by way of whoever is in range, if it is
                // something that is being kept until it arrives.
                if ack.is_some() {
                    let packet =
                        self.with_relay(|relay| relay.send(&hexcode::decode(&to)?, &bytes))?;
                    self.open
                        .as_mut()
                        .ok_or(CoreError::NotOpen)?
                        .passing
                        .push((packet, None));
                }
                self.with_deliveries(
                    json!({ "delivered": false, "queued": ack.is_some(), "frames": [] }),
                )
            }
            Request::LinkClose { link } => {
                let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
                let mut still_reached = None;
                if let Some(key) = open.links.remove(&link).and_then(|l| l.peer_key()) {
                    // Gone only if no other connection reaches them.
                    if open
                        .links
                        .values()
                        .any(|l| l.peer_key().as_deref() == Some(key.as_str()))
                    {
                        still_reached = Some(key.clone());
                    } else {
                        open.peers.remove(&key);
                    }
                    open.events
                        .push(json!({ "kind": "peer_gone", "link": link, "key": key }));
                }
                // A Wi-Fi link can die without a word while Bluetooth to
                // the same person lives on. Whatever was on the dead one
                // is lost, and nobody is going to walk out of range and
                // back to set it right. So what is being kept for them is
                // sent again on the link that is left (they drop anything
                // they already have), and files carry on from where each
                // side had got to.
                if let Some(key) = still_reached {
                    for (_, record) in self.vault()?.list(OUTBOX)? {
                        let waiting = kept(&record)?;
                        if waiting.to == key {
                            let again = json!({ "to": waiting.to, "envelope": waiting.envelope });
                            self.open
                                .as_mut()
                                .ok_or(CoreError::NotOpen)?
                                .outgoing
                                .push(again);
                        }
                    }
                    for wire in self.with_files(|files| files.lost_a_way(&key))? {
                        self.say_about_file(&key, &wire)?;
                    }
                    self.send_pieces(&key)?;
                }
                self.with_deliveries(json!({}))
            }
            Request::MeshShare { peers, now } => self.mesh_share(peers, now),
            Request::Mesh { now } => {
                let open = self.open.as_ref().ok_or(CoreError::NotOpen)?;
                let current: Vec<String> = open.peers.keys().cloned().collect();
                let now = now.unwrap_or_else(relay::now_ms);
                Ok(open.relay.view(&current, now).to_json())
            }
            Request::Poll => {
                let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
                Ok(Value::Array(std::mem::take(&mut open.events)))
            }
            Request::Close => {
                // Every write is already on disk, so this only lets go of
                // the file.
                self.open = None;
                Ok(Value::Null)
            }
            Request::Wipe => {
                // Files the app saved for the user go too, and the files
                // kept from channels.
                self.with_files(|files| files.erase_received())?;
                if let Some(open) = &self.open {
                    let _ = std::fs::remove_dir_all(open.dir.join(SPACE_FILES));
                }
                let open = self.open.take().ok_or(CoreError::NotOpen)?;
                let dir = open.dir.clone();
                // Closes the file so it can be deleted.
                drop(open);
                // The key goes first. If the wipe is cut short after this
                // line, what is left on disk can no longer be opened.
                keyguard::destroy(&dir)?;
                Vault::destroy(&dir)?;
                Ok(Value::Null)
            }
            Request::PhotoClean { path, dir } => Ok(clean_photo(&path, &dir)),
            Request::Version => Ok(json!({
                "core": env!("CARGO_PKG_VERSION"),
                "schema": SCHEMA_VERSION,
            })),
        }
    }

    /// Takes in one envelope, whichever way it arrived, and stops keeping
    /// anything it shows to have been delivered.
    fn take_in(&mut self, envelope: &str) -> Result<Value> {
        let mut result = self.chat()?.receive(envelope)?;
        if result["event"]["kind"] == "request" && !self.may_ask(&result["event"])? {
            // Not someone the user lets ask. Declined, and not told.
            let from = result["event"]["from"].as_str().unwrap_or_default().to_string();
            self.chat()?.decline(&from)?;
            result["event"] = json!({ "kind": "ignored" });
        }
        let event = &result["event"];
        // Someone the user asked has said yes: they are sent the photo, if
        // the user shows it.
        if event["kind"] == "accepted" {
            if let Some(from) = event["from"].as_str().map(str::to_string) {
                self.send_photo(Some(&from))?;
            }
        }
        let event = &result["event"];
        if event["kind"] == "delivered" {
            let vault = self.vault()?;
            let answered: Vec<&str> = event["ids"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .collect();
            for (key, record) in vault.list(OUTBOX)? {
                let waiting = kept(&record)?;
                // Only the person an envelope was for can answer for it.
                if event["from"] == waiting.to.as_str() && answered.contains(&waiting.ack.as_str())
                {
                    vault.delete(OUTBOX, &key)?;
                }
            }
        }
        if event["kind"] == "space_wire" {
            return self.take_space_wire(result);
        }
        if event["kind"] == "call_wire" {
            return self.take_call(result);
        }
        if event["kind"] == "file_wire" || event["kind"] == "file_piece" {
            return self.take_file(result);
        }
        Ok(result)
    }

    /// Acts on a message about a file, or a piece of one. What comes back
    /// tells the app only which transfer may look different now.
    fn take_file(&mut self, mut result: Value) -> Result<Value> {
        let event = result["event"].take();
        result["event"] = json!({ "kind": "ignored" });
        let from = event["from"].as_str().unwrap_or_default().to_string();
        let outcome = if event["kind"] == "file_piece" {
            let piece = hexcode::decode(event["piece"].as_str().unwrap_or_default())?;
            self.with_files(|files| files.piece(&from, &piece))?
        } else {
            let Ok(wire) = serde_json::from_value::<file::Wire>(event["wire"].clone()) else {
                return Ok(result);
            };
            let contact = event["contact"] == true;
            self.with_files(|files| files.receive(&from, contact, wire))?
        };
        if let Some((id, name, size)) = &outcome.offered {
            self.chat()?.file_message(&from, false, id, name, *size)?;
        }
        for wire in &outcome.replies {
            if let Some(answer) = self.seal_about_file(&from, wire)? {
                result["replies"]
                    .as_array_mut()
                    .expect("replies is always a list")
                    .push(answer);
            }
        }
        // An answer or an "I have this much" may free more to be sent.
        self.send_pieces(&from)?;
        if let Some(id) = outcome.changed {
            result["event"] = json!({ "kind": "file", "id": id, "from": from });
        }
        Ok(result)
    }

    fn with_files<T>(&mut self, work: impl FnOnce(&mut Files) -> Result<T>) -> Result<T> {
        let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
        work(&mut Files {
            vault: &open.vault,
            live: &mut open.files,
        })
    }

    /// Seals a message about a file for a contact. One that must arrive is
    /// also put with the kept envelopes, to be sent again until answered.
    fn seal_about_file(&mut self, to: &str, wire: &file::Wire) -> Result<Option<Value>> {
        // Someone who is no longer a contact is told nothing more.
        let Ok(identity) = self.chat()?.contact_identity(to) else {
            return Ok(None);
        };
        let ack = if wire.kept() {
            Some(hexcode::encode(
                crate::seal::random_bytes::<16>()?.as_slice(),
            ))
        } else {
            None
        };
        let json = serde_json::to_value(wire).expect("a file message is plain data");
        let mut envelope = self
            .chat()?
            .seal_file_wire(to, &identity, json, ack.clone())?;
        // What is not kept is only worth having now. If the person is out
        // of range it is passed along by whoever is in range, and nobody
        // carries it.
        if ack.is_none() {
            envelope["passing"] = json!(true);
        }
        if let Some(ack) = ack {
            let key = self.next_kept_key()?;
            let record = Kept {
                to: to.to_string(),
                envelope: envelope["envelope"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
                ack,
            };
            let record = serde_json::to_vec(&record).expect("a kept envelope is plain data");
            self.vault()?.put(OUTBOX, &key, &record)?;
        }
        Ok(Some(envelope))
    }

    /// Seals a message about a file and queues it for the device it is for.
    /// If that device is not in range it goes by way of whoever is.
    fn say_about_file(&mut self, to: &str, wire: &file::Wire) -> Result<()> {
        if let Some(envelope) = self.seal_about_file(to, wire)? {
            self.open
                .as_mut()
                .ok_or(CoreError::NotOpen)?
                .outgoing
                .push(by_any_way(envelope));
        }
        Ok(())
    }

    /// Queues the next pieces of every file being sent to `peer`. If they
    /// are not in range, the pieces are passed along by whoever is: still
    /// sealed to `peer`, and kept by nobody on the way.
    fn send_pieces(&mut self, peer: &str) -> Result<()> {
        let open = self.open.as_ref().ok_or(CoreError::NotOpen)?;
        let in_range = open.peers.contains_key(peer);
        if !in_range && open.peers.is_empty() {
            return Ok(());
        }
        let pieces = self.with_files(|files| files.pieces_for(peer))?;
        if pieces.is_empty() {
            return Ok(());
        }
        let Ok(identity) = self.chat()?.contact_identity(peer) else {
            return Ok(());
        };
        for piece in pieces {
            let mut envelope = self.chat()?.seal_piece(peer, &identity, &piece.bytes)?;
            if !in_range {
                envelope["passing"] = json!(true);
            }
            // Pieces go after chat: those of small files first.
            envelope["class"] = json!(if piece.small { "small" } else { "big" });
            self.open
                .as_mut()
                .ok_or(CoreError::NotOpen)?
                .outgoing
                .push(envelope);
        }
        Ok(())
    }

    /// Someone new is in range. For every file moving to or from a person
    /// who is not, says where it has got to and tries its next pieces, in
    /// case the newcomer is a way through.
    fn try_files_another_way(&mut self) -> Result<()> {
        let in_range: Vec<String> = self
            .open
            .as_ref()
            .ok_or(CoreError::NotOpen)?
            .peers
            .keys()
            .cloned()
            .collect();
        let (say, sending) =
            self.with_files(|files| files.out_of_range(|peer| in_range.iter().any(|p| p == peer)))?;
        for (peer, wire) in say {
            self.say_about_file(&peer, &wire)?;
        }
        for peer in sending {
            self.send_pieces(&peer)?;
        }
        Ok(())
    }

    /// Acts on something another device said about spaces. What comes back
    /// tells the app only that its spaces may look different now.
    fn take_space_wire(&mut self, mut result: Value) -> Result<Value> {
        let event = result["event"].take();
        result["event"] = json!({ "kind": "ignored" });
        let from = event["from"].as_str().unwrap_or_default().to_string();
        let Ok(wire) = serde_json::from_value::<Wire>(event["wire"].clone()) else {
            return Ok(result);
        };
        // An invite is welcome from a contact, or from anyone not blocked
        // if the user switched on "let strangers add me to groups".
        let strangers = self.settings()?.sharing.add_to_groups;
        let may_invite = event["contact"] == true || (strangers && event["blocked"] != true);
        let outcome = self.with_spaces(|spaces, peers| {
            // Someone not in range shares nothing that can be acted on,
            // but may still have sent an invite.
            let mut passing = PeerSpaces::default();
            let known = peers
                .get_mut(&from)
                .map_or(&mut passing, |peer| &mut peer.spaces);
            spaces.receive(&from, wire, known, may_invite)
        })?;

        let identity = self
            .open
            .as_ref()
            .and_then(|open| open.peers.get(&from))
            .map(|peer| peer.identity.clone());
        if let Some(identity) = identity {
            let identity = PublicIdentity::from_bytes(&hexcode::decode(&identity)?)?;
            for wire in &outcome.replies {
                let wire = serde_json::to_value(wire).expect("a space message is plain data");
                let answer = self
                    .chat()?
                    .seal_space_wire(&from, &identity, wire, false)?;
                result["replies"]
                    .as_array_mut()
                    .expect("replies is always a list")
                    .push(answer);
            }
        }
        // What was new to this device is new to other members in range too.
        for (space, items) in &outcome.fresh {
            self.pass_on(space, items, Some(&from))?;
        }
        // Whoever runs a space may have muted or deafened someone in the
        // voice room the user is in. That holds from now.
        let spaces_now: Vec<&String> = outcome.fresh.iter().map(|(space, _)| space).collect();
        self.refresh_rooms(&spaces_now)?;
        if outcome.rekeyed {
            // The tags shown to devices in range came from the old key.
            self.tell_devices_in_range()?;
        }
        // Once the two are known to share a space, each says how it is.
        self.tell_status(Some(&from))?;
        if outcome.changed {
            result["event"] = json!({ "kind": "space" });
        } else if let Some((space, channel)) = outcome.typing {
            result["event"] = json!({
                "kind": "space_typing",
                "space": space,
                "channel": channel,
                "from": from,
            });
        } else if let Some((space, channel, said)) = outcome.room {
            if let Some(told) = self.take_room(&from, space, channel, said)? {
                result["event"] = told;
            }
        }
        Ok(result)
    }

    /// Acts on what a fellow member said about a voice room. The space has
    /// checked they are a member and it is a voice room.
    fn take_room(
        &mut self,
        from: &str,
        space: String,
        channel: String,
        said: Value,
    ) -> Result<Option<Value>> {
        let Ok(wire) = serde_json::from_value::<RoomWire>(said) else {
            return Ok(None);
        };
        let me = self.my_key()?;
        let place = (space.clone(), channel.clone());
        let (told, replies) = self
            .calls_mut()?
            .room_receive(&me, from, place.clone(), wire);
        let only = [from.to_string()];
        for reply in replies {
            self.room_tell(&space, &channel, &reply, Some(&only))?;
        }
        // Let in, or moved to the room everyone else is in: the user says
        // so to everyone in range.
        if told.as_ref().is_some_and(|t| t["kind"] == "room_in") {
            if let Some(here) = self.calls_mut()?.here_again(&place) {
                self.room_tell(&space, &channel, &here, None)?;
            }
        }
        Ok(told)
    }

    /// Acts on what a contact said about a call between the two.
    fn take_call(&mut self, mut result: Value) -> Result<Value> {
        let event = result["event"].take();
        result["event"] = json!({ "kind": "ignored" });
        let from = event["from"].as_str().unwrap_or_default().to_string();
        let Ok(wire) = serde_json::from_value::<call::Wire>(event["wire"].clone()) else {
            return Ok(result);
        };
        let me = self.my_key()?;
        let (told, replies) = self.calls_mut()?.receive(&me, &from, wire);
        for reply in replies {
            let reply = serde_json::to_value(&reply).expect("a call message is plain data");
            let answer = self.chat()?.seal_call_wire(&from, reply)?;
            result["replies"]
                .as_array_mut()
                .expect("replies is always a list")
                .push(answer);
        }
        if let Some(told) = told {
            result["event"] = told;
        }
        Ok(result)
    }

    fn calls_mut(&mut self) -> Result<&mut Calls> {
        Ok(&mut self.open.as_mut().ok_or(CoreError::NotOpen)?.calls)
    }

    /// The user's signing key, hex. Looked up once.
    fn my_key(&mut self) -> Result<String> {
        if let Some(key) = self.open.as_ref().and_then(|open| open.my_key.clone()) {
            return Ok(key);
        }
        let (me, _) = self.me()?;
        let key = hexcode::encode(&me.signing_public());
        self.open.as_mut().ok_or(CoreError::NotOpen)?.my_key = Some(key.clone());
        Ok(key)
    }

    /// Seals something about a call for the contact it is with and queues
    /// it. Sent now or never.
    fn send_call_wire(&mut self, to: &str, wire: &call::Wire) -> Result<()> {
        let wire = serde_json::to_value(wire).expect("a call message is plain data");
        let envelope = self.chat()?.seal_call_wire(to, wire)?;
        self.open
            .as_mut()
            .ok_or(CoreError::NotOpen)?
            .outgoing
            .push(envelope);
        Ok(())
    }

    /// Tells members of `space` in range something about one of its voice
    /// rooms: all of them, or `only` these.
    fn room_tell(
        &mut self,
        space: &str,
        channel: &str,
        wire: &RoomWire,
        only: Option<&[String]>,
    ) -> Result<()> {
        let message = Wire::Room {
            space: space.to_string(),
            channel: channel.to_string(),
            call: serde_json::to_value(wire).expect("a room message is plain data"),
        };
        let members: Vec<String> = self
            .open
            .as_ref()
            .ok_or(CoreError::NotOpen)?
            .peers
            .iter()
            .filter(|(key, peer)| {
                peer.spaces.shared.contains(space) && only.is_none_or(|only| only.contains(key))
            })
            .map(|(key, _)| key.clone())
            .collect();
        for member in members {
            self.queue_wire(&member, &message)?;
        }
        Ok(())
    }

    /// Reads again who is muted and deafened in the voice rooms the user
    /// is in, for these spaces. A room the user may no longer be in is
    /// left.
    fn refresh_rooms(&mut self, spaces: &[&String]) -> Result<()> {
        let places: Vec<(String, String)> = self
            .calls_mut()?
            .joined_places()
            .into_iter()
            .filter(|(space, _)| spaces.contains(&space))
            .collect();
        for place in places {
            let standing = self.with_spaces(|s, _| s.voice_standing(&place.0, &place.1));
            match standing {
                Ok((muted, deaf)) => self
                    .calls_mut()?
                    .room_owner(&place, OwnerSays { muted, deaf }),
                Err(_) => {
                    if self.calls_mut()?.room_leave(&place) {
                        self.room_tell(&place.0, &place.1, &RoomWire::Left, None)?;
                    }
                }
            }
        }
        Ok(())
    }

    /// One voice room as the app shows it.
    fn room_view(&mut self, space: &str, channel: &str) -> Result<Value> {
        Ok(self
            .calls_mut()?
            .rooms()
            .into_iter()
            .find(|r| r["space"] == space && r["channel"] == channel)
            .unwrap_or_else(
                || json!({ "space": space, "channel": channel, "people": [], "joined": false }),
            ))
    }

    /// Tells fellow members in range how the user is: every device in
    /// range that shares a space with this one, or just `only`, each once
    /// for each change. Someone invisible tells nobody anything, except
    /// that whoever was told a status before is told "offline", so it is
    /// not left showing.
    fn tell_status(&mut self, only: Option<&str>) -> Result<()> {
        let settings = self.settings()?;
        let status = settings.status;
        let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
        let mut telling = Vec::new();
        for (key, peer) in open.peers.iter_mut() {
            if only.is_some_and(|only| only != key) || peer.spaces.shared.is_empty() {
                continue;
            }
            let say = if status == "invisible" {
                match peer.spaces.told.as_deref() {
                    None | Some("offline") => continue,
                    Some(_) => "offline",
                }
            } else {
                status.as_str()
            };
            // Being away goes with the status, and never from someone
            // invisible.
            let away = settings.away.clone().filter(|_| say != "offline");
            if peer.spaces.told.as_deref() == Some(say) && peer.spaces.told_away == away {
                continue;
            }
            peer.spaces.told = Some(say.to_string());
            peer.spaces.told_away = away.clone();
            telling.push((
                key.clone(),
                Wire::Status {
                    status: say.to_string(),
                    away,
                },
            ));
        }
        for (key, wire) in telling {
            self.queue_wire(&key, &wire)?;
        }
        Ok(())
    }

    /// After the owner changed what a space is: passes the change to
    /// members in range, and shows everyone in range the space as it now
    /// is, since a public one is listed nearby under its name.
    fn space_changed(&mut self, space: &str, sealed: Vec<u8>, reply: Value) -> Result<Value> {
        self.pass_on(space, &[sealed], None)?;
        self.tell_devices_in_range()?;
        self.with_deliveries(reply)
    }

    /// Puts a sealed envelope that carries an answer number with the kept
    /// ones, to be sent again until its answer comes.
    fn keep(&mut self, envelope: &Value) -> Result<()> {
        let (Some(to), Some(sealed), Some(ack)) = (
            envelope["to"].as_str(),
            envelope["envelope"].as_str(),
            envelope["ack"].as_str(),
        ) else {
            return Ok(());
        };
        let record = Kept {
            to: to.to_string(),
            envelope: sealed.to_string(),
            ack: ack.to_string(),
        };
        let key = self.next_kept_key()?;
        self.vault()?.put(
            OUTBOX,
            &key,
            &serde_json::to_vec(&record).expect("a kept envelope is plain data"),
        )
    }

    /// Runs `work` with the user's spaces and what is known about each
    /// device in range.
    fn with_spaces<T>(
        &mut self,
        work: impl FnOnce(&Spaces, &mut HashMap<String, Peer>) -> Result<T>,
    ) -> Result<T> {
        let (me, name) = self.me()?;
        // Members are shown the user's photo only if they show it at all.
        let photo = match self.settings()?.sharing.show_photo {
            true => self.my_photo()?.photo,
            false => None,
        };
        let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
        let files = open.dir.join(SPACE_FILES);
        let spaces = Spaces {
            vault: &open.vault,
            me: &me,
            my_name: &name,
            my_photo: photo.as_deref(),
            files: &files,
        };
        work(&spaces, &mut open.peers)
    }

    /// Seals something about spaces for one device in range and queues it.
    fn queue_wire(&mut self, to: &str, wire: &Wire) -> Result<()> {
        let Some(identity) = self
            .open
            .as_ref()
            .and_then(|open| open.peers.get(to))
            .map(|peer| peer.identity.clone())
        else {
            return Ok(());
        };
        let identity = PublicIdentity::from_bytes(&hexcode::decode(&identity)?)?;
        let wire = serde_json::to_value(wire).expect("a space message is plain data");
        let envelope = self.chat()?.seal_space_wire(to, &identity, wire, false)?;
        self.open
            .as_mut()
            .ok_or(CoreError::NotOpen)?
            .outgoing
            .push(envelope);
        Ok(())
    }

    /// After the user's own spaces change: shows every device in range the
    /// new set, still readable only by fellow members, and asks each to
    /// compare notes.
    fn tell_devices_in_range(&mut self) -> Result<()> {
        let keys: Vec<String> = self
            .open
            .as_ref()
            .ok_or(CoreError::NotOpen)?
            .peers
            .keys()
            .cloned()
            .collect();
        for key in keys {
            let hello = self.with_spaces(|spaces, peers| {
                let peer = peers.get_mut(&key).expect("the key came from this map");
                spaces.hello(&key, &mut peer.spaces, true)
            })?;
            self.queue_wire(&key, &hello)?;
        }
        Ok(())
    }

    /// Passes sealed items to every member of `space` in range, except the
    /// one they came from.
    fn pass_on(&mut self, space: &str, items: &[Vec<u8>], except: Option<&str>) -> Result<()> {
        let members: Vec<String> = self
            .open
            .as_ref()
            .ok_or(CoreError::NotOpen)?
            .peers
            .iter()
            .filter(|(key, peer)| {
                Some(key.as_str()) != except && peer.spaces.shared.contains(space)
            })
            .map(|(key, _)| key.clone())
            .collect();
        for member in members {
            for wire in Spaces::push(space, items) {
                self.queue_wire(&member, &wire)?;
            }
        }
        Ok(())
    }

    /// Turns what is queued into frames, each for the link that reaches
    /// the device it is for. An envelope for someone not in range goes by
    /// way of everyone who is, if it is marked as allowed to.
    fn deliveries(&mut self) -> Result<Value> {
        let mut deliveries = Vec::new();
        let queued = std::mem::take(&mut self.open.as_mut().ok_or(CoreError::NotOpen)?.outgoing);
        for envelope in queued {
            let to = envelope["to"].as_str().unwrap_or_default().to_string();
            let bytes = hexcode::decode(envelope["envelope"].as_str().unwrap_or_default())?;
            let open = self.open.as_ref().ok_or(CoreError::NotOpen)?;
            // Direct, to a device that has proved it is this person: chat
            // on every link that reaches them, a piece on the fastest.
            let direct =
                crate::link::deliveries_for(&open.links, &to, &bytes, envelope["class"].as_str());
            if !direct.is_empty() {
                deliveries.extend(direct);
            } else if envelope["passing"] == true {
                let packet = self
                    .with_relay(|relay| Ok(relay.send_passing(&hexcode::decode(&to)?, &bytes)))?;
                self.open
                    .as_mut()
                    .ok_or(CoreError::NotOpen)?
                    .passing
                    .push((packet, None));
            } else if envelope["any_way"] == true {
                let packet = self.with_relay(|relay| relay.send(&hexcode::decode(&to)?, &bytes))?;
                self.open
                    .as_mut()
                    .ok_or(CoreError::NotOpen)?
                    .passing
                    .push((packet, None));
            }
        }

        let direct = std::mem::take(&mut self.open.as_mut().ok_or(CoreError::NotOpen)?.direct);
        for (peer, frames) in direct {
            let open = self.open.as_ref().ok_or(CoreError::NotOpen)?;
            if let Some((link, _)) = link_to(&open.links, &peer) {
                deliveries.push(json!({ "link": link, "frames": frames }));
            }
        }

        // Packets being passed on go to every device in range, except the
        // one each came from.
        let passing = std::mem::take(&mut self.open.as_mut().ok_or(CoreError::NotOpen)?.passing);
        for (packet, came_from) in passing {
            let open = self.open.as_ref().ok_or(CoreError::NotOpen)?;
            let mut handed = Vec::new();
            for (link, state) in &open.links {
                let Some(peer) = state.peer_key() else {
                    continue;
                };
                if Some(&peer) == came_from.as_ref() || handed.contains(&peer) {
                    continue;
                }
                // A big packet is most likely a piece of a file on its way
                // through, and waits behind chat.
                let class = crate::link::class_of(packet.len(), None);
                let lane = match class {
                    "chat" => crate::link::Lane::Chat,
                    _ => crate::link::Lane::Bulk,
                };
                let frames = hex_frames(&state.relay_frames_on(&packet, lane));
                deliveries.push(json!({ "link": link, "class": class, "frames": frames }));
                handed.push(peer);
            }
            self.with_relay(|relay| {
                for peer in &handed {
                    relay.gave(&packet, peer);
                }
                Ok(())
            })?;
        }
        Ok(json!(deliveries))
    }

    fn with_relay<T>(&mut self, work: impl FnOnce(&mut Relay) -> Result<T>) -> Result<T> {
        let (me, _) = self.me()?;
        let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
        work(&mut Relay {
            vault: &open.vault,
            live: &mut open.relay,
            my_tag: relay::tag_of(&me.signing_public()),
        })
    }

    /// Queues this device's map for each device in range that is due one.
    /// Only devices that have proved who they are count, whatever the
    /// app says. Someone invisible names nobody and asks not to be named.
    fn mesh_share(&mut self, peers: Vec<relay::Neighbour>, now: Option<u64>) -> Result<Value> {
        let (me, _) = self.me()?;
        let me = hexcode::encode(&me.signing_public());
        let settings = self.settings()?;
        let hidden = settings.status == "invisible";
        let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
        let peers: Vec<relay::Neighbour> = peers
            .into_iter()
            .filter(|peer| open.peers.contains_key(&peer.key))
            .collect();
        let now = now.unwrap_or_else(relay::now_ms);
        let maps = open
            .relay
            .share(&me, &peers, hidden, settings.safety.relay, now);
        for (peer, map) in maps {
            if let Some((_, state)) = link_to(&open.links, &peer) {
                let frames = hex_frames(&state.relay_frames(&map));
                open.direct
                    .push((peer, frames.into_iter().map(Value::from).collect()));
            }
        }
        self.with_deliveries(json!({}))
    }

    /// Hands a device that has just come into range everything being
    /// carried that it has not had: packets from others, and the user's
    /// own kept envelopes for people who are not in range.
    fn hand_over_carried(&mut self, peer: &str) -> Result<()> {
        self.open
            .as_mut()
            .ok_or(CoreError::NotOpen)?
            .relay
            .met(peer);
        let kept_for_others: Vec<Kept> = self
            .vault()?
            .list(OUTBOX)?
            .iter()
            .map(|(_, record)| kept(record))
            .collect::<Result<Vec<Kept>>>()?
            .into_iter()
            .filter(|waiting| waiting.to != peer)
            .collect();
        for waiting in kept_for_others {
            // Kept under the same packet id every time, so a device that
            // has had it already is not handed it again.
            self.with_relay(|relay| {
                relay.send(
                    &hexcode::decode(&waiting.to)?,
                    &hexcode::decode(&waiting.envelope)?,
                )
            })?;
        }
        let packets = self.with_relay(|relay| relay.for_peer(peer))?;
        let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
        let Some((_, state)) = link_to(&open.links, peer) else {
            return Ok(());
        };
        // Queued as frames for this one device only: it has not had them,
        // and everyone else in range was handed them when they arrived.
        let frames: Vec<Value> = packets
            .iter()
            .flat_map(|packet| hex_frames(&state.relay_frames(packet)))
            .map(Value::from)
            .collect();
        if !frames.is_empty() {
            open.direct.push((peer.to_string(), frames));
        }
        Ok(())
    }

    /// Adds what is waiting to be sent to a reply.
    fn with_deliveries(&mut self, mut reply: Value) -> Result<Value> {
        reply["deliveries"] = self.deliveries()?;
        Ok(reply)
    }

    /// Kept envelopes are filed under a rising number, so they are sent
    /// again in the order they were written.
    fn next_kept_key(&mut self) -> Result<Vec<u8>> {
        let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
        let next = match open.next_kept {
            Some(next) => next,
            None => open
                .vault
                .list(OUTBOX)?
                .last()
                .and_then(|(key, _)| key.get(..8)?.try_into().ok())
                .map_or(0, |last: [u8; 8]| u64::from_be_bytes(last) + 1),
        };
        open.next_kept = Some(next + 1);
        Ok(next.to_be_bytes().to_vec())
    }

    fn my_photo(&self) -> Result<MyPhoto> {
        Ok(match self.vault()?.get(PHOTO.0, PHOTO.1)? {
            Some(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
            None => MyPhoto::default(),
        })
    }

    fn save_photo(&self, photo: &MyPhoto) -> Result<()> {
        let bytes = serde_json::to_vec(photo).expect("a photo is plain data");
        self.vault()?.put(PHOTO.0, PHOTO.1, &bytes)
    }

    /// Tells contacts the user's profile photo, every contact or just
    /// `only`, as far as the user shows it: with the switch off, they are
    /// told there is none. Each envelope is kept until it arrives, and
    /// sent now to whoever is in range. A new contact with the switch off
    /// is told nothing.
    /// Tells every space the user is in their photo as it now is, or that
    /// there is none to show.
    fn show_photo_in_spaces(&mut self) -> Result<()> {
        for (space, sealed) in self.with_spaces(|spaces, _| spaces.show_photo_again())? {
            self.pass_on(&space, &[sealed], None)?;
        }
        Ok(())
    }

    fn send_photo(&mut self, only: Option<&str>) -> Result<()> {
        let mine = self.my_photo()?;
        let shown = self.settings()?.sharing.show_photo;
        if only.is_some() && !shown {
            return Ok(());
        }
        let (preset, photo) = if shown {
            (mine.preset, mine.photo)
        } else {
            (None, None)
        };
        for envelope in self
            .chat()?
            .photo_envelopes(only, preset, photo, mine.version)?
        {
            self.keep(&envelope)?;
            self.open
                .as_mut()
                .ok_or(CoreError::NotOpen)?
                .outgoing
                .push(by_any_way(envelope));
        }
        Ok(())
    }

    /// The user's own keys and name.
    fn me(&self) -> Result<(IdentitySecret, String)> {
        let vault = self.vault()?;
        let secret = vault
            .get(IDENTITY.0, IDENTITY.1)?
            .ok_or_else(|| CoreError::Invalid("there is no identity yet".into()))?;
        let me = IdentitySecret::from_bytes(&Zeroizing::new(secret))?;
        let name = vault.get(NAME.0, NAME.1)?.unwrap_or_default();
        Ok((me, String::from_utf8_lossy(&name).into_owned()))
    }

    /// Everything a chat action needs: the vault, the user's own keys and
    /// name, and the word comparisons in progress.
    fn chat(&mut self) -> Result<Chat<'_>> {
        let (me, my_name) = self.me()?;
        let open = self.open.as_mut().ok_or(CoreError::NotOpen)?;
        Ok(Chat {
            vault: &open.vault,
            me,
            my_name,
            sessions: &mut open.sessions,
        })
    }

    fn settings(&self) -> Result<Settings> {
        match self.vault()?.get(SETTINGS.0, SETTINGS.1)? {
            None => Ok(Settings::default()),
            Some(bytes) => serde_json::from_slice(&bytes)
                .map_err(|_| CoreError::Corrupt("the saved settings are unreadable".into())),
        }
    }

    /// Whether the user's "who can ask me" choice lets this new request
    /// in. Someone who came with one of the user's own links always may.
    fn may_ask(&mut self, request: &Value) -> Result<bool> {
        if request["invited"] == true {
            return Ok(true);
        }
        let from = request["from"].as_str().unwrap_or_default().to_string();
        Ok(match self.settings()?.requests_from.as_str() {
            "nobody" => false,
            "spaces" => self
                .with_spaces(|spaces, _| spaces.common_space(&from))?
                .is_some(),
            _ => true,
        })
    }

    /// Notes how someone the user is asking, from `identity` read off their
    /// own device, will have been verified once they accept.
    fn note_proof_for(&mut self, identity: &str, how: &str) -> Result<()> {
        let identity = PublicIdentity::from_bytes(&hexcode::decode(identity)?)?;
        proof::record(self.vault()?, &hexcode::encode(&identity.signing_key), how)
    }

    fn profile(&self) -> Result<Value> {
        let vault = self.vault()?;
        let Some(secret) = vault.get(IDENTITY.0, IDENTITY.1)? else {
            return Ok(Value::Null);
        };
        let secret = Zeroizing::new(secret);
        let public = IdentitySecret::from_bytes(&secret)?.public();
        let name = vault.get(NAME.0, NAME.1)?.unwrap_or_default();
        Ok(json!({
            "name": String::from_utf8_lossy(&name),
            "fingerprint": public.fingerprint(),
            "spoken_code": public.spoken_code(),
            "signing_key": hexcode::encode(&public.signing_key),
        }))
    }
}

/// The connection to use for someone who can be reached by more than one:
/// the one that carries the most in a frame. Bluetooth and Wi-Fi can both
/// reach the same device, and Wi-Fi is many times faster.
fn link_to<'a>(links: &'a OpenLinks, peer: &str) -> Option<(&'a u32, &'a Link)> {
    links
        .iter()
        .filter(|(_, link)| link.peer_key().as_deref() == Some(peer))
        .max_by_key(|(_, link)| link.room())
}

/// Marks an envelope as one that may go by way of other devices if the
/// person it is for is not in range. Answers and anything kept are. What
/// only makes sense between two devices in range (comparing notes on a
/// space, pieces of a file) is not.
fn by_any_way(mut envelope: Value) -> Value {
    envelope["any_way"] = json!(true);
    envelope
}

/// Writes a copy of the picture at `path` into `dir`, under the same
/// name, with what the camera noted about it taken out. The original is
/// not touched. Says so if it could not: the file is not a kind of
/// picture this can clean, is broken, or is too big to hold in memory.
fn clean_photo(path: &str, dir: &str) -> Value {
    const MOST: u64 = 64 << 20;
    let copy = || -> Option<std::path::PathBuf> {
        let path = std::path::Path::new(path);
        if std::fs::metadata(path).ok()?.len() > MOST {
            return None;
        }
        let cleaned = crate::photo::clean(&std::fs::read(path).ok()?)?;
        std::fs::create_dir_all(dir).ok()?;
        let copy = std::path::Path::new(dir).join(path.file_name()?);
        std::fs::write(&copy, cleaned).ok()?;
        Some(copy)
    };
    match copy() {
        Some(copy) => json!({ "cleaned": true, "path": copy }),
        None => json!({ "cleaned": false }),
    }
}

/// A sealed envelope being kept until the person it is for answers.
#[derive(Serialize, Deserialize)]
struct Kept {
    to: String,
    envelope: String,
    /// The number their device answers with.
    ack: String,
}

fn kept(record: &[u8]) -> Result<Kept> {
    serde_json::from_slice(record)
        .map_err(|_| CoreError::Corrupt("a kept message is unreadable".into()))
}

fn hex_frames(frames: &[Vec<u8>]) -> Vec<String> {
    frames.iter().map(|f| hexcode::encode(f)).collect()
}

/// A name may be anything, but not nothing.
fn clean_name(name: &str) -> Result<String> {
    let name = name.trim();
    if name.is_empty() {
        return Err(CoreError::Invalid("a name cannot be empty".into()));
    }
    if name.chars().count() > 64 {
        return Err(CoreError::Invalid(
            "a name can be at most 64 characters".into(),
        ));
    }
    Ok(name.to_string())
}
