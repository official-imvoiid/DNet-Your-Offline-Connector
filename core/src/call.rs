//! Calls: from one person to another, and voice rooms in spaces.
//!
//! What is said to set a call up travels like any other message: sealed to
//! the person and signed (`chat.rs`), or for a voice room, sealed to each
//! fellow member in range (`space.rs`). The sound itself cannot: sealing
//! fifty frames a second with a fresh post-quantum key each would cost far
//! too much. So each call agrees a key of its own, and every frame of
//! sound or picture is sealed with that.
//!
//! **Between two people.** The caller makes a key pair for this call alone
//! and puts its public half in the offer. Whoever answers encapsulates a
//! secret to it (HPKE with X-Wing, as for envelopes) and both take the
//! call's key from that secret, bound to the call and to both identities.
//! The key pair is never stored and is gone when the call ends, so someone
//! who later steals either person's identity still cannot open a recording
//! of the call.
//!
//! **A voice room.** Whoever opens an empty room makes a random key for it.
//! A member who comes in makes a key pair for asking, and someone already
//! inside hands over the room's key sealed to it. Two people who open the
//! same room at once each make one; the room with the lower number wins and
//! the other side moves over to it.
//!
//! **The call key words.** Four words come from the key itself, so everyone
//! holding the same key sees the same words, and anyone who sees different
//! ones is not in the same call.
//!
//! **Media frames** go only over a fast link (the local network), each
//! sealed with AES-256-GCM under a key taken from the call's. The device it
//! came from is part of what is checked, so a member of a room cannot speak
//! as another: the receiver names the sender from the link the frame came
//! on, which the link proved (`link.rs`).
//!
//! **A shared screen** is pictures too, sent as frames of their own kind
//! so they never mix with the camera's. Each frame holds one small piece of
//! the screen, and only pieces that changed are sent (`screen_share.dart`):
//! what is on the screen is as private as anything said, so it is sealed
//! exactly the same way. Whether someone is sharing travels with whether
//! they are muted, in `State` and `Here`.
//!
//! Nothing here is ever saved.

use std::collections::{HashMap, HashSet};
use std::time::{SystemTime, UNIX_EPOCH};

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use hkdf::Hkdf;
use hpke::aead::AesGcm256;
use hpke::kdf::HkdfSha256;
use hpke::kem::XWing;
use hpke::{Deserializable, Kem, OpModeR, OpModeS, Serializable};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::Sha256;
use zeroize::Zeroizing;

use crate::codec;
use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::seal::{self, random_bytes};
use crate::words::WORDS;

type EphSecret = <XWing as Kem>::PrivateKey;
type EphPublic = <XWing as Kem>::PublicKey;
type Encapped = <XWing as Kem>::EncappedKey;

/// The first byte of every media frame. A link frame (`link.rs`) starts
/// with its flags, 0 to 3, so the two are never mixed up.
pub const MEDIA_MARK: u8 = 0xd7;
const AUDIO: u8 = 1;
const VIDEO: u8 = 2;
const SCREEN: u8 = 3;
/// The mark, the kind, and the call's number.
const HEADER: usize = 2 + 16;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;

/// The most one frame of media carries. A frame on the local network holds
/// 16 KB (`lan_radio.dart`); this leaves room for the rest.
pub const MAX_MEDIA: usize = 15 * 1024;

/// How long someone counts as in a voice room after they last said so. A
/// device inside says so every few seconds.
pub const PRESENT_FOR: u64 = 12_000;

const CALL_INFO: &[u8] = b"dnet call v1";
const ROOM_INFO: &[u8] = b"dnet voice room v1";

/// What two devices say to each other about a call between them. Always
/// inside a sealed envelope (`chat.rs`), and only between contacts.
#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "c", rename_all = "snake_case")]
pub(crate) enum Wire {
    /// "Will you take a call?" `eph` is the public half of a key pair made
    /// for this call alone.
    Offer {
        call: String,
        eph: String,
        #[serde(default)]
        video: bool,
    },
    /// "It is ringing here."
    Ring { call: String },
    /// "Yes." `enc` is a secret encapsulated to the offer's key.
    Answer { call: String, enc: String },
    /// "My microphone is off", "my camera is on" or "I am sharing my
    /// screen", during the call.
    State {
        call: String,
        muted: bool,
        camera: bool,
        #[serde(default)]
        screen: bool,
    },
    /// The call is over, or never began: "hangup", "declined", "busy",
    /// "unanswered" or "no_wifi".
    End { call: String, reason: String },
}

/// What members say to each other about a voice room. Always inside a
/// sealed envelope, between fellow members of the space (`space.rs`).
#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "r", rename_all = "snake_case")]
pub(crate) enum RoomWire {
    /// "I am in this room." Said every few seconds while there.
    Here {
        room: String,
        #[serde(default)]
        muted: bool,
        /// Has the sound off: nothing need be sent to them.
        #[serde(default)]
        deaf: bool,
        #[serde(default)]
        camera: bool,
        /// Is sharing their screen with the room.
        #[serde(default)]
        screen: bool,
    },
    /// "Let me in." The public half of a key pair made for asking.
    Ask { eph: String },
    /// The room's number and key, sealed to the asker's key pair.
    Key {
        room: String,
        enc: String,
        sealed: String,
    },
    /// "I have left."
    Left,
}

/// How far a call between two people has got.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Phase {
    /// The user called. Nothing heard back yet.
    Calling,
    /// The user called and it is ringing there.
    Ringing,
    /// Someone is calling the user.
    Incoming,
    /// Answered. Sound can flow.
    Live,
}

impl Phase {
    fn name(self) -> &'static str {
        match self {
            Phase::Calling => "calling",
            Phase::Ringing => "ringing",
            Phase::Incoming => "incoming",
            Phase::Live => "live",
        }
    }
}

struct Direct {
    /// The other person's signing key, hex.
    with: String,
    /// The user started it.
    mine: bool,
    video: bool,
    phase: Phase,
    /// The caller's private half of the call's key pair, until the answer.
    eph: Option<Box<EphSecret>>,
    /// The caller's public half, kept by whoever is called until they
    /// answer.
    their_eph: Option<String>,
    key: Option<Zeroizing<[u8; 32]>>,
}

/// A voice room the user is in, or asking to be let into.
#[derive(Default)]
struct Joined {
    /// The room's number and key, once known.
    room: Option<([u8; 16], Zeroizing<[u8; 32]>)>,
    /// The key pair made for asking, while asking.
    asking: Option<Box<EphSecret>>,
    muted: bool,
    deaf: bool,
    camera: bool,
    screen: bool,
    /// Members whoever runs the space has muted or deafened in its voice
    /// rooms, as the space last said.
    owner_muted: HashSet<String>,
    owner_deaf: HashSet<String>,
}

/// Someone in a voice room, as they last said.
#[derive(Clone, PartialEq)]
struct Presence {
    room: [u8; 16],
    at: u64,
    muted: bool,
    deaf: bool,
    camera: bool,
    screen: bool,
}

type Place = (String, String);

/// Every call and voice room, while the app runs.
#[derive(Default)]
pub(crate) struct Calls {
    direct: HashMap<[u8; 16], Direct>,
    joined: HashMap<Place, Joined>,
    /// Who is in each voice room of the user's spaces, as heard.
    present: HashMap<Place, HashMap<String, Presence>>,
    /// Counts the frames the user sends, so a receiver can put them in
    /// order.
    seq: u32,
}

/// Members whoever runs a space has muted, and deafened, in its voice
/// rooms.
#[derive(Default, Clone)]
pub(crate) struct OwnerSays {
    pub muted: HashSet<String>,
    pub deaf: HashSet<String>,
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn invalid(message: &str) -> CoreError {
    CoreError::Invalid(message.into())
}

fn call_id(text: &str) -> Result<[u8; 16]> {
    hexcode::decode_exact::<16>(text).map_err(|_| invalid("that is not a call"))
}

fn key_bytes(key: &str) -> Result<Vec<u8>> {
    hexcode::decode(key)
}

fn derive<const N: usize>(key: &[u8; 32], info: &[u8]) -> [u8; N] {
    let mut out = [0u8; N];
    Hkdf::<Sha256>::new(None, key)
        .expand(info, &mut out)
        .expect("the output is far shorter than HKDF's limit");
    out
}

/// The four words everyone holding `key` sees.
pub(crate) fn words(key: &[u8; 32]) -> Vec<&'static str> {
    derive::<4>(key, b"dnet call words v1")
        .iter()
        .map(|&b| WORDS[b as usize])
        .collect()
}

fn new_pair() -> (EphSecret, EphPublic) {
    XWing::gen_keypair()
}

/// What a secret encapsulated for a call is bound to: the call and the two
/// people, in the order of who called.
fn call_info(id: &[u8; 16], caller: &str, callee: &str) -> Result<Vec<u8>> {
    Ok([CALL_INFO, id, &key_bytes(caller)?, &key_bytes(callee)?].concat())
}

fn room_info(place: &Place, asker: &str, holder: &str) -> Result<Vec<u8>> {
    Ok([
        ROOM_INFO,
        place.0.as_bytes(),
        b"/",
        place.1.as_bytes(),
        &key_bytes(asker)?,
        &key_bytes(holder)?,
    ]
    .concat())
}

fn hpke_failed() -> CoreError {
    invalid("the call key could not be agreed")
}

/// Encapsulates a fresh secret to `their_eph` and takes a 32-byte key from
/// it. Returns the encapsulation, for them, and the key.
fn encapsulate(
    their_eph: &str,
    info: &[u8],
    label: &[u8],
) -> Result<(String, Zeroizing<[u8; 32]>)> {
    let public = EphPublic::from_bytes(&hexcode::decode(their_eph)?).map_err(|_| hpke_failed())?;
    let (enc, context) =
        hpke::setup_sender::<AesGcm256, HkdfSha256, XWing>(&OpModeS::Base, &public, info)
            .map_err(|_| hpke_failed())?;
    let mut key = Zeroizing::new([0u8; 32]);
    context
        .export(label, key.as_mut_slice())
        .map_err(|_| hpke_failed())?;
    Ok((hexcode::encode(&enc.to_bytes()), key))
}

/// Undoes [`encapsulate`] with the private half.
fn decapsulate(
    secret: &EphSecret,
    enc: &str,
    info: &[u8],
    label: &[u8],
) -> Result<Zeroizing<[u8; 32]>> {
    let enc = Encapped::from_bytes(&hexcode::decode(enc)?).map_err(|_| hpke_failed())?;
    let context =
        hpke::setup_receiver::<AesGcm256, HkdfSha256, XWing>(&OpModeR::Base, secret, &enc, info)
            .map_err(|_| hpke_failed())?;
    let mut key = Zeroizing::new([0u8; 32]);
    context
        .export(label, key.as_mut_slice())
        .map_err(|_| hpke_failed())?;
    Ok(key)
}

/// Seals one frame of media from `sender` (a signing key, bytes).
fn seal_media(
    key: &[u8; 32],
    id: &[u8; 16],
    kind: u8,
    sender: &[u8],
    seq: u32,
    data: &[u8],
) -> Result<Vec<u8>> {
    let mut frame = Vec::with_capacity(HEADER + NONCE_LEN + 4 + data.len() + TAG_LEN);
    frame.push(MEDIA_MARK);
    frame.push(kind);
    frame.extend_from_slice(id);
    let aad = [&frame[..HEADER], sender].concat();
    let mut plain = Zeroizing::new(Vec::with_capacity(4 + data.len()));
    plain.extend_from_slice(&seq.to_be_bytes());
    plain.extend_from_slice(data);
    // A fresh random number for every frame. Many people seal under one
    // room's key, so a counter could repeat across them; 96 random bits
    // will not, for as many frames as any call makes.
    let nonce = random_bytes::<NONCE_LEN>()?;
    let media = derive::<32>(key, b"dnet call media v1");
    let sealed = Aes256Gcm::new(&Key::<Aes256Gcm>::from(media))
        .encrypt(
            &Nonce::from(*nonce),
            Payload {
                msg: &plain,
                aad: &aad,
            },
        )
        .map_err(|_| invalid("the frame could not be sealed"))?;
    frame.extend_from_slice(nonce.as_slice());
    frame.extend_from_slice(&sealed);
    Ok(frame)
}

/// Opens one frame of media that came from `sender`. Returns its kind, its
/// number and what it holds.
fn open_media(
    key: &[u8; 32],
    frame: &[u8],
    sender: &[u8],
) -> Result<(u8, u32, Zeroizing<Vec<u8>>)> {
    let not_one = || invalid("that is not a frame of this call");
    if frame.len() < HEADER + NONCE_LEN + 4 + TAG_LEN || frame[0] != MEDIA_MARK {
        return Err(not_one());
    }
    let aad = [&frame[..HEADER], sender].concat();
    let nonce: [u8; NONCE_LEN] = frame[HEADER..HEADER + NONCE_LEN]
        .try_into()
        .expect("twelve bytes were taken");
    let media = derive::<32>(key, b"dnet call media v1");
    let plain = Aes256Gcm::new(&Key::<Aes256Gcm>::from(media))
        .decrypt(
            &Nonce::from(nonce),
            Payload {
                msg: &frame[HEADER + NONCE_LEN..],
                aad: &aad,
            },
        )
        .map(Zeroizing::new)
        .map_err(|_| not_one())?;
    let seq = u32::from_be_bytes(plain[..4].try_into().expect("four bytes were checked"));
    Ok((frame[1], seq, Zeroizing::new(plain[4..].to_vec())))
}

/// The call a media frame belongs to, without opening it.
pub(crate) fn frame_call(frame: &[u8]) -> Option<[u8; 16]> {
    (frame.len() >= HEADER && frame[0] == MEDIA_MARK).then(|| {
        frame[2..HEADER]
            .try_into()
            .expect("sixteen bytes were checked")
    })
}

/// Squeezes sound for a frame: how many samples, then the block.
fn pack_audio(pcm: &[u8]) -> Result<Vec<u8>> {
    let block = codec::encode(pcm);
    if block.is_empty() || !pcm.len().is_multiple_of(2) {
        return Err(invalid("that is not a block of sound"));
    }
    let samples = (pcm.len() / 2) as u16;
    Ok([&samples.to_be_bytes()[..], &block].concat())
}

fn unpack_audio(data: &[u8]) -> Option<Vec<u8>> {
    if data.len() < 2 {
        return None;
    }
    let samples = u16::from_be_bytes([data[0], data[1]]) as usize;
    codec::decode(&data[2..], samples)
}

impl Calls {
    /// The call between two people that is going on, or ringing, if any.
    fn busy(&self) -> bool {
        !self.direct.is_empty()
    }

    /// Starts a call to `with`. Returns the call's number and the offer to
    /// seal for them.
    pub fn start(&mut self, with: &str, video: bool) -> Result<(String, Wire)> {
        if self.busy() {
            return Err(invalid("the user is already in a call"));
        }
        if !self.joined.is_empty() {
            return Err(invalid("the user is in a voice room"));
        }
        let id = *random_bytes::<16>()?;
        let (secret, public) = new_pair();
        self.direct.insert(
            id,
            Direct {
                with: with.to_string(),
                mine: true,
                video,
                phase: Phase::Calling,
                eph: Some(Box::new(secret)),
                their_eph: None,
                key: None,
            },
        );
        let call = hexcode::encode(&id);
        Ok((
            call.clone(),
            Wire::Offer {
                call,
                eph: hexcode::encode(&public.to_bytes()),
                video,
            },
        ))
    }

    /// The user answers an incoming call. Returns who it is with, the
    /// answer to seal for them, and the call key words.
    pub fn answer(&mut self, me: &str, call: &str) -> Result<(String, Wire, Vec<&'static str>)> {
        let id = call_id(call)?;
        let direct = self
            .direct
            .get_mut(&id)
            .filter(|d| d.phase == Phase::Incoming)
            .ok_or_else(|| invalid("there is no such call waiting"))?;
        let their_eph = direct
            .their_eph
            .take()
            .ok_or_else(|| invalid("there is no such call waiting"))?;
        let info = call_info(&id, &direct.with, me)?;
        let (enc, key) = encapsulate(&their_eph, &info, b"call key")?;
        let shown = words(&key);
        direct.key = Some(key);
        direct.phase = Phase::Live;
        Ok((
            direct.with.clone(),
            Wire::Answer {
                call: call.to_string(),
                enc,
            },
            shown,
        ))
    }

    /// Ends a call, or turns one down. Returns who to tell and how, if
    /// there was such a call.
    pub fn end(&mut self, call: &str, reason: &str) -> Option<(String, Wire)> {
        let id = call_id(call).ok()?;
        let direct = self.direct.remove(&id)?;
        Some((
            direct.with,
            Wire::End {
                call: call.to_string(),
                reason: reason.to_string(),
            },
        ))
    }

    /// Tells the other person the user's microphone, camera or screen
    /// sharing changed.
    pub fn tell(
        &self,
        call: &str,
        muted: bool,
        camera: bool,
        screen: bool,
    ) -> Result<(String, Wire)> {
        let id = call_id(call)?;
        let direct = self
            .direct
            .get(&id)
            .ok_or_else(|| invalid("there is no such call"))?;
        Ok((
            direct.with.clone(),
            Wire::State {
                call: call.to_string(),
                muted,
                camera,
                screen,
            },
        ))
    }

    /// Takes in what a contact said about a call. `me` is the user's own
    /// signing key. Returns what to tell the app, if anything, and what to
    /// send back to `from`.
    pub fn receive(&mut self, me: &str, from: &str, wire: Wire) -> (Option<Value>, Vec<Wire>) {
        match wire {
            Wire::Offer { call, eph, video } => {
                let Ok(id) = call_id(&call) else {
                    return (None, vec![]);
                };
                if self.direct.contains_key(&id) || hexcode::decode(&eph).is_err() {
                    return (None, vec![]);
                }
                // Both called each other at once. The call with the lower
                // number goes ahead; the other side drops theirs on seeing
                // this one, and this side drops its own here.
                let crossing = self
                    .direct
                    .iter()
                    .find(|(_, d)| d.with == from && d.mine && d.phase != Phase::Live)
                    .map(|(mine, _)| *mine);
                let mut replaces = None;
                if let Some(mine) = crossing {
                    if mine < id {
                        return (None, vec![]);
                    }
                    self.direct.remove(&mine);
                    replaces = Some(hexcode::encode(&mine));
                }
                if self.busy() || !self.joined.is_empty() {
                    let event = json!({ "kind": "call_missed", "from": from, "video": video });
                    let busy = Wire::End {
                        call,
                        reason: "busy".into(),
                    };
                    return (Some(event), vec![busy]);
                }
                self.direct.insert(
                    id,
                    Direct {
                        with: from.to_string(),
                        mine: false,
                        video,
                        phase: Phase::Incoming,
                        eph: None,
                        their_eph: Some(eph),
                        key: None,
                    },
                );
                let mut event =
                    json!({ "kind": "call_offer", "call": call, "from": from, "video": video });
                if let Some(replaces) = replaces {
                    event["replaces"] = json!(replaces);
                }
                (Some(event), vec![Wire::Ring { call }])
            }
            Wire::Ring { call } => {
                let Some(direct) = self.call_with(&call, from) else {
                    return (None, vec![]);
                };
                if direct.mine && direct.phase == Phase::Calling {
                    direct.phase = Phase::Ringing;
                    let event = json!({ "kind": "call_ringing", "call": call, "from": from });
                    return (Some(event), vec![]);
                }
                (None, vec![])
            }
            Wire::Answer { call, enc } => {
                let Ok(id) = call_id(&call) else {
                    return (None, vec![]);
                };
                let Some(direct) = self.call_with(&call, from) else {
                    return (None, vec![]);
                };
                if !direct.mine || !matches!(direct.phase, Phase::Calling | Phase::Ringing) {
                    return (None, vec![]);
                }
                let Some(secret) = direct.eph.as_deref() else {
                    return (None, vec![]);
                };
                let key = call_info(&id, me, from)
                    .and_then(|info| decapsulate(secret, &enc, &info, b"call key"));
                let Ok(key) = key else {
                    // An answer that does not open is no answer. The call
                    // cannot go ahead safely, so it ends.
                    self.direct.remove(&id);
                    let event = json!({ "kind": "call_ended", "call": call, "from": from, "reason": "failed" });
                    let end = Wire::End {
                        call,
                        reason: "failed".into(),
                    };
                    return (Some(event), vec![end]);
                };
                let shown = words(&key);
                direct.eph = None;
                direct.key = Some(key);
                direct.phase = Phase::Live;
                let event =
                    json!({ "kind": "call_answered", "call": call, "from": from, "words": shown });
                (Some(event), vec![])
            }
            Wire::State {
                call,
                muted,
                camera,
                screen,
            } => {
                if self.call_with(&call, from).is_none() {
                    return (None, vec![]);
                }
                let event = json!({ "kind": "call_state", "call": call, "from": from, "muted": muted, "camera": camera, "screen": screen });
                (Some(event), vec![])
            }
            Wire::End { call, reason } => {
                if self.call_with(&call, from).is_none() {
                    return (None, vec![]);
                }
                if let Ok(id) = call_id(&call) {
                    self.direct.remove(&id);
                }
                let reason = match reason.as_str() {
                    "hangup" | "declined" | "busy" | "unanswered" | "no_wifi" | "failed" => reason,
                    _ => "hangup".to_string(),
                };
                let event =
                    json!({ "kind": "call_ended", "call": call, "from": from, "reason": reason });
                (Some(event), vec![])
            }
        }
    }

    /// The call `call`, if it is with `from`.
    fn call_with(&mut self, call: &str, from: &str) -> Option<&mut Direct> {
        let id = call_id(call).ok()?;
        self.direct.get_mut(&id).filter(|d| d.with == from)
    }

    /// Every call and voice room, for the app to show.
    pub fn list(&self) -> Value {
        let calls: Vec<Value> = self
            .direct
            .iter()
            .map(|(id, d)| {
                let mut call = json!({
                    "call": hexcode::encode(id),
                    "with": d.with,
                    "mine": d.mine,
                    "video": d.video,
                    "phase": d.phase.name(),
                });
                if let Some(key) = &d.key {
                    call["words"] = json!(words(key));
                }
                call
            })
            .collect();
        json!({ "calls": calls, "rooms": self.rooms() })
    }

    /// Seals one frame of the user's sound (16-bit samples, little-endian,
    /// 16,000 a second), picture (a JPEG) or piece of their shared screen
    /// for a call or a voice room.
    /// Returns the frame, who to send it to, and for sound, how loud it
    /// was.
    pub fn media_out(
        &mut self,
        me: &str,
        call: &str,
        kind: &str,
        data: &[u8],
    ) -> Result<(Vec<u8>, Vec<String>, f64)> {
        let id = call_id(call)?;
        let kind = match kind {
            "audio" => AUDIO,
            "video" => VIDEO,
            "screen" => SCREEN,
            _ => return Err(invalid("a frame is sound, a picture or a screen")),
        };
        if data.len() > MAX_MEDIA {
            return Err(invalid("that frame is too big"));
        }
        let level = if kind == AUDIO {
            codec::level(data)
        } else {
            0.0
        };
        let packed = if kind == AUDIO {
            pack_audio(data)?
        } else {
            data.to_vec()
        };
        let (key, to) = if let Some(direct) = self.direct.get(&id) {
            let key = direct
                .key
                .as_ref()
                .filter(|_| direct.phase == Phase::Live)
                .ok_or_else(|| invalid("the call has not been answered"))?;
            (**key, vec![direct.with.clone()])
        } else {
            let (place, joined) = self
                .joined
                .iter()
                .find(|(_, j)| j.room.as_ref().is_some_and(|(room, _)| *room == id))
                .ok_or_else(|| invalid("there is no such call"))?;
            if kind == AUDIO && joined.owner_muted.contains(me) {
                return Err(invalid("whoever runs the space has muted the user here"));
            }
            let (_, key) = joined.room.as_ref().expect("it was found by its room");
            let now = now();
            let to = self
                .present
                .get(place)
                .into_iter()
                .flatten()
                .filter(|(who, p)| {
                    who.as_str() != me
                        && p.room == id
                        && now.saturating_sub(p.at) < PRESENT_FOR
                        // Someone with the sound off still sees a screen.
                        && (kind != AUDIO || !p.deaf)
                        && !joined.owner_deaf.contains(*who)
                })
                .map(|(who, _)| who.clone())
                .collect();
            (**key, to)
        };
        self.seq = self.seq.wrapping_add(1);
        let frame = seal_media(&key, &id, kind, &key_bytes(me)?, self.seq, &packed)?;
        Ok((frame, to, level))
    }

    /// Opens a frame of media that came from `from`, the device the link it
    /// arrived on has proved to be. Sound comes back as 16-bit samples.
    pub fn media_in(&self, from: &str, frame: &[u8]) -> Result<Value> {
        let id = frame_call(frame).ok_or_else(|| invalid("that is not a frame"))?;
        let sender = key_bytes(from)?;
        let key = if let Some(direct) = self.direct.get(&id) {
            if direct.with != from || direct.phase != Phase::Live {
                return Err(invalid("that is not a frame of this call"));
            }
            direct.key.as_ref().map(|k| **k)
        } else {
            let (place, joined) = self
                .joined
                .iter()
                .find(|(_, j)| j.room.as_ref().is_some_and(|(room, _)| *room == id))
                .ok_or_else(|| invalid("there is no such call"))?;
            let inside = self
                .present
                .get(place)
                .and_then(|p| p.get(from))
                .is_some_and(|p| p.room == id);
            if !inside {
                return Err(invalid("they are not in this room"));
            }
            joined.room.as_ref().map(|(_, key)| **key)
        }
        .ok_or_else(|| invalid("there is no key for this call"))?;
        let (kind, seq, data) = open_media(&key, frame, &sender)?;
        let call = hexcode::encode(&id);
        if kind == AUDIO {
            // In a room, whoever runs the space may have muted the sender,
            // or deafened the user. Either way nothing is played.
            if let Some((_, joined)) = self
                .joined
                .iter()
                .find(|(_, j)| j.room.as_ref().is_some_and(|(room, _)| *room == id))
            {
                if joined.owner_muted.contains(from) {
                    return Err(invalid("whoever runs the space has muted them"));
                }
            }
            let pcm = unpack_audio(&data).ok_or_else(|| invalid("that is not a block of sound"))?;
            return Ok(json!({
                "call": call,
                "from": from,
                "kind": "audio",
                "seq": seq,
                "level": codec::level(&pcm),
                "data": hexcode::encode(&pcm),
            }));
        }
        if kind == VIDEO || kind == SCREEN {
            return Ok(json!({
                "call": call,
                "from": from,
                "kind": if kind == VIDEO { "video" } else { "screen" },
                "seq": seq,
                "data": hexcode::encode(&data),
            }));
        }
        Err(invalid("that is not a frame of a kind this app knows"))
    }

    // Voice rooms

    fn fresh_inside(&self, place: &Place, me: &str) -> Vec<String> {
        let now = now();
        self.present
            .get(place)
            .into_iter()
            .flatten()
            .filter(|(who, p)| who.as_str() != me && now.saturating_sub(p.at) < PRESENT_FOR)
            .map(|(who, _)| who.clone())
            .collect()
    }

    /// The user goes into a voice room. If others are inside, returns an
    /// ask for them; if not (or with `alone`, when nobody answered the
    /// ask), opens the room and returns word of it for everyone.
    pub fn room_join(
        &mut self,
        me: &str,
        place: Place,
        alone: bool,
        muted: bool,
        owner: OwnerSays,
    ) -> Result<RoomStep> {
        if self.busy() {
            return Err(invalid("the user is in a call"));
        }
        if owner.deaf.contains(me) {
            return Err(invalid("whoever runs the space has deafened the user here"));
        }
        // One room at a time.
        let others: Vec<Place> = self
            .joined
            .keys()
            .filter(|p| **p != place)
            .cloned()
            .collect();
        let mut steps = RoomStep::default();
        for other in others {
            steps.left.push(other.clone());
            self.room_leave(&other);
        }
        let inside = self.fresh_inside(&place, me);
        let fresh = !self.joined.contains_key(&place);
        let joined = self.joined.entry(place.clone()).or_default();
        if fresh {
            joined.muted = muted;
        }
        joined.owner_muted = owner.muted;
        joined.owner_deaf = owner.deaf;
        if joined.room.is_some() {
            steps.here = true;
            return Ok(steps);
        }
        if !inside.is_empty() && !alone {
            let (secret, public) = new_pair();
            joined.asking = Some(Box::new(secret));
            steps.ask = Some((
                inside,
                RoomWire::Ask {
                    eph: hexcode::encode(&public.to_bytes()),
                },
            ));
            return Ok(steps);
        }
        let room = *random_bytes::<16>()?;
        let key = Zeroizing::new(*random_bytes::<32>()?);
        joined.room = Some((room, key));
        joined.asking = None;
        steps.here = true;
        Ok(steps)
    }

    /// What the user says while in a room, every few seconds and whenever
    /// it changes. None while still asking to be let in.
    pub fn room_here(
        &mut self,
        place: &Place,
        muted: bool,
        deaf: bool,
        camera: bool,
        screen: bool,
        owner: Option<OwnerSays>,
    ) -> Option<RoomWire> {
        let joined = self.joined.get_mut(place)?;
        joined.muted = muted;
        joined.deaf = deaf;
        joined.camera = camera;
        joined.screen = screen;
        if let Some(owner) = owner {
            joined.owner_muted = owner.muted;
            joined.owner_deaf = owner.deaf;
        }
        // Old word of people long gone is let go.
        let now = now();
        if let Some(inside) = self.present.get_mut(place) {
            inside.retain(|_, p| now.saturating_sub(p.at) < PRESENT_FOR * 4);
        }
        let (room, _) = joined.room.as_ref()?;
        Some(RoomWire::Here {
            room: hexcode::encode(room),
            muted,
            deaf,
            camera,
            screen,
        })
    }

    /// What the user says about a room they are in, as last set. None while
    /// still asking to be let in.
    pub fn here_again(&mut self, place: &Place) -> Option<RoomWire> {
        let joined = self.joined.get(place)?;
        let (muted, deaf, camera, screen) =
            (joined.muted, joined.deaf, joined.camera, joined.screen);
        self.room_here(place, muted, deaf, camera, screen, None)
    }

    /// What whoever runs the space now says about who is muted and
    /// deafened, for a room the user is in.
    pub fn room_owner(&mut self, place: &Place, owner: OwnerSays) {
        if let Some(joined) = self.joined.get_mut(place) {
            joined.owner_muted = owner.muted;
            joined.owner_deaf = owner.deaf;
        }
    }

    /// The user leaves a room. True if they were in it.
    pub fn room_leave(&mut self, place: &Place) -> bool {
        self.joined.remove(place).is_some()
    }

    /// Whether the user is in this room or asking to be.
    pub fn in_room(&self, place: &Place) -> bool {
        self.joined.contains_key(place)
    }

    /// Takes in what a fellow member said about a voice room. The space
    /// has checked they are a member and the room is one. Returns what to
    /// tell the app and what to send back to `from`.
    pub fn room_receive(
        &mut self,
        me: &str,
        from: &str,
        place: Place,
        wire: RoomWire,
    ) -> (Option<Value>, Vec<RoomWire>) {
        let changed = || {
            Some(json!({
                "kind": "room",
                "space": place.0,
                "channel": place.1,
            }))
        };
        match wire {
            RoomWire::Here {
                room,
                muted,
                deaf,
                camera,
                screen,
            } => {
                let Ok(room) = call_id(&room) else {
                    return (None, vec![]);
                };
                let heard = Presence {
                    room,
                    at: now(),
                    muted,
                    deaf,
                    camera,
                    screen,
                };
                let inside = self.present.entry(place.clone()).or_default();
                let before = inside.insert(from.to_string(), heard.clone());
                let news = before.is_none_or(|b| {
                    b.room != heard.room
                        || b.muted != muted
                        || b.deaf != deaf
                        || b.camera != camera
                        || b.screen != screen
                        || heard.at.saturating_sub(b.at) >= PRESENT_FOR
                });
                // Two rooms by one name: the lower number wins, so the
                // user asks to be let into theirs.
                let mut replies = vec![];
                if let Some(joined) = self.joined.get_mut(&place) {
                    let ours = joined.room.as_ref().map(|(r, _)| *r);
                    if ours.is_some_and(|ours| room < ours) && joined.asking.is_none() {
                        let (secret, public) = new_pair();
                        joined.asking = Some(Box::new(secret));
                        replies.push(RoomWire::Ask {
                            eph: hexcode::encode(&public.to_bytes()),
                        });
                    }
                }
                (if news { changed() } else { None }, replies)
            }
            RoomWire::Ask { eph } => {
                let Some(joined) = self.joined.get(&place) else {
                    return (None, vec![]);
                };
                // Whoever runs the space deafened them: they are not given
                // the key to hear with.
                let Some((room, key)) = joined.room.as_ref() else {
                    return (None, vec![]);
                };
                if joined.owner_deaf.contains(from) {
                    return (None, vec![]);
                }
                let handed = room_info(&place, from, me).and_then(|info| {
                    let (enc, wrap) = encapsulate(&eph, &info, b"room key")?;
                    let sealed = seal::seal(&wrap, room, key.as_slice())?;
                    Ok(RoomWire::Key {
                        room: hexcode::encode(room),
                        enc,
                        sealed: hexcode::encode(&sealed),
                    })
                });
                match handed {
                    Ok(wire) => (None, vec![wire]),
                    Err(_) => (None, vec![]),
                }
            }
            RoomWire::Key { room, enc, sealed } => {
                let Some(joined) = self.joined.get_mut(&place) else {
                    return (None, vec![]);
                };
                let Some(secret) = joined.asking.as_deref() else {
                    return (None, vec![]);
                };
                let Ok(room) = call_id(&room) else {
                    return (None, vec![]);
                };
                // Only a move to a lower room, if the user is already in
                // one.
                if joined.room.as_ref().is_some_and(|(ours, _)| room >= *ours) {
                    joined.asking = None;
                    return (None, vec![]);
                }
                let opened = room_info(&place, me, from)
                    .and_then(|info| decapsulate(secret, &enc, &info, b"room key"))
                    .and_then(|wrap| seal::open(&wrap, &room, &hexcode::decode(&sealed)?));
                let Ok(opened) = opened else {
                    return (None, vec![]);
                };
                let Ok(key) = <[u8; 32]>::try_from(opened.as_slice()) else {
                    return (None, vec![]);
                };
                let key = Zeroizing::new(key);
                let shown = words(&key);
                joined.room = Some((room, key));
                joined.asking = None;
                let event = json!({
                    "kind": "room_in",
                    "space": place.0,
                    "channel": place.1,
                    "words": shown,
                });
                (Some(event), vec![])
            }
            RoomWire::Left => {
                let gone = self
                    .present
                    .get_mut(&place)
                    .and_then(|inside| inside.remove(from))
                    .is_some();
                (if gone { changed() } else { None }, vec![])
            }
        }
    }

    /// Everyone in each voice room, as heard, and the rooms the user is in.
    pub fn rooms(&self) -> Vec<Value> {
        let now = now();
        let mut places: HashSet<&Place> = self.present.keys().collect();
        places.extend(self.joined.keys());
        let mut rooms: Vec<Value> = places
            .into_iter()
            .map(|place| {
                let joined = self.joined.get(place);
                let mut people: Vec<Value> = self
                    .present
                    .get(place)
                    .into_iter()
                    .flatten()
                    .filter(|(_, p)| now.saturating_sub(p.at) < PRESENT_FOR)
                    .map(|(who, p)| {
                        let owner_muted = joined.is_some_and(|j| j.owner_muted.contains(who));
                        let owner_deaf = joined.is_some_and(|j| j.owner_deaf.contains(who));
                        json!({
                            "key": who,
                            "muted": p.muted || owner_muted,
                            "deaf": p.deaf || owner_deaf,
                            "camera": p.camera,
                            "screen": p.screen,
                            "owner_muted": owner_muted,
                            "owner_deaf": owner_deaf,
                            "room": hexcode::encode(&p.room),
                        })
                    })
                    .collect();
                people.sort_by(|a, b| a["key"].as_str().cmp(&b["key"].as_str()));
                let mut room = json!({
                    "space": place.0,
                    "channel": place.1,
                    "people": people,
                    "joined": joined.is_some(),
                });
                if let Some(joined) = joined {
                    room["asking"] = json!(joined.asking.is_some() && joined.room.is_none());
                    room["muted"] = json!(joined.muted);
                    room["deaf"] = json!(joined.deaf);
                    room["screen"] = json!(joined.screen);
                    room["owner_muted"] = json!(joined.owner_muted.iter().collect::<Vec<_>>());
                    room["owner_deaf"] = json!(joined.owner_deaf.iter().collect::<Vec<_>>());
                    if let Some((id, key)) = &joined.room {
                        room["call"] = json!(hexcode::encode(id));
                        room["words"] = json!(words(key));
                    }
                }
                room
            })
            .filter(|room| {
                room["joined"] == true || !room["people"].as_array().is_some_and(Vec::is_empty)
            })
            .collect();
        rooms.sort_by(|a, b| {
            (a["space"].as_str(), a["channel"].as_str())
                .cmp(&(b["space"].as_str(), b["channel"].as_str()))
        });
        rooms
    }

    /// The voice rooms the user is in, or asking to be.
    pub fn joined_places(&self) -> Vec<Place> {
        self.joined.keys().cloned().collect()
    }
}

/// What joining a room leads to.
#[derive(Default)]
pub(crate) struct RoomStep {
    /// Ask these members, who are inside, to let the user in.
    pub ask: Option<(Vec<String>, RoomWire)>,
    /// The user is in: tell everyone in range.
    pub here: bool,
    /// Rooms the user left to come here: tell everyone in range.
    pub left: Vec<Place>,
}

#[cfg(test)]
mod tests {
    use super::*;

    const ASHA: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const MIRA: &str = "0202020202020202020202020202020202020202020202020202020202020202";
    const NOOR: &str = "0303030303030303030303030303030303030303030303030303030303030303";

    fn place() -> Place {
        ("space".to_string(), "campfire".to_string())
    }

    fn pcm() -> Vec<u8> {
        (0..320)
            .flat_map(|i| (((i as f64 / 8.0).sin() * 8000.0) as i16).to_le_bytes())
            .collect()
    }

    /// Asha calls Mira and Mira answers. Returns both sides and the call.
    fn live() -> (Calls, Calls, String) {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        let (call, offer) = asha.start(MIRA, false).unwrap();
        let (event, replies) = mira.receive(MIRA, ASHA, offer);
        assert_eq!(event.unwrap()["kind"], "call_offer");
        let [ring] = <[Wire; 1]>::try_from(replies).unwrap();
        let (event, _) = asha.receive(ASHA, MIRA, ring);
        assert_eq!(event.unwrap()["kind"], "call_ringing");
        let (with, answer, mira_words) = mira.answer(MIRA, &call).unwrap();
        assert_eq!(with, ASHA);
        let (event, _) = asha.receive(ASHA, MIRA, answer);
        let event = event.unwrap();
        assert_eq!(event["kind"], "call_answered");
        assert_eq!(event["words"], json!(mira_words), "both see the same words");
        (asha, mira, call)
    }

    #[test]
    fn both_ends_agree_the_same_key_and_words() {
        let (asha, mira, call) = live();
        let id = call_id(&call).unwrap();
        assert_eq!(
            *asha.direct[&id].key.as_ref().unwrap(),
            *mira.direct[&id].key.as_ref().unwrap()
        );
        assert_eq!(
            asha.list()["calls"][0]["words"].as_array().unwrap().len(),
            4
        );
    }

    #[test]
    fn every_call_has_a_new_key() {
        let (asha, _, first) = live();
        let (asha2, _, second) = live();
        let one = asha.direct[&call_id(&first).unwrap()]
            .key
            .as_ref()
            .unwrap()
            .clone();
        let two = asha2.direct[&call_id(&second).unwrap()]
            .key
            .as_ref()
            .unwrap()
            .clone();
        assert_ne!(*one, *two);
    }

    #[test]
    fn sound_goes_through_and_comes_out() {
        let (mut asha, mira, call) = live();
        let (frame, to, level) = asha.media_out(ASHA, &call, "audio", &pcm()).unwrap();
        assert_eq!(to, vec![MIRA.to_string()]);
        assert!(level > 0.1);
        assert_eq!(frame[0], MEDIA_MARK);
        // About a quarter of the sound, plus the sealing.
        assert!(frame.len() < 640 / 2, "{}", frame.len());
        let heard = mira.media_in(ASHA, &frame).unwrap();
        assert_eq!(heard["kind"], "audio");
        let back = hexcode::decode(heard["data"].as_str().unwrap()).unwrap();
        assert_eq!(back.len(), 640);
    }

    #[test]
    fn a_picture_goes_through_as_it_is() {
        let (mut asha, mira, call) = live();
        let jpeg = [0xff, 0xd8, 0xff, 1, 2, 3];
        let (frame, _, _) = asha.media_out(ASHA, &call, "video", &jpeg).unwrap();
        let seen = mira.media_in(ASHA, &frame).unwrap();
        assert_eq!(seen["kind"], "video");
        assert_eq!(seen["data"], hexcode::encode(&jpeg));
        assert!(asha
            .media_out(ASHA, &call, "video", &vec![0; MAX_MEDIA + 1])
            .is_err());
    }

    #[test]
    fn a_shared_screen_goes_through_as_its_own_kind() {
        let (mut asha, mira, call) = live();
        // A voice call: no camera needed to share a screen.
        let piece = [1, 0, 7, 0xff, 0xd8, 0xff, 9, 9];
        let (frame, to, _) = asha.media_out(ASHA, &call, "screen", &piece).unwrap();
        assert_eq!(to, vec![MIRA.to_string()]);
        let seen = mira.media_in(ASHA, &frame).unwrap();
        assert_eq!(seen["kind"], "screen");
        assert_eq!(seen["data"], hexcode::encode(&piece));
        assert!(asha
            .media_out(ASHA, &call, "screen", &vec![0; MAX_MEDIA + 1])
            .is_err());
        assert!(asha.media_out(ASHA, &call, "smell", &piece).is_err());
    }

    #[test]
    fn sharing_a_screen_is_told_to_the_other_person() {
        let (asha, mut mira, call) = live();
        let (to, wire) = asha.tell(&call, false, false, true).unwrap();
        assert_eq!(to, MIRA);
        let (event, _) = mira.receive(MIRA, ASHA, wire);
        let event = event.unwrap();
        assert_eq!(event["kind"], "call_state");
        assert_eq!(event["screen"], true);
        assert_eq!(event["camera"], false);
    }

    #[test]
    fn word_from_an_older_app_says_nobody_is_sharing() {
        let state: Wire = serde_json::from_value(
            json!({"c": "state", "call": "00", "muted": true, "camera": false}),
        )
        .unwrap();
        assert!(matches!(state, Wire::State { screen: false, .. }));
        let here: RoomWire = serde_json::from_value(json!({"r": "here", "room": "00"})).unwrap();
        assert!(matches!(here, RoomWire::Here { screen: false, .. }));
    }

    #[test]
    fn a_frame_changed_on_the_way_is_dropped() {
        let (mut asha, mira, call) = live();
        let (mut frame, _, _) = asha.media_out(ASHA, &call, "audio", &pcm()).unwrap();
        let last = frame.len() - 1;
        frame[last] ^= 1;
        assert!(mira.media_in(ASHA, &frame).is_err());
    }

    #[test]
    fn a_frame_is_believed_only_from_the_device_it_says_it_is() {
        let (mut asha, mira, call) = live();
        let (frame, _, _) = asha.media_out(ASHA, &call, "audio", &pcm()).unwrap();
        // The same frame, arriving on Noor's link.
        assert!(mira.media_in(NOOR, &frame).is_err());
    }

    #[test]
    fn nothing_flows_before_the_answer() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        let (call, offer) = asha.start(MIRA, false).unwrap();
        mira.receive(MIRA, ASHA, offer);
        assert!(asha.media_out(ASHA, &call, "audio", &pcm()).is_err());
        assert!(mira.media_out(MIRA, &call, "audio", &pcm()).is_err());
    }

    #[test]
    fn someone_already_in_a_call_is_busy() {
        let (_, mut mira, _) = live();
        let mut noor = Calls::default();
        let (_, offer) = noor.start(MIRA, false).unwrap();
        let (event, replies) = mira.receive(MIRA, NOOR, offer);
        assert_eq!(event.unwrap()["kind"], "call_missed");
        assert!(matches!(&replies[..], [Wire::End { reason, .. }] if reason == "busy"));
        let (event, _) = noor.receive(NOOR, MIRA, replies.into_iter().next().unwrap());
        assert_eq!(event.unwrap()["reason"], "busy");
        assert!(noor.list()["calls"].as_array().unwrap().is_empty());
    }

    #[test]
    fn two_calling_each_other_at_once_end_up_in_one_call() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        let (a, offer_a) = asha.start(MIRA, false).unwrap();
        let (m, offer_m) = mira.start(ASHA, false).unwrap();
        let (to_mira, _) = mira.receive(MIRA, ASHA, offer_a);
        let (to_asha, _) = asha.receive(ASHA, MIRA, offer_m);
        let winner = a.clone().min(m.clone());
        // Exactly one side is now being called, by the lower call.
        let offered: Vec<Value> = [to_mira, to_asha].into_iter().flatten().collect();
        assert_eq!(offered.len(), 1);
        assert_eq!(offered[0]["call"], winner);
        assert_eq!(asha.direct.len(), 1);
        assert_eq!(mira.direct.len(), 1);
    }

    #[test]
    fn hanging_up_ends_it_on_both_sides() {
        let (mut asha, mut mira, call) = live();
        let (to, end) = asha.end(&call, "hangup").unwrap();
        assert_eq!(to, MIRA);
        let (event, _) = mira.receive(MIRA, ASHA, end);
        assert_eq!(event.unwrap()["kind"], "call_ended");
        assert!(mira.direct.is_empty() && asha.direct.is_empty());
    }

    #[test]
    fn only_the_other_person_can_end_or_answer_a_call() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        let (call, offer) = asha.start(MIRA, false).unwrap();
        mira.receive(MIRA, ASHA, offer);
        let end = Wire::End {
            call: call.clone(),
            reason: "hangup".into(),
        };
        assert!(asha.receive(ASHA, NOOR, end).0.is_none());
        assert_eq!(asha.direct.len(), 1);
    }

    #[test]
    fn an_answer_that_does_not_open_ends_the_call() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        let (call, offer) = asha.start(MIRA, false).unwrap();
        mira.receive(MIRA, ASHA, offer);
        // An answer is signed by whoever sent it, so only Mira could send
        // one at all; this one is simply broken.
        let fake = Wire::Answer {
            call,
            enc: hexcode::encode(&[7u8; 40]),
        };
        let (event, _) = asha.receive(ASHA, MIRA, fake);
        assert_eq!(event.unwrap()["reason"], "failed");
        assert!(asha.direct.is_empty());
    }

    // Voice rooms

    fn here_of(calls: &mut Calls) -> RoomWire {
        calls
            .room_here(&place(), false, false, false, false, None)
            .unwrap()
    }

    #[test]
    fn the_first_in_opens_the_room_and_the_next_is_let_in() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        let step = asha
            .room_join(ASHA, place(), false, false, OwnerSays::default())
            .unwrap();
        assert!(step.here && step.ask.is_none());
        // Mira hears Asha is inside, then comes in.
        mira.room_receive(MIRA, ASHA, place(), here_of(&mut asha));
        let step = mira
            .room_join(MIRA, place(), false, false, OwnerSays::default())
            .unwrap();
        let (to, ask) = step.ask.unwrap();
        assert_eq!(to, vec![ASHA.to_string()]);
        let (_, replies) = asha.room_receive(ASHA, MIRA, place(), ask);
        let [key] = <[RoomWire; 1]>::try_from(replies).unwrap();
        let (event, _) = mira.room_receive(MIRA, ASHA, place(), key);
        let event = event.unwrap();
        assert_eq!(event["kind"], "room_in");
        assert_eq!(json!(asha.rooms()[0]["words"]), event["words"]);

        // Now each hears the other.
        asha.room_receive(ASHA, MIRA, place(), here_of(&mut mira));
        let room = asha.rooms()[0]["call"].as_str().unwrap().to_string();
        let (frame, to, _) = mira.media_out(MIRA, &room, "audio", &pcm()).unwrap();
        assert_eq!(to, vec![ASHA.to_string()]);
        assert_eq!(asha.media_in(MIRA, &frame).unwrap()["kind"], "audio");
    }

    #[test]
    fn two_who_open_a_room_at_once_move_to_the_lower_one() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        asha.room_join(ASHA, place(), false, false, OwnerSays::default())
            .unwrap();
        mira.room_join(MIRA, place(), false, false, OwnerSays::default())
            .unwrap();
        let (a, m) = (here_of(&mut asha), here_of(&mut mira));
        let (_, from_asha) = mira.room_receive(MIRA, ASHA, place(), a);
        let (_, from_mira) = asha.room_receive(ASHA, MIRA, place(), m);
        // Exactly one of them asks the other.
        let (asker, holder, holder_key, mut asks) = if from_asha.is_empty() {
            (&mut asha, &mut mira, MIRA, from_mira)
        } else {
            (&mut mira, &mut asha, ASHA, from_asha)
        };
        assert_eq!(asks.len(), 1);
        let asker_key = if holder_key == MIRA { ASHA } else { MIRA };
        let (_, keys) = holder.room_receive(holder_key, asker_key, place(), asks.remove(0));
        asker.room_receive(
            asker_key,
            holder_key,
            place(),
            keys.into_iter().next().unwrap(),
        );
        assert_eq!(asker.rooms()[0]["words"], holder.rooms()[0]["words"]);
        assert_eq!(asker.rooms()[0]["call"], holder.rooms()[0]["call"]);
    }

    #[test]
    fn someone_the_owner_deafened_is_not_given_the_key() {
        let mut asha = Calls::default();
        let owner = OwnerSays {
            muted: HashSet::new(),
            deaf: HashSet::from([MIRA.to_string()]),
        };
        asha.room_join(ASHA, place(), false, false, owner).unwrap();
        let (_, public) = new_pair();
        let ask = RoomWire::Ask {
            eph: hexcode::encode(&public.to_bytes()),
        };
        let (_, replies) = asha.room_receive(ASHA, MIRA, place(), ask);
        assert!(replies.is_empty());
    }

    #[test]
    fn someone_the_owner_muted_cannot_send_and_is_not_heard() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        let owner = OwnerSays {
            muted: HashSet::from([MIRA.to_string()]),
            deaf: HashSet::new(),
        };
        asha.room_join(ASHA, place(), false, false, owner.clone())
            .unwrap();
        mira.room_receive(MIRA, ASHA, place(), here_of(&mut asha));
        let (_, ask) = mira
            .room_join(MIRA, place(), false, false, owner)
            .unwrap()
            .ask
            .unwrap();
        let (_, keys) = asha.room_receive(ASHA, MIRA, place(), ask);
        mira.room_receive(MIRA, ASHA, place(), keys.into_iter().next().unwrap());
        asha.room_receive(ASHA, MIRA, place(), here_of(&mut mira));
        let room = asha.rooms()[0]["call"].as_str().unwrap().to_string();
        assert!(mira.media_out(MIRA, &room, "audio", &pcm()).is_err());
        // Even sealed some other way, it is not played.
        let key = **mira.joined[&place()].room.as_ref().map(|(_, k)| k).unwrap();
        let frame = seal_media(
            &key,
            &call_id(&room).unwrap(),
            AUDIO,
            &key_bytes(MIRA).unwrap(),
            1,
            &pack_audio(&pcm()).unwrap(),
        )
        .unwrap();
        assert!(asha.media_in(MIRA, &frame).is_err());
    }

    #[test]
    fn a_frame_from_someone_not_in_the_room_is_dropped() {
        let mut asha = Calls::default();
        asha.room_join(ASHA, place(), false, false, OwnerSays::default())
            .unwrap();
        let room = asha.rooms()[0]["call"].as_str().unwrap().to_string();
        let key = **asha.joined[&place()].room.as_ref().map(|(_, k)| k).unwrap();
        let frame = seal_media(
            &key,
            &call_id(&room).unwrap(),
            AUDIO,
            &key_bytes(NOOR).unwrap(),
            1,
            &pack_audio(&pcm()).unwrap(),
        )
        .unwrap();
        assert!(asha.media_in(NOOR, &frame).is_err());
    }

    #[test]
    fn everyone_in_a_room_sees_who_is_sharing() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        asha.room_join(ASHA, place(), false, false, OwnerSays::default())
            .unwrap();
        mira.room_receive(MIRA, ASHA, place(), here_of(&mut asha));
        assert_eq!(mira.rooms()[0]["people"][0]["screen"], false);
        let sharing = asha
            .room_here(&place(), true, false, false, true, None)
            .unwrap();
        let (event, _) = mira.room_receive(MIRA, ASHA, place(), sharing);
        assert_eq!(event.unwrap()["kind"], "room", "a change is news");
        assert_eq!(mira.rooms()[0]["people"][0]["screen"], true);
        assert_eq!(asha.rooms()[0]["screen"], true);
        // Said again every few seconds, it stays as it was set.
        let again = asha.here_again(&place()).unwrap();
        assert!(matches!(again, RoomWire::Here { screen: true, .. }));
    }

    #[test]
    fn a_screen_shared_in_a_room_reaches_those_inside() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        asha.room_join(ASHA, place(), false, false, OwnerSays::default())
            .unwrap();
        mira.room_receive(MIRA, ASHA, place(), here_of(&mut asha));
        let (_, ask) = mira
            .room_join(MIRA, place(), false, false, OwnerSays::default())
            .unwrap()
            .ask
            .unwrap();
        let (_, keys) = asha.room_receive(ASHA, MIRA, place(), ask);
        mira.room_receive(MIRA, ASHA, place(), keys.into_iter().next().unwrap());
        asha.room_receive(ASHA, MIRA, place(), here_of(&mut mira));
        let room = asha.rooms()[0]["call"].as_str().unwrap().to_string();
        let piece = [1, 2, 3];
        let (frame, to, _) = asha.media_out(ASHA, &room, "screen", &piece).unwrap();
        assert_eq!(to, vec![MIRA.to_string()]);
        assert_eq!(mira.media_in(ASHA, &frame).unwrap()["kind"], "screen");
    }

    #[test]
    fn someone_with_the_sound_off_still_sees_a_shared_screen() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        asha.room_join(ASHA, place(), false, false, OwnerSays::default())
            .unwrap();
        mira.room_receive(MIRA, ASHA, place(), here_of(&mut asha));
        let (_, ask) = mira
            .room_join(MIRA, place(), false, false, OwnerSays::default())
            .unwrap()
            .ask
            .unwrap();
        let (_, keys) = asha.room_receive(ASHA, MIRA, place(), ask);
        mira.room_receive(MIRA, ASHA, place(), keys.into_iter().next().unwrap());
        let deaf = mira
            .room_here(&place(), true, true, false, false, None)
            .unwrap();
        asha.room_receive(ASHA, MIRA, place(), deaf);
        let room = asha.rooms()[0]["call"].as_str().unwrap().to_string();
        let (_, to, _) = asha.media_out(ASHA, &room, "audio", &pcm()).unwrap();
        assert!(to.is_empty(), "no sound to someone who turned it off");
        let (_, to, _) = asha.media_out(ASHA, &room, "screen", &[1, 2]).unwrap();
        assert_eq!(to, vec![MIRA.to_string()]);
    }

    #[test]
    fn leaving_is_heard() {
        let (mut asha, mut mira) = (Calls::default(), Calls::default());
        asha.room_join(ASHA, place(), false, false, OwnerSays::default())
            .unwrap();
        mira.room_receive(MIRA, ASHA, place(), here_of(&mut asha));
        assert_eq!(mira.rooms()[0]["people"].as_array().unwrap().len(), 1);
        let (event, _) = mira.room_receive(MIRA, ASHA, place(), RoomWire::Left);
        assert_eq!(event.unwrap()["kind"], "room");
        assert!(mira.rooms().is_empty());
    }

    #[test]
    fn someone_in_a_room_cannot_also_take_a_call() {
        let mut asha = Calls::default();
        asha.room_join(ASHA, place(), false, false, OwnerSays::default())
            .unwrap();
        assert!(asha.start(MIRA, false).is_err());
        let mut mira = Calls::default();
        let (_, offer) = mira.start(ASHA, false).unwrap();
        let (event, _) = asha.receive(ASHA, MIRA, offer);
        assert_eq!(event.unwrap()["kind"], "call_missed");
    }
}
