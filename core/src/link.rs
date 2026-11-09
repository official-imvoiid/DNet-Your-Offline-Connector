//! One radio connection between two devices.
//!
//! A radio such as Bluetooth carries small frames and knows nothing about
//! who is at the other end. This module does the two things every link
//! needs, so the radio code on each platform can stay simple:
//!
//! 1. **Splitting.** A message is cut into frames that fit the radio and
//!    put back together on arrival. There are two lanes, each putting
//!    together one message at a time: one for chat and everything short,
//!    and one for pieces of files. A frame of chat can go between any two
//!    frames of a piece, so a chat never waits for a file to finish.
//! 2. **Proving who is there.** Each side shows its identity and then signs
//!    a fresh number from the other side. An identity is public, so anyone
//!    could show someone else's. Only its owner can sign with it.
//!
//! Envelopes are already sealed end to end, so the link adds no secrecy of
//! its own. The proof exists so that messages are handed to the device that
//! can open them, and not to one that merely claims to be that person.
//!
//! What this does not hide: a device that connects learns the other's
//! identity. Someone nearby running the app can therefore recognise a
//! device they have met before.

use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::identity::{verify_signature, IdentitySecret, PublicIdentity, SIGNATURE_LEN};
use crate::seal::random_bytes;

/// The smallest frame a Bluetooth link can carry before the two sides
/// agree on more.
pub(crate) const MIN_FRAME: usize = 20;
/// The largest message a link will put together. Larger claims are refused
/// before any memory is set aside.
const MAX_MESSAGE: usize = (1 << 20) + 64;
const MAX_NAME_CHARS: usize = 64;
const NONCE_LEN: usize = 32;
const PROOF_CONTEXT: &[u8] = b"dnet link proof v1";

const FLAG_FIRST: u8 = 0b001;
const FLAG_LAST: u8 = 0b010;
/// The frame belongs to the bulk lane: a piece of a file, or anything
/// else big enough to hold up a chat.
const FLAG_BULK: u8 = 0b100;

const KIND_HELLO: u8 = 1;
const KIND_PROOF: u8 = 2;
const KIND_ENVELOPE: u8 = 3;
/// An envelope for someone else, wrapped for passing on. See `relay.rs`.
const KIND_RELAY: u8 = 4;

struct Peer {
    identity: PublicIdentity,
    nonce: [u8; NONCE_LEN],
    name: Option<String>,
}

struct Incoming {
    total: usize,
    data: Vec<u8>,
}

/// Which of the two lanes a message goes on. Each lane puts together one
/// message at a time, so the two can be interleaved frame by frame, but
/// two messages on the same lane must not be.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Lane {
    /// Chat, receipts, calls, the handshake: anything short.
    Chat,
    /// Pieces of files, and anything else big.
    Bulk,
}

pub(crate) struct Link {
    max_frame: usize,
    my_nonce: [u8; NONCE_LEN],
    /// The message being put together on each lane: chat, then bulk.
    incoming: [Option<Incoming>; 2],
    peer: Option<Peer>,
    /// True once the peer has signed our number with the identity it showed.
    proved: bool,
}

pub(crate) type Links = HashMap<u32, Link>;

/// What one arriving frame led to.
#[derive(Default)]
pub(crate) struct Outcome {
    /// Frames to send back on the same link.
    pub frames: Vec<Vec<u8>>,
    pub events: Vec<Value>,
    /// Envelopes that arrived from a peer that has proved itself.
    pub envelopes: Vec<Vec<u8>>,
    /// Packets being passed on, from a peer that has proved itself.
    pub relays: Vec<Vec<u8>>,
}

/// Cuts one message into frames of at most `max_frame` bytes. The first
/// frame carries the message's length so the other side knows when it has
/// everything.
pub(crate) fn fragment(message: &[u8], max_frame: usize) -> Vec<Vec<u8>> {
    fragment_on(message, max_frame, Lane::Chat)
}

/// Cuts one message into frames for one lane.
pub(crate) fn fragment_on(message: &[u8], max_frame: usize, lane: Lane) -> Vec<Vec<u8>> {
    let lane_flag = match lane {
        Lane::Chat => 0,
        Lane::Bulk => FLAG_BULK,
    };
    let mut frames = Vec::new();
    let mut rest = message;
    let mut first = true;
    loop {
        let header = if first { 5 } else { 1 };
        let take = rest.len().min(max_frame - header);
        let (chunk, remaining) = rest.split_at(take);
        let mut frame = Vec::with_capacity(header + take);
        let last = remaining.is_empty();
        frame.push(
            if first { FLAG_FIRST } else { 0 } | if last { FLAG_LAST } else { 0 } | lane_flag,
        );
        if first {
            frame.extend_from_slice(&(message.len() as u32).to_be_bytes());
        }
        frame.extend_from_slice(chunk);
        frames.push(frame);
        if last {
            return frames;
        }
        rest = remaining;
        first = false;
    }
}

fn proof_message(
    signer_nonce: &[u8],
    verifier_nonce: &[u8],
    signer: &[u8; 32],
    verifier: &[u8; 32],
) -> Vec<u8> {
    let mut message = PROOF_CONTEXT.to_vec();
    message.extend_from_slice(signer_nonce);
    message.extend_from_slice(verifier_nonce);
    message.extend_from_slice(signer);
    message.extend_from_slice(verifier);
    message
}

impl Link {
    /// Starts a link and returns the frames that introduce this device.
    /// `name` is sent only if the user lets strangers see it.
    pub fn open(
        max_frame: usize,
        me: &IdentitySecret,
        name: Option<&str>,
    ) -> Result<(Self, Vec<Vec<u8>>)> {
        if max_frame < MIN_FRAME {
            return Err(CoreError::Invalid(format!(
                "a frame must hold at least {MIN_FRAME} bytes"
            )));
        }
        let link = Self {
            max_frame,
            my_nonce: *random_bytes()?,
            incoming: [None, None],
            peer: None,
            proved: false,
        };
        let mut hello = vec![KIND_HELLO];
        hello.extend_from_slice(&link.my_nonce);
        hello.extend_from_slice(&me.public().to_bytes());
        hello.extend_from_slice(name.unwrap_or_default().as_bytes());
        let frames = fragment(&hello, max_frame);
        Ok((link, frames))
    }

    /// The signing key of the peer, once it has proved itself.
    pub fn peer_key(&self) -> Option<String> {
        self.peer
            .as_ref()
            .filter(|_| self.proved)
            .map(|p| hexcode::encode(&p.identity.signing_key))
    }

    /// How many bytes one frame on this connection carries.
    pub fn room(&self) -> usize {
        self.max_frame
    }

    /// Frames for a packet that is being passed on to or through the peer.
    pub fn relay_frames(&self, packet: &[u8]) -> Vec<Vec<u8>> {
        let mut message = Vec::with_capacity(1 + packet.len());
        message.push(KIND_RELAY);
        message.extend_from_slice(packet);
        fragment(&message, self.max_frame)
    }

    pub fn envelope_frames(&self, envelope: &[u8]) -> Vec<Vec<u8>> {
        self.envelope_frames_on(envelope, Lane::Chat)
    }

    /// Frames for an envelope on the lane given.
    pub fn envelope_frames_on(&self, envelope: &[u8], lane: Lane) -> Vec<Vec<u8>> {
        let mut message = Vec::with_capacity(1 + envelope.len());
        message.push(KIND_ENVELOPE);
        message.extend_from_slice(envelope);
        fragment_on(&message, self.max_frame, lane)
    }

    /// Frames for a packet being passed on, on the lane given.
    pub fn relay_frames_on(&self, packet: &[u8], lane: Lane) -> Vec<Vec<u8>> {
        let mut message = Vec::with_capacity(1 + packet.len());
        message.push(KIND_RELAY);
        message.extend_from_slice(packet);
        fragment_on(&message, self.max_frame, lane)
    }

    /// Adds one frame to the message being put together on its lane.
    /// Returns the message when its last frame arrives. Anything malformed
    /// throws that lane's partial message away; the other lane's is kept.
    fn assemble(&mut self, frame: &[u8]) -> Option<Vec<u8>> {
        let (&flags, mut data) = frame.split_first()?;
        let slot = usize::from(flags & FLAG_BULK != 0);
        if flags & !(FLAG_FIRST | FLAG_LAST | FLAG_BULK) != 0 {
            self.incoming[slot] = None;
            return None;
        }
        if flags & FLAG_FIRST != 0 {
            self.incoming[slot] = None;
            let length: [u8; 4] = data.get(..4)?.try_into().ok()?;
            let total = u32::from_be_bytes(length) as usize;
            if total == 0 || total > MAX_MESSAGE {
                return None;
            }
            // Grows as data arrives, so a false length costs nothing.
            self.incoming[slot] = Some(Incoming {
                total,
                data: Vec::new(),
            });
            data = &data[4..];
        }
        let incoming = self.incoming[slot].as_mut()?;
        if incoming.data.len() + data.len() > incoming.total {
            self.incoming[slot] = None;
            return None;
        }
        incoming.data.extend_from_slice(data);
        if flags & FLAG_LAST == 0 {
            return None;
        }
        let done = self.incoming[slot].take()?;
        (done.data.len() == done.total).then_some(done.data)
    }

    /// Takes in one frame from the radio.
    pub fn receive(&mut self, id: u32, frame: &[u8], me: &IdentitySecret) -> Result<Outcome> {
        let mut outcome = Outcome::default();
        let Some(message) = self.assemble(frame) else {
            return Ok(outcome);
        };
        let Some((&kind, body)) = message.split_first() else {
            return Ok(outcome);
        };
        match kind {
            KIND_HELLO => self.on_hello(body, me, &mut outcome),
            KIND_PROOF => self.on_proof(id, body, me, &mut outcome),
            KIND_ENVELOPE if self.proved => outcome.envelopes.push(body.to_vec()),
            KIND_RELAY if self.proved => outcome.relays.push(body.to_vec()),
            // An envelope before the proof, or an unknown kind. Dropped.
            _ => {}
        }
        Ok(outcome)
    }

    fn on_hello(&mut self, body: &[u8], me: &IdentitySecret, outcome: &mut Outcome) {
        // One identity per link. A second hello cannot swap it.
        if self.peer.is_some() {
            return;
        }
        let identity_len = me.public().to_bytes().len();
        if body.len() < NONCE_LEN + identity_len {
            return;
        }
        let (nonce, rest) = body.split_at(NONCE_LEN);
        let (identity, name) = rest.split_at(identity_len);
        let Ok(identity) = PublicIdentity::from_bytes(identity) else {
            return;
        };
        if identity.verify().is_err() || identity.signing_key == me.signing_public() {
            return;
        }
        let name = std::str::from_utf8(name)
            .ok()
            .map(str::trim)
            .filter(|n| !n.is_empty() && n.chars().count() <= MAX_NAME_CHARS)
            .map(str::to_string);

        // Sign their number, to prove this device holds the identity it
        // showed.
        let signature = me.sign(&proof_message(
            &self.my_nonce,
            nonce,
            &me.public().hash(),
            &identity.hash(),
        ));
        let mut proof = vec![KIND_PROOF];
        proof.extend_from_slice(&signature);
        outcome.frames.extend(fragment(&proof, self.max_frame));

        self.peer = Some(Peer {
            identity,
            nonce: nonce.try_into().expect("split at the nonce length"),
            name,
        });
    }

    fn on_proof(&mut self, id: u32, body: &[u8], me: &IdentitySecret, outcome: &mut Outcome) {
        let Some(peer) = self.peer.as_ref().filter(|_| !self.proved) else {
            return;
        };
        if body.len() != SIGNATURE_LEN {
            return;
        }
        let expected = proof_message(
            &peer.nonce,
            &self.my_nonce,
            &peer.identity.hash(),
            &me.public().hash(),
        );
        if verify_signature(&peer.identity.signing_key, &expected, body).is_err() {
            return;
        }
        self.proved = true;
        outcome.events.push(json!({
            "kind": "peer",
            "link": id,
            "key": hexcode::encode(&peer.identity.signing_key),
            "identity": hexcode::encode(&peer.identity.to_bytes()),
            "fingerprint": peer.identity.fingerprint(),
            "spoken_code": peer.identity.spoken_code(),
            "name": peer.name,
        }));
    }
}

/// Envelopes bigger than this are not chat, whatever they hold: they go
/// once, on the fastest link, on the bulk lane, after chat.
pub(crate) const CHAT_MOST: usize = 16 * 1024;

/// What a delivery is, for the app's queue: chat first, then pieces of
/// small files, then pieces of big ones.
pub(crate) fn class_of(bytes: usize, class: Option<&str>) -> &'static str {
    match class {
        Some("big") => "big",
        Some("small") => "small",
        _ if bytes > CHAT_MOST => "small",
        _ => "chat",
    }
}

/// The links that reach `peer`, fastest first.
pub(crate) fn links_to<'a>(links: &'a Links, peer: &str) -> Vec<(u32, &'a Link)> {
    let mut reaching: Vec<(u32, &Link)> = links
        .iter()
        .filter(|(_, link)| link.peer_key().as_deref() == Some(peer))
        .map(|(id, link)| (*id, link))
        .collect();
    reaching.sort_by_key(|(id, link)| (std::cmp::Reverse(link.room()), *id));
    reaching
}

/// What to send for one envelope to `peer`, if any link reaches them.
///
/// Chat goes on every link that reaches them, Bluetooth and Wi-Fi alike,
/// so that whichever arrives first counts and a link that died without a
/// word loses nothing; the other side takes it in once. A piece of a file,
/// or anything else big, goes once, on the bulk lane of the fastest link.
pub(crate) fn deliveries_for(
    links: &Links,
    peer: &str,
    envelope: &[u8],
    class: Option<&str>,
) -> Vec<Value> {
    let class = class_of(envelope.len(), class);
    let reaching = links_to(links, peer);
    let hex = |frames: Vec<Vec<u8>>| -> Vec<String> {
        frames.iter().map(|f| hexcode::encode(f)).collect()
    };
    if class == "chat" {
        reaching
            .iter()
            .map(|(id, link)| {
                json!({ "link": id, "class": class, "frames": hex(link.envelope_frames(envelope)) })
            })
            .collect()
    } else {
        reaching
            .first()
            .map(|(id, link)| {
                let frames = hex(link.envelope_frames_on(envelope, Lane::Bulk));
                json!({ "link": id, "class": class, "frames": frames })
            })
            .into_iter()
            .collect()
    }
}

/// How long a copy of an envelope is remembered, and how many are.
const SEEN_FOR: Duration = Duration::from_secs(120);
const SEEN_MOST: usize = 1024;

/// Envelopes lately taken in, so that the copy of one sent on a second
/// link to the same device is taken in once.
///
/// When Bluetooth and Wi-Fi both reach someone, anything short is sent on
/// both, and whichever copy arrives first is the one that counts. The
/// other is dropped, but only while the link the first came on is still
/// open: a copy sent again because a link died is a resend, and is taken
/// in as before, so that its answer goes back.
#[derive(Default)]
pub(crate) struct Seen {
    order: VecDeque<([u8; 16], Instant)>,
    by: HashMap<[u8; 16], (u32, Instant)>,
}

impl Seen {
    /// Whether `envelope`, arriving on `link`, is to be taken in. `open`
    /// says whether a link is still up.
    pub fn first(&mut self, link: u32, envelope: &[u8], open: impl Fn(u32) -> bool) -> bool {
        let now = Instant::now();
        while let Some(&(oldest, at)) = self.order.front() {
            if self.order.len() <= SEEN_MOST && now.duration_since(at) < SEEN_FOR {
                break;
            }
            self.order.pop_front();
            if self.by.get(&oldest).is_some_and(|&(_, when)| when == at) {
                self.by.remove(&oldest);
            }
        }
        let digest = Sha256::digest(envelope);
        let key: [u8; 16] = digest[..16].try_into().expect("sixteen of thirty-two");
        if let Some(&(other, _)) = self.by.get(&key) {
            if other != link && open(other) {
                return false;
            }
        }
        self.by.insert(key, (link, now));
        self.order.push_back((key, now));
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rejoin(frames: &[Vec<u8>]) -> Option<Vec<u8>> {
        let me = IdentitySecret::generate().unwrap();
        let (mut link, _) = Link::open(64, &me, None).unwrap();
        frames.iter().find_map(|f| link.assemble(f))
    }

    #[test]
    fn a_message_cut_up_comes_back_whole() {
        for length in [1usize, 14, 15, 16, 19, 20, 21, 100, 5000] {
            let message: Vec<u8> = (0..length).map(|i| i as u8).collect();
            for max_frame in [20usize, 23, 180, 512] {
                let frames = fragment(&message, max_frame);
                assert!(frames.iter().all(|f| f.len() <= max_frame));
                assert_eq!(
                    rejoin(&frames),
                    Some(message.clone()),
                    "{length} bytes in frames of {max_frame}"
                );
            }
        }
    }

    #[test]
    fn a_missing_frame_means_no_message() {
        let frames = fragment(&[9u8; 200], 20);
        let mut short = frames.clone();
        short.remove(3);
        assert_eq!(rejoin(&short), None);
    }

    #[test]
    fn a_new_message_replaces_a_half_received_one() {
        let me = IdentitySecret::generate().unwrap();
        let (mut link, _) = Link::open(20, &me, None).unwrap();
        let first = fragment(&[1u8; 100], 20);
        assert_eq!(link.assemble(&first[0]), None);
        let second = fragment(&[2u8; 10], 20);
        assert_eq!(link.assemble(&second[0]), Some(vec![2u8; 10]));
    }

    #[test]
    fn nothing_is_passed_on_for_a_device_that_has_not_proved_who_it_is() {
        // Passing things on costs storage and airtime. A device that only
        // connected and never proved itself gets none of either.
        let me = IdentitySecret::generate().unwrap();
        let (mut link, _) = Link::open(64, &me, None).unwrap();
        let mut message = vec![KIND_RELAY];
        message.extend_from_slice(&[7u8; 100]);
        for frame in fragment(&message, 64) {
            let outcome = link.receive(1, &frame, &me).unwrap();
            assert!(outcome.relays.is_empty());
            assert!(outcome.envelopes.is_empty());
        }
    }

    #[test]
    fn frames_smaller_than_bluetooth_allows_are_refused() {
        let me = IdentitySecret::generate().unwrap();
        assert!(Link::open(19, &me, None).is_err());
    }

    #[test]
    fn a_chat_can_go_between_the_frames_of_a_piece() {
        let me = IdentitySecret::generate().unwrap();
        let (mut link, _) = Link::open(20, &me, None).unwrap();
        let piece = fragment_on(&[3u8; 200], 20, Lane::Bulk);
        let chat = fragment(&[4u8; 30], 20);
        let mut out = Vec::new();
        for (i, frame) in piece.iter().enumerate() {
            out.extend(link.assemble(frame));
            if i == 2 {
                for frame in &chat {
                    out.extend(link.assemble(frame));
                }
            }
        }
        assert_eq!(out, vec![vec![4u8; 30], vec![3u8; 200]]);
    }

    #[test]
    fn a_copy_on_a_second_link_is_taken_in_once() {
        let mut seen = Seen::default();
        let open = |_| true;
        assert!(seen.first(1, b"hello", open));
        assert!(!seen.first(2, b"hello", open), "the copy over Wi-Fi");
        assert!(seen.first(2, b"another", open));
        // Sent again on the same link, it is a resend and is taken in.
        assert!(seen.first(1, b"hello", open));
    }

    #[test]
    fn a_copy_sent_again_after_its_link_died_is_taken_in() {
        let mut seen = Seen::default();
        assert!(seen.first(1, b"hello", |_| true));
        assert!(seen.first(2, b"hello", |link| link != 1));
    }

    /// A link from `me` on which `them` has proved who they are.
    fn proved(me: &IdentitySecret, them: &IdentitySecret, max_frame: usize) -> Link {
        let (mut mine, hello_mine) = Link::open(max_frame, me, None).unwrap();
        let (mut theirs, hello_theirs) = Link::open(max_frame, them, None).unwrap();
        let mut to_me = Vec::new();
        let mut to_them = Vec::new();
        for frame in &hello_theirs {
            to_them.extend(mine.receive(1, frame, me).unwrap().frames);
        }
        for frame in &hello_mine {
            to_me.extend(theirs.receive(1, frame, them).unwrap().frames);
        }
        for frame in &to_me {
            mine.receive(1, frame, me).unwrap();
        }
        assert!(mine.peer_key().is_some());
        mine
    }

    #[test]
    fn chat_goes_on_every_link_and_a_piece_on_the_fastest_alone() {
        let (me, mira) = (
            IdentitySecret::generate().unwrap(),
            IdentitySecret::generate().unwrap(),
        );
        let key = hexcode::encode(&mira.signing_public());
        let mut links = Links::new();
        links.insert(1, proved(&me, &mira, 180));
        links.insert(1 << 20, proved(&me, &mira, 16384));

        let chat = deliveries_for(&links, &key, &[1u8; 300], None);
        assert_eq!(chat.len(), 2);
        assert!(chat.iter().all(|d| d["class"] == "chat"));

        for (bytes, class, named) in [
            (300, "big", Some("big")),
            (300, "small", Some("small")),
            (CHAT_MOST + 1, "small", None),
        ] {
            let bulk = deliveries_for(&links, &key, &vec![2u8; bytes], named);
            assert_eq!(bulk.len(), 1, "{class}");
            assert_eq!(bulk[0]["link"], 1 << 20, "on Wi-Fi");
            assert_eq!(bulk[0]["class"], class);
            let first = hexcode::decode(bulk[0]["frames"][0].as_str().unwrap()).unwrap();
            assert_eq!(first[0] & FLAG_BULK, FLAG_BULK, "on the bulk lane");
        }
        assert!(deliveries_for(&links, "someone else", &[1u8; 3], None).is_empty());
    }
}
