//! Passing envelopes on for other people.
//!
//! When the person an envelope is for is not in range, it is handed to
//! whoever is, who hands it on at once to whoever is in range of them.
//! An envelope travelling this way is wrapped in a *packet*:
//!
//! ```text
//! [hops left][hops so far][packet id, 16 bytes][tag, 8 bytes][envelope]
//! ```
//!
//! The envelope inside is sealed to the person it is for, exactly as when
//! it goes direct. A device passing it on cannot open it and cannot tell
//! who sent it.
//!
//! What a device passing it on *can* see is the tag. The tag is worked out
//! from the recipient's public key, so anyone who already knows that key
//! can tell a packet is for them, though not from whom or what it says.
//! This is not an anonymity network and must never be described as one.
//!
//! A packet is passed on at most a few times and is dropped if it has
//! been seen before. A device passing on someone else's packet never
//! writes it down: it goes from memory to whoever is in range now, and is
//! then forgotten. Only the sender keeps its own packets, sealed, and
//! hands them to each device it meets until they arrive or run out.
//!
//! A piece of a file travels differently. It is big and there are many of
//! them, so it is only *passed along*: handed at once to whoever is in
//! range, never kept, and through two devices at most. The top bit of the
//! first byte marks such a packet.
//!
//! ## Maps
//!
//! So that the app can draw the mesh and show how a message would hop,
//! each device tells the devices in range which devices it hears, over
//! which radio and roughly how near. That is a *map*:
//!
//! ```text
//! [0x40][flags][n][n keys, 32 bytes each][m][m links, 5 bytes each]
//! link: [from][to][radios][near][told]
//! ```
//!
//! `from` and `to` count from the sender itself, which is 0, then the keys
//! in order. A map is never passed on as it is: each device makes its own
//! from what it hears and what it was told, and the word travels no
//! further than a packet can. It holds signing keys only, which the radio
//! shows anyone in range anyway, never names. A device is named only once
//! it has sent a map of its own, and not if that map asks not to be: the
//! user chose to be invisible. What a device was told is never told back
//! to it, and is forgotten soon unless it is told again. An old device
//! drops a map, since its first byte is not a hop count.

use std::collections::{HashMap, HashSet, VecDeque};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::error::{CoreError, Result};
use crate::hexcode;
use crate::vault::Vault;

const CARRY: &str = "carry";
const TAG_CONTEXT: &[u8] = b"dnet relay tag v1";
const HEADER: usize = 1 + 1 + 16 + 8;
/// How many times a packet may be passed on after it leaves its sender.
pub(crate) const HOPS: u8 = 4;
/// Marks a packet that is passed along and never carried.
const PASSING: u8 = 0x80;
/// How many times such a packet may be passed on. Every device in range
/// of one passes it on, so a file sent far would keep a crowd busy.
const PASSING_HOPS: u8 = 2;
/// Larger than any honest envelope: one piece of a file, sealed.
const MAX_PACKET: usize = 80 * 1024;
/// How much one device will carry for other people.
const MAX_CARRIED: usize = 500;
const MAX_CARRIED_BYTES: usize = 8 * 1024 * 1024;
const KEEP_SECS: u64 = 72 * 60 * 60;
/// How many packet ids are remembered, to recognise one coming round again.
const REMEMBERED: usize = 8192;

pub(crate) type Tag = [u8; 8];
type Id = [u8; 16];

/// Marks a map. An envelope packet's first byte is a hop count of at most
/// [`HOPS`], with or without [`PASSING`], so it is never this.
const MAP: u8 = 0x40;
/// The sender asks not to be named to anyone.
const MAP_HIDDEN: u8 = 0b01;
/// The sender passes nothing on for others, so nobody is reached through
/// it, and its map names nobody.
const MAP_NO_RELAY: u8 = 0b10;
/// How far a map reaches, in links: as far as a packet can travel.
pub(crate) const MAP_REACH: u8 = HOPS + 1;
const MAP_KEYS: usize = 64;
const MAP_LINKS: usize = 160;
const MAP_LINK_LEN: usize = 5;
const KEY_LEN: usize = 32;
/// How long what a device said about its links is believed.
pub(crate) const MAP_FRESH_MS: u64 = 30_000;
/// A device whose map has not changed sends it again this often, so the
/// devices in range keep believing it.
pub(crate) const MAP_AGAIN_MS: u64 = 10_000;
/// Which radios carry a link.
pub(crate) const BLUETOOTH: u8 = 0b01;
pub(crate) const WIFI: u8 = 0b10;
/// Set on a link to a device that passes nothing on: the mesh ends there.
pub(crate) const ENDS: u8 = 0x80;

/// One link on a map: `from` hears `to`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct MapLink {
    pub from: String,
    pub to: String,
    /// [`BLUETOOTH`], [`WIFI`] or both, with [`ENDS`] if `to` passes
    /// nothing on.
    pub radios: u8,
    /// How strongly `from` hears `to`: 0 when not known, else 1 very
    /// close, 2 near, 3 far.
    pub near: u8,
    /// How many devices the word passed through to get here: one for a
    /// link a device in range told of itself.
    pub told: u8,
}

/// One device in range, as the app knows the link to it.
#[derive(Clone, Debug, Deserialize)]
pub(crate) struct Neighbour {
    /// Its signing key, hex.
    pub key: String,
    #[serde(default)]
    pub bluetooth: bool,
    #[serde(default)]
    pub wifi: bool,
    /// 0 when not known, else 1 very close, 2 near, 3 far.
    #[serde(default)]
    pub near: u8,
}

impl Neighbour {
    fn radios(&self) -> u8 {
        (if self.bluetooth { BLUETOOTH } else { 0 }) | if self.wifi { WIFI } else { 0 }
    }
}

/// What one device in range last said about its links.
struct Report {
    at: u64,
    hidden: bool,
    relays: bool,
    links: Vec<MapLink>,
}

/// The mesh as the devices in range last told it.
pub(crate) struct MeshView {
    /// Every link they named, once each, by the shortest word.
    pub links: Vec<MapLink>,
    /// Devices in range that asked not to be named.
    pub hidden: Vec<String>,
    /// Devices in range that pass nothing on.
    pub ends: Vec<String>,
}

impl MeshView {
    pub fn to_json(&self) -> Value {
        let links: Vec<Value> = self
            .links
            .iter()
            .map(|link| {
                json!({
                    "from": link.from,
                    "to": link.to,
                    "bluetooth": link.radios & BLUETOOTH != 0,
                    "wifi": link.radios & WIFI != 0,
                    "ends": link.radios & ENDS != 0,
                    "near": link.near,
                    "told": link.told,
                })
            })
            .collect();
        json!({ "links": links, "hidden": self.hidden, "ends": self.ends })
    }
}

/// The time in milliseconds, for maps.
pub(crate) fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Writes a map. Links that would need more than [`MAP_KEYS`] keys, or
/// come after the first [`MAP_LINKS`], are left out: nearest first, so
/// what is left out is the furthest.
fn write_map(flags: u8, me: &str, links: &[MapLink]) -> Vec<u8> {
    let mut keys: Vec<&str> = Vec::new();
    let mut kept: Vec<[u8; MAP_LINK_LEN]> = Vec::new();
    for link in links {
        if kept.len() == MAP_LINKS {
            break;
        }
        let new: Vec<&str> = [link.from.as_str(), link.to.as_str()]
            .into_iter()
            .filter(|key| *key != me && !keys.contains(key))
            .collect();
        if keys.len() + new.len() > MAP_KEYS
            || new.iter().any(|key| hexcode::decode_exact::<KEY_LEN>(key).is_err())
        {
            continue;
        }
        for key in new {
            if !keys.contains(&key) {
                keys.push(key);
            }
        }
        let slot = |key: &str| match keys.iter().position(|k| *k == key) {
            Some(at) => at as u8 + 1,
            None => 0,
        };
        kept.push([
            slot(&link.from),
            slot(&link.to),
            link.radios,
            link.near,
            link.told,
        ]);
    }
    let mut packet = vec![MAP, flags, keys.len() as u8];
    for key in &keys {
        packet.extend_from_slice(&hexcode::decode_exact::<KEY_LEN>(key).expect("checked above"));
    }
    packet.push(kept.len() as u8);
    for link in kept {
        packet.extend_from_slice(&link);
    }
    packet
}

/// Reads a map from `sender`: whether it asks not to be named, whether it
/// passes things on, and its links. None for anything malformed, or that
/// claims to reach further than a packet could.
fn read_map(sender: &str, packet: &[u8]) -> Option<(bool, bool, Vec<MapLink>)> {
    let (&MAP, rest) = packet.split_first()? else {
        return None;
    };
    let (&flags, rest) = rest.split_first()?;
    let (&count, rest) = rest.split_first()?;
    let count = count as usize;
    if count > MAP_KEYS || rest.len() < count * KEY_LEN + 1 {
        return None;
    }
    let (keys, rest) = rest.split_at(count * KEY_LEN);
    let mut names = vec![sender.to_string()];
    for key in keys.chunks(KEY_LEN) {
        let key = hexcode::encode(key);
        if names.contains(&key) {
            return None;
        }
        names.push(key);
    }
    let (&many, rest) = rest.split_first()?;
    let many = many as usize;
    if many > MAP_LINKS || rest.len() != many * MAP_LINK_LEN {
        return None;
    }
    let (hidden, relays) = (flags & MAP_HIDDEN != 0, flags & MAP_NO_RELAY == 0);
    // Someone hidden names nobody, and neither does someone who passes
    // nothing on.
    if (hidden || !relays) && (count > 0 || many > 0) {
        return None;
    }
    let mut links = Vec::with_capacity(many);
    for raw in rest.chunks(MAP_LINK_LEN) {
        let [from, to, radios, near, told]: [u8; MAP_LINK_LEN] = raw.try_into().ok()?;
        let (from, to) = (from as usize, to as usize);
        if from > count
            || to > count
            || from == to
            || radios & (BLUETOOTH | WIFI) == 0
            || radios & !(BLUETOOTH | WIFI | ENDS) != 0
            || near > 3
            || told as u16 + 2 > MAP_REACH as u16
        {
            return None;
        }
        links.push(MapLink {
            from: names[from].clone(),
            to: names[to].clone(),
            radios,
            near,
            told: told + 1,
        });
    }
    Some((hidden, relays, links))
}

/// The tag for packets to whoever holds `key`.
pub(crate) fn tag_of(key: &[u8]) -> Tag {
    let digest = Sha256::new()
        .chain_update(TAG_CONTEXT)
        .chain_update(key)
        .finalize();
    digest[..8]
        .try_into()
        .expect("a SHA-256 digest is 32 bytes")
}

/// Wraps a sealed envelope for passing on. The packet's id comes from the
/// envelope itself, so the same envelope sent again is recognised as the
/// same packet.
pub(crate) fn wrap(to: &[u8], envelope: &[u8]) -> Vec<u8> {
    let mut packet = Vec::with_capacity(HEADER + envelope.len());
    packet.push(HOPS);
    packet.push(0);
    packet.extend_from_slice(&Sha256::digest(envelope)[..16]);
    packet.extend_from_slice(&tag_of(to));
    packet.extend_from_slice(envelope);
    packet
}

/// The same, for something that is only worth having now: it is passed
/// along by whoever is in range and kept by nobody.
fn wrap_passing(to: &[u8], envelope: &[u8]) -> Vec<u8> {
    let mut packet = wrap(to, envelope);
    packet[0] = PASSING_HOPS | PASSING;
    packet
}

struct Packet<'a> {
    left: u8,
    so_far: u8,
    passing: bool,
    id: Id,
    tag: Tag,
    envelope: &'a [u8],
}

fn parse(packet: &[u8]) -> Option<Packet<'_>> {
    if packet.len() <= HEADER || packet.len() > MAX_PACKET {
        return None;
    }
    let (left, so_far, passing) = (packet[0] & !PASSING, packet[1], packet[0] & PASSING != 0);
    // Nobody honest sends a packet claiming more hops than there are.
    if left > HOPS || so_far > HOPS || left as u16 + so_far as u16 > HOPS as u16 {
        return None;
    }
    Some(Packet {
        left,
        so_far,
        passing,
        id: packet[2..18].try_into().expect("sixteen bytes were taken"),
        tag: packet[18..26].try_into().expect("eight bytes were taken"),
        envelope: &packet[HEADER..],
    })
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// What to do with a packet that arrived.
pub(crate) enum Verdict {
    /// It is for this device. Open the envelope. `hops` is how many
    /// links it crossed to get here: one if its writer handed it over
    /// themselves, two if one device passed it on, and so on.
    Mine { envelope: Vec<u8>, hops: u8 },
    /// It is for someone else. Pass this on.
    Onward(Vec<u8>),
    /// A map that says something new about who is linked to whom.
    Mapped,
    /// Seen before, spent, or not a packet.
    Drop,
}

/// What is remembered only while the app runs.
#[derive(Default)]
pub(crate) struct Live {
    /// Packets seen, with the meeting round each was last seen in.
    seen: HashMap<Id, u64>,
    order: VecDeque<Id>,
    /// Which devices each of the user's own packets has been handed to.
    given: HashMap<Id, HashSet<String>>,
    /// Goes up each time a device comes into range. A packet seen again in
    /// the same round is a copy going round in circles and is dropped. In
    /// a later round it is the sender trying again over a new path, since
    /// nobody along the way kept it, and it is passed on once more.
    round: u64,
    /// What each device in range last said about its links, by key.
    maps: HashMap<String, Report>,
    /// When each device in range was last sent this device's map, and a
    /// digest of it, so it is sent again only when it changes or is due.
    mapped: HashMap<String, (u64, [u8; 32])>,
    /// How much more each device in range may have passed on through this
    /// one, by key. See [`Allowance`].
    allowance: HashMap<String, Allowance>,
}

/// How much one device may hand over for passing on. Someone flooding
/// the mesh with packets nobody asked for would otherwise have every
/// device in range pass each one on to everyone in range of them. What
/// goes over the allowance is not passed on; it is dropped here, as if
/// out of range. Packets for this device are never counted.
///
/// The burst covers the most an honest sender hands over at once: every
/// packet it carries, on meeting a device. After that it refills at a pace
/// well above chat, and above what Bluetooth carries for pieces of files.
#[derive(Clone, Copy)]
struct Allowance {
    packets: f64,
    bytes: f64,
    at: u64,
}

const ALLOW_PACKETS: f64 = (MAX_CARRIED + 100) as f64;
const ALLOW_BYTES: f64 = (32 * 1024 * 1024) as f64;
const REFILL_PACKETS_PER_SEC: f64 = 5.0;
const REFILL_BYTES_PER_SEC: f64 = (2 * 1024 * 1024) as f64;
/// Allowances are kept for this many devices at most; the ones not heard
/// from for longest go first.
const ALLOWANCES: usize = 256;

impl Allowance {
    fn full(now: u64) -> Self {
        Self {
            packets: ALLOW_PACKETS,
            bytes: ALLOW_BYTES,
            at: now,
        }
    }

    /// Takes one packet of `bytes` from the allowance, if it has room.
    fn take(&mut self, bytes: usize, now: u64) -> bool {
        let secs = now.saturating_sub(self.at) as f64 / 1000.0;
        self.at = self.at.max(now);
        self.packets = (self.packets + secs * REFILL_PACKETS_PER_SEC).min(ALLOW_PACKETS);
        self.bytes = (self.bytes + secs * REFILL_BYTES_PER_SEC).min(ALLOW_BYTES);
        if self.packets < 1.0 || self.bytes < bytes as f64 {
            return false;
        }
        self.packets -= 1.0;
        self.bytes -= bytes as f64;
        true
    }
}

impl Live {
    /// Whether `from` may have one more packet of `bytes` passed on now.
    fn allow(&mut self, from: &str, bytes: usize, now: u64) -> bool {
        if !self.allowance.contains_key(from) && self.allowance.len() >= ALLOWANCES {
            let oldest = self
                .allowance
                .iter()
                .min_by_key(|(_, allowance)| allowance.at)
                .map(|(key, _)| key.clone());
            if let Some(oldest) = oldest {
                self.allowance.remove(&oldest);
            }
        }
        self.allowance
            .entry(from.to_string())
            .or_insert_with(|| Allowance::full(now))
            .take(bytes, now)
    }

    /// Remembers a packet. False if it was already seen this round.
    fn remember(&mut self, id: Id) -> bool {
        let round = self.round;
        match self.seen.insert(id, round) {
            Some(seen) if seen == round => return false,
            Some(_) => return true,
            None => {}
        }
        self.order.push_back(id);
        if self.order.len() > REMEMBERED {
            if let Some(oldest) = self.order.pop_front() {
                self.seen.remove(&oldest);
                self.given.remove(&oldest);
            }
        }
        true
    }

    /// A device has come into range: a new round, and it may be handed
    /// the user's own waiting packets again, since nobody kept them.
    pub fn met(&mut self, peer: &str) {
        self.round += 1;
        for handed in self.given.values_mut() {
            handed.remove(peer);
        }
    }

    /// Takes in a map from a device in range. True if it says something
    /// new.
    fn take_map(&mut self, from: &str, packet: &[u8], now: u64) -> bool {
        let Some((hidden, relays, links)) = read_map(from, packet) else {
            return false;
        };
        let same = self.fresh(from, now).is_some_and(|old| {
            old.hidden == hidden && old.relays == relays && old.links == links
        });
        self.maps.insert(
            from.to_string(),
            Report {
                at: now,
                hidden,
                relays,
                links,
            },
        );
        !same
    }

    fn fresh(&self, key: &str, now: u64) -> Option<&Report> {
        self.maps
            .get(key)
            .filter(|report| now.saturating_sub(report.at) <= MAP_FRESH_MS)
    }

    /// This device's map for each device in range that is due one: it
    /// would say something new, or has said nothing for a while. Someone
    /// `hidden` names nobody and asks not to be named. Someone who does
    /// not pass things on (`relays` false) names nobody either, since
    /// nobody is reached through them.
    pub fn share(
        &mut self,
        me: &str,
        neighbours: &[Neighbour],
        hidden: bool,
        relays: bool,
        now: u64,
    ) -> Vec<(String, Vec<u8>)> {
        // Whoever is gone is forgotten at once.
        let here = |key: &String| neighbours.iter().any(|n| &n.key == key);
        self.maps.retain(|key, _| here(key));
        self.mapped.retain(|key, _| here(key));
        let mut out = Vec::new();
        for to in neighbours {
            let packet = if hidden {
                write_map(MAP_HIDDEN, me, &[])
            } else if !relays {
                write_map(MAP_NO_RELAY, me, &[])
            } else {
                write_map(0, me, &self.links_for(me, &to.key, neighbours, now))
            };
            let digest: [u8; 32] = Sha256::digest(&packet).into();
            let due = self.mapped.get(&to.key).is_none_or(|(at, sent)| {
                *sent != digest || now.saturating_sub(*at) >= MAP_AGAIN_MS
            });
            if due {
                self.mapped.insert(to.key.clone(), (now, digest));
                out.push((to.key.clone(), packet));
            }
        }
        out
    }

    /// The links to tell `to` of, nearest first: what this device hears of
    /// devices that may be named, then what devices in range told of,
    /// except what `to` told and anything about `to` itself.
    fn links_for(&self, me: &str, to: &str, neighbours: &[Neighbour], now: u64) -> Vec<MapLink> {
        let mut own: Vec<MapLink> = neighbours
            .iter()
            .filter(|n| n.key != to && n.key != me && n.radios() != 0)
            .filter_map(|n| {
                let report = self.fresh(&n.key, now).filter(|r| !r.hidden)?;
                Some(MapLink {
                    from: me.to_string(),
                    to: n.key.clone(),
                    radios: n.radios() | if report.relays { 0 } else { ENDS },
                    near: n.near.min(3),
                    told: 0,
                })
            })
            .collect();
        own.sort_by(|a, b| a.to.cmp(&b.to));
        let mut told: Vec<&MapLink> = neighbours
            .iter()
            .filter(|n| n.key != to)
            .filter_map(|n| self.fresh(&n.key, now))
            .flat_map(|report| &report.links)
            .filter(|link| {
                link.told + 2 <= MAP_REACH
                    && ![me, to].contains(&link.from.as_str())
                    && ![me, to].contains(&link.to.as_str())
            })
            .collect();
        told.sort_by(|a, b| (a.told, &a.from, &a.to).cmp(&(b.told, &b.from, &b.to)));
        let mut links = own;
        for link in told {
            if !links
                .iter()
                .any(|have| have.from == link.from && have.to == link.to)
            {
                links.push(link.clone());
            }
        }
        links
    }

    /// The mesh as the devices in `current` last told it.
    pub fn view(&self, current: &[String], now: u64) -> MeshView {
        let mut view = MeshView {
            links: Vec::new(),
            hidden: Vec::new(),
            ends: Vec::new(),
        };
        for key in current {
            let Some(report) = self.fresh(key, now) else {
                continue;
            };
            if report.hidden {
                view.hidden.push(key.clone());
            }
            if !report.relays {
                view.ends.push(key.clone());
            }
            for link in &report.links {
                match view
                    .links
                    .iter_mut()
                    .find(|have| have.from == link.from && have.to == link.to)
                {
                    Some(have) if have.told <= link.told => {}
                    Some(have) => *have = link.clone(),
                    None => view.links.push(link.clone()),
                }
            }
        }
        view
    }
}

pub(crate) struct Relay<'a> {
    pub vault: &'a Vault,
    pub live: &'a mut Live,
    pub my_tag: Tag,
}

impl Relay<'_> {
    /// Decides what to do with a packet handed over by `from`.
    pub fn accept(&mut self, from: &str, packet: &[u8]) -> Result<Verdict> {
        // A map is taken in and goes no further. This device tells its own.
        if packet.first() == Some(&MAP) {
            return Ok(if self.live.take_map(from, packet, now_ms()) {
                Verdict::Mapped
            } else {
                Verdict::Drop
            });
        }
        let Some(parsed) = parse(packet) else {
            return Ok(Verdict::Drop);
        };
        if parsed.tag == self.my_tag {
            // Taken in every time it comes. The same message arriving
            // again is answered again, which is how its sender finds out
            // it arrived if the first answer was lost. It goes no further.
            return Ok(Verdict::Mine {
                envelope: parsed.envelope.to_vec(),
                hops: parsed.so_far + 1,
            });
        }
        let fresh = self.live.remember(parsed.id);
        // Whoever handed it over has it already.
        self.live
            .given
            .entry(parsed.id)
            .or_default()
            .insert(from.to_string());
        if !fresh || parsed.left == 0 {
            return Ok(Verdict::Drop);
        }
        // More than anyone honest hands over: a flood, not passed on.
        if !self.live.allow(from, packet.len(), now_ms()) {
            return Ok(Verdict::Drop);
        }
        let mut onward = packet.to_vec();
        onward[0] = (parsed.left - 1) | if parsed.passing { PASSING } else { 0 };
        onward[1] = parsed.so_far + 1;
        // Handed on from memory to whoever is in range now. Never kept.
        Ok(Verdict::Onward(onward))
    }

    /// Sends something of the user's own by way of whoever is in range
    /// now. Nobody keeps it: if it does not arrive, it is gone.
    pub fn send_passing(&mut self, to: &[u8], envelope: &[u8]) -> Vec<u8> {
        let packet = wrap_passing(to, envelope);
        if let Some(parsed) = parse(&packet) {
            self.live.remember(parsed.id);
        }
        packet
    }

    /// How many of the user's own packets are waiting for a path, and how
    /// many bytes they come to. Nothing of anyone else's is kept.
    pub fn carrying(&self) -> Result<(usize, usize)> {
        let held = self.stored()?;
        Ok((
            held.len(),
            held.iter().map(|(_, _, packet)| packet.len()).sum(),
        ))
    }

    /// Sends something of the user's own by way of others. Returns the
    /// packet, which is also kept to hand to whoever is met later.
    pub fn send(&mut self, to: &[u8], envelope: &[u8]) -> Result<Vec<u8>> {
        let packet = wrap(to, envelope);
        if let Some(parsed) = parse(&packet) {
            self.live.remember(parsed.id);
            self.carry(&packet)?;
        }
        Ok(packet)
    }

    /// Keeps one of the user's own packets to hand to devices met later.
    /// Makes room by letting go of the oldest, and of anything kept too
    /// long.
    fn carry(&self, packet: &[u8]) -> Result<()> {
        let Some(parsed) = parse(packet) else {
            return Ok(());
        };
        let mut value = now().to_be_bytes().to_vec();
        value.extend_from_slice(packet);
        self.vault.put(CARRY, &parsed.id, &value)?;

        let mut held = self.stored()?;
        held.sort_by_key(|(_, at, _)| *at);
        let mut bytes: usize = held.iter().map(|(_, _, packet)| packet.len()).sum();
        let mut count = held.len();
        let cutoff = now().saturating_sub(KEEP_SECS);
        for (id, at, packet) in held {
            if at >= cutoff && count <= MAX_CARRIED && bytes <= MAX_CARRIED_BYTES {
                break;
            }
            self.vault.delete(CARRY, &id)?;
            count -= 1;
            bytes -= packet.len();
        }
        Ok(())
    }

    fn stored(&self) -> Result<Vec<(Id, u64, Vec<u8>)>> {
        self.vault
            .list(CARRY)?
            .into_iter()
            .map(|(id, value)| {
                let (id, at) = (
                    id.as_slice().try_into().ok(),
                    value.get(..8).and_then(|at| at.try_into().ok()),
                );
                match (id, at) {
                    (Some(id), Some(at)) => Ok((id, u64::from_be_bytes(at), value[8..].to_vec())),
                    _ => Err(CoreError::Corrupt("a carried packet is misfiled".into())),
                }
            })
            .collect()
    }

    /// Everything being carried that `peer` has not been handed yet, oldest
    /// first. They are counted as handed over from now on.
    pub fn for_peer(&mut self, peer: &str) -> Result<Vec<Vec<u8>>> {
        let cutoff = now().saturating_sub(KEEP_SECS);
        let mut held = self.stored()?;
        held.sort_by_key(|(_, at, _)| *at);
        let mut out = Vec::new();
        for (id, at, packet) in held {
            if at < cutoff {
                self.vault.delete(CARRY, &id)?;
                continue;
            }
            if self
                .live
                .given
                .entry(id)
                .or_default()
                .insert(peer.to_string())
            {
                out.push(packet);
            }
        }
        Ok(out)
    }

    /// Notes that `peer` has been handed a packet, so it is not handed
    /// over again.
    pub fn gave(&mut self, packet: &[u8], peer: &str) {
        if let Some(parsed) = parse(packet) {
            self.live
                .given
                .entry(parsed.id)
                .or_default()
                .insert(peer.to_string());
        }
    }

    #[cfg(test)]
    pub fn carried(&self) -> Result<usize> {
        Ok(self.stored()?.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn relay<'a>(vault: &'a Vault, live: &'a mut Live, me: &[u8]) -> Relay<'a> {
        Relay {
            vault,
            live,
            my_tag: tag_of(me),
        }
    }

    fn vault() -> (tempfile::TempDir, Vault) {
        let dir = tempfile::tempdir().unwrap();
        let vault = Vault::open(dir.path(), &[7u8; 32]).unwrap();
        (dir, vault)
    }

    #[test]
    fn a_packet_for_this_device_is_opened_and_goes_no_further() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut me = relay(&vault, &mut live, b"mira");
        let packet = wrap(b"mira", b"sealed envelope");
        match me.accept("noor", &packet).unwrap() {
            Verdict::Mine { envelope, hops } => {
                assert_eq!(envelope, b"sealed envelope");
                assert_eq!(hops, 1);
            }
            _ => panic!("it was for this device"),
        }
        // Again, so that a lost answer can be sent again.
        assert!(matches!(
            me.accept("noor", &packet).unwrap(),
            Verdict::Mine { .. }
        ));
        assert_eq!(
            me.carried().unwrap(),
            0,
            "nothing of one's own is carried on"
        );
    }

    #[test]
    fn a_relay_never_writes_someone_elses_packet_to_disk() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut noor = relay(&vault, &mut live, b"noor");
        let packet = wrap(b"mira", b"sealed envelope");
        assert!(matches!(
            noor.accept("asha", &packet).unwrap(),
            Verdict::Onward(_)
        ));
        // Passed to whoever is in range now, from memory, then gone.
        assert_eq!(noor.carried().unwrap(), 0);
        assert!(vault.list(CARRY).unwrap().is_empty());
        assert!(noor.for_peer("kabir").unwrap().is_empty());
    }

    #[test]
    fn the_sender_keeps_its_own_packet_to_try_again() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut asha = relay(&vault, &mut live, b"asha");
        let packet = asha.send(b"mira", b"sealed envelope").unwrap();
        assert_eq!(asha.carried().unwrap(), 1);
        // A path opens: whoever is met is handed it.
        assert_eq!(asha.for_peer("noor").unwrap(), vec![packet]);
    }

    #[test]
    fn a_packet_for_someone_else_is_passed_on_once_with_one_hop_fewer() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut noor = relay(&vault, &mut live, b"noor");
        let packet = wrap(b"mira", b"sealed envelope");
        let Verdict::Onward(onward) = noor.accept("asha", &packet).unwrap() else {
            panic!("it should be passed on")
        };
        assert_eq!((onward[0], onward[1]), (HOPS - 1, 1));
        assert_eq!(&onward[2..], &packet[2..], "nothing else about it changes");
        // Coming round again, from anyone, it is dropped.
        assert!(matches!(
            noor.accept("dev", &packet).unwrap(),
            Verdict::Drop
        ));
        assert!(matches!(
            noor.accept("asha", &onward).unwrap(),
            Verdict::Drop
        ));
    }

    #[test]
    fn a_flood_from_one_device_is_not_passed_on_past_its_allowance() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut noor = relay(&vault, &mut live, b"noor");
        // Each packet different, as a packet's number comes from what it holds.
        let mut made = 0u32;
        let mut onward = |noor: &mut Relay<'_>, from: &str| {
            made += 1;
            let packet = wrap(b"mira", format!("sealed envelope {made}").as_bytes());
            matches!(noor.accept(from, &packet).unwrap(), Verdict::Onward(_))
        };
        // Everything a sender carries, handed over at once, goes on.
        let burst = ALLOW_PACKETS as usize;
        assert!((0..burst).all(|_| onward(&mut noor, "flooder")));
        // Then next to none from that device: only what a moment refills.
        assert!((0..50).filter(|_| onward(&mut noor, "flooder")).count() <= 2);
        // Someone else's packets still go on.
        assert!(onward(&mut noor, "asha"));
        // And anything for this device itself is always taken in.
        let mine = wrap(b"noor", b"for me");
        assert!(matches!(
            noor.accept("flooder", &mine).unwrap(),
            Verdict::Mine { .. }
        ));
    }

    #[test]
    fn an_allowance_fills_again_with_time_and_counts_bytes_too() {
        let mut allowance = Allowance::full(0);
        let mut taken = 0;
        while allowance.take(10, 0) {
            taken += 1;
        }
        assert_eq!(taken, ALLOW_PACKETS as usize);
        // Two seconds on, ten more.
        assert_eq!((0..20).filter(|_| allowance.take(10, 2_000)).count(), 10);
        // Bytes run out before packets do for big packets.
        let mut big = Allowance::full(0);
        let size = MAX_PACKET;
        let fit = (ALLOW_BYTES / size as f64) as usize;
        assert_eq!((0..fit + 10).filter(|_| big.take(size, 0)).count(), fit);
    }

    #[test]
    fn allowances_are_kept_for_a_limited_number_of_devices() {
        let mut live = Live::default();
        for n in 0..ALLOWANCES + 40 {
            assert!(live.allow(&format!("device {n}"), 100, n as u64));
        }
        assert_eq!(live.allowance.len(), ALLOWANCES);
        // The ones heard from longest ago went first.
        assert!(!live.allowance.contains_key("device 0"));
        assert!(live.allowance.contains_key(&format!("device {}", ALLOWANCES + 39)));
    }

    #[test]
    fn a_packet_that_has_used_its_hops_is_not_passed_on() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut noor = relay(&vault, &mut live, b"noor");
        let mut packet = wrap(b"mira", b"sealed envelope");
        (packet[0], packet[1]) = (0, HOPS);
        assert!(matches!(
            noor.accept("asha", &packet).unwrap(),
            Verdict::Drop
        ));
        assert_eq!(noor.carried().unwrap(), 0);
    }

    #[test]
    fn a_packet_claiming_more_hops_than_allowed_is_refused() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut noor = relay(&vault, &mut live, b"noor");
        for (left, so_far) in [(HOPS + 1, 0), (255, 0), (HOPS, 1), (1, HOPS)] {
            let mut packet = wrap(b"mira", b"sealed envelope");
            (packet[0], packet[1]) = (left, so_far);
            assert!(
                matches!(noor.accept("asha", &packet).unwrap(), Verdict::Drop),
                "{left} left, {so_far} so far"
            );
        }
    }

    #[test]
    fn things_that_are_not_packets_are_dropped() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut noor = relay(&vault, &mut live, b"noor");
        for junk in [
            vec![],
            vec![4],
            vec![4u8; HEADER],
            vec![4u8; MAX_PACKET + 1],
        ] {
            assert!(matches!(noor.accept("asha", &junk).unwrap(), Verdict::Drop));
        }
        assert_eq!(noor.carried().unwrap(), 0);
    }

    #[test]
    fn the_senders_own_packet_is_handed_to_each_device_once() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut asha = relay(&vault, &mut live, b"asha");
        asha.send(b"mira", b"one").unwrap();
        asha.send(b"mira", b"two").unwrap();

        assert_eq!(asha.for_peer("noor").unwrap().len(), 2);
        assert!(
            asha.for_peer("noor").unwrap().is_empty(),
            "handed over once"
        );
        assert_eq!(asha.for_peer("mira").unwrap().len(), 2);
    }

    #[test]
    fn the_senders_own_packets_survive_a_restart() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        relay(&vault, &mut live, b"asha")
            .send(b"mira", b"kept")
            .unwrap();
        // After a restart nothing is remembered but what is on disk.
        let mut live = Live::default();
        let mut asha = relay(&vault, &mut live, b"asha");
        assert_eq!(asha.for_peer("noor").unwrap().len(), 1);
    }

    #[test]
    fn what_the_sender_keeps_waiting_is_capped() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut asha = relay(&vault, &mut live, b"asha");
        for number in 0..MAX_CARRIED + 20 {
            asha.send(b"mira", format!("packet {number}").as_bytes())
                .unwrap();
        }
        assert_eq!(asha.carried().unwrap(), MAX_CARRIED);
    }

    #[test]
    fn a_tag_depends_on_the_key_and_nothing_else() {
        assert_eq!(tag_of(b"mira"), tag_of(b"mira"));
        assert_ne!(tag_of(b"mira"), tag_of(b"asha"));
    }

    #[test]
    fn the_same_envelope_is_the_same_packet() {
        assert_eq!(wrap(b"mira", b"one"), wrap(b"mira", b"one"));
        assert_ne!(wrap(b"mira", b"one")[2..18], wrap(b"mira", b"two")[2..18]);
    }

    // Maps

    /// A made-up signing key, hex.
    fn key(n: u8) -> String {
        hexcode::encode(&[n; KEY_LEN])
    }

    fn by_bluetooth(n: u8, near: u8) -> Neighbour {
        Neighbour {
            key: key(n),
            bluetooth: true,
            wifi: false,
            near,
        }
    }

    /// What `who` sends `to`, read back as `to` would.
    fn map_from(live: &mut Live, who: u8, to: u8, around: &[Neighbour], now: u64) -> Vec<MapLink> {
        let sent = live.share(&key(who), around, false, true, now);
        let (_, packet) = sent
            .into_iter()
            .find(|(peer, _)| *peer == key(to))
            .expect("a map was due");
        read_map(&key(who), &packet).expect("a map reads back").2
    }

    #[test]
    fn a_device_is_named_only_once_it_has_sent_a_map_of_its_own() {
        let mut live = Live::default();
        let around = [by_bluetooth(2, 1), by_bluetooth(3, 2)];
        // Nobody has said anything yet: nobody is named.
        assert!(map_from(&mut live, 1, 3, &around, 0).is_empty());

        // Device 2 sends its map. Now device 3 is told of it.
        let two = write_map(0, &key(2), &[]);
        assert!(live.take_map(&key(2), &two, 1));
        let told = map_from(&mut live, 1, 3, &around, 2);
        assert_eq!(
            told,
            vec![MapLink {
                from: key(1),
                to: key(2),
                radios: BLUETOOTH,
                near: 1,
                told: 1,
            }]
        );
    }

    #[test]
    fn someone_invisible_is_never_named_and_names_nobody() {
        let mut live = Live::default();
        let hidden = write_map(MAP_HIDDEN, &key(2), &[]);
        assert_eq!(hidden.len(), 4, "it says nothing but that");
        live.take_map(&key(2), &hidden, 0);
        let around = [by_bluetooth(2, 1), by_bluetooth(3, 1)];
        assert!(map_from(&mut live, 1, 3, &around, 1).is_empty());
        let view = live.view(&[key(2)], 1);
        assert_eq!(view.hidden, vec![key(2)]);

        // And a hidden device's own map holds no keys at all.
        let mine = live.share(&key(1), &around, true, true, 2);
        for (_, packet) in mine {
            assert_eq!(read_map(&key(1), &packet), Some((true, true, vec![])));
        }
        // A map that claims to be hidden but names people is refused.
        let mut liar = write_map(0, &key(2), &[MapLink {
            from: key(2),
            to: key(4),
            radios: BLUETOOTH,
            near: 0,
            told: 0,
        }]);
        liar[1] = MAP_HIDDEN;
        assert!(read_map(&key(2), &liar).is_none());
    }

    #[test]
    fn a_device_that_passes_nothing_on_names_nobody_and_is_marked_as_an_end() {
        let mut live = Live::default();
        for (_, packet) in live.share(&key(1), &[by_bluetooth(2, 0)], false, false, 0) {
            assert_eq!(read_map(&key(1), &packet), Some((false, false, vec![])));
        }
        let mut live = Live::default();
        live.take_map(&key(2), &write_map(MAP_NO_RELAY, &key(2), &[]), 0);
        let told = map_from(&mut live, 1, 3, &[by_bluetooth(2, 0), by_bluetooth(3, 0)], 1);
        assert_eq!(told[0].radios, BLUETOOTH | ENDS);
        assert_eq!(live.view(&[key(2)], 1).ends, vec![key(2)]);
    }

    #[test]
    fn word_travels_no_further_than_a_packet_could() {
        let mut live = Live::default();
        // Device 2 tells of a link it heard of from far off.
        let far = |told: u8| MapLink {
            from: key(5),
            to: key(6),
            radios: WIFI,
            near: 3,
            told,
        };
        live.take_map(&key(2), &write_map(0, &key(2), &[far(2)]), 0);
        let around = [by_bluetooth(2, 0), by_bluetooth(3, 0)];
        let passed: Vec<MapLink> = map_from(&mut live, 1, 3, &around, 1)
            .into_iter()
            .filter(|link| link.from == key(5))
            .collect();
        assert_eq!(passed.len(), 1);
        assert_eq!(passed[0].told, 4, "two before, then 2, then 1");

        // One step further would reach beyond what a packet can, so it is
        // not passed on, and a map claiming it is refused.
        let mut live = Live::default();
        live.take_map(&key(2), &write_map(0, &key(2), &[far(3)]), 0);
        assert_eq!(live.view(&[key(2)], 1).links[0].told, 4);
        assert!(map_from(&mut live, 1, 3, &around, 1)
            .iter()
            .all(|link| link.from != key(5)));
        assert!(read_map(&key(2), &write_map(0, &key(2), &[far(4)])).is_none());
    }

    #[test]
    fn what_a_device_told_is_never_told_back_to_it() {
        let mut live = Live::default();
        let link = MapLink {
            from: key(2),
            to: key(4),
            radios: BLUETOOTH,
            near: 2,
            told: 0,
        };
        live.take_map(&key(2), &write_map(0, &key(2), &[link]), 0);
        live.take_map(&key(3), &write_map(0, &key(3), &[]), 0);
        let around = [by_bluetooth(2, 0), by_bluetooth(3, 0)];
        let sent = live.share(&key(1), &around, false, true, 1);
        let to = |n: u8| {
            let (_, packet) = sent.iter().find(|(peer, _)| *peer == key(n)).unwrap();
            read_map(&key(1), packet).unwrap().2
        };
        // Device 3 hears of 2's link; device 2 does not hear it back.
        assert!(to(3).iter().any(|l| l.from == key(2) && l.to == key(4)));
        assert!(to(2).iter().all(|l| l.from != key(2) && l.to != key(2)));
    }

    #[test]
    fn a_map_is_sent_again_only_when_it_changes_or_is_due() {
        let mut live = Live::default();
        let around = [by_bluetooth(2, 1)];
        assert_eq!(live.share(&key(1), &around, false, true, 0).len(), 1);
        assert!(live.share(&key(1), &around, false, true, 1_000).is_empty());
        // Device 2 is heard further off now: that is news.
        let moved = [by_bluetooth(2, 3)];
        live.take_map(&key(2), &write_map(0, &key(2), &[]), 1_000);
        live.take_map(&key(3), &write_map(0, &key(3), &[]), 1_000);
        let both = [moved[0].clone(), by_bluetooth(3, 1)];
        assert_eq!(live.share(&key(1), &both, false, true, 2_000).len(), 2);
        assert!(live.share(&key(1), &both, false, true, 3_000).is_empty());
        // Nothing new for a while: said again so it stays believed.
        assert_eq!(
            live.share(&key(1), &both, false, true, 2_000 + MAP_AGAIN_MS)
                .len(),
            2
        );
    }

    #[test]
    fn what_was_told_is_soon_forgotten_and_whoever_goes_at_once() {
        let mut live = Live::default();
        let link = MapLink {
            from: key(2),
            to: key(4),
            radios: BLUETOOTH,
            near: 0,
            told: 0,
        };
        assert!(live.take_map(&key(2), &write_map(0, &key(2), std::slice::from_ref(&link)), 0));
        // The same again is not news.
        assert!(!live.take_map(&key(2), &write_map(0, &key(2), &[link]), 10));
        assert_eq!(live.view(&[key(2)], 20).links.len(), 1);
        assert!(live.view(&[key(2)], 20 + MAP_FRESH_MS).links.is_empty());
        // Gone from range: forgotten, whatever the time.
        live.share(&key(1), &[], false, true, 30);
        assert!(live.view(&[key(2)], 30).links.is_empty());
    }

    #[test]
    fn a_map_is_never_taken_for_an_envelope_and_junk_is_dropped() {
        let (_dir, vault) = vault();
        let mut live = Live::default();
        let mut noor = relay(&vault, &mut live, b"noor");
        let map = write_map(0, &key(2), &[]);
        assert!(parse(&map).is_none(), "an old device drops it");
        assert!(matches!(noor.accept(&key(2), &map).unwrap(), Verdict::Mapped));
        assert!(matches!(noor.accept(&key(2), &map).unwrap(), Verdict::Drop));
        for junk in [
            vec![MAP],
            vec![MAP, 0, 1],
            vec![MAP, 0, 0, 1, 0, 0, 1, 0, 0],
            vec![MAP, 0, 0, 1, 0, 1, 1, 0, 0],
            vec![MAP, 0, 0, 0, 7],
        ] {
            assert!(read_map(&key(2), &junk).is_none(), "{junk:?}");
            assert!(matches!(noor.accept(&key(2), &junk).unwrap(), Verdict::Drop));
        }
        assert_eq!(noor.carried().unwrap(), 0, "a map is never kept");
        assert!(vault.list(CARRY).unwrap().is_empty());
    }

    #[test]
    fn a_crowd_fits_in_one_map_nearest_first() {
        let mut live = Live::default();
        let many: Vec<Neighbour> = (10..110).map(|n| by_bluetooth(n, 2)).collect();
        for n in &many {
            live.take_map(&n.key, &write_map(0, &n.key, &[]), 0);
        }
        let sent = live.share(&key(1), &many, false, true, 1);
        let (_, packet) = &sent[0];
        let (_, _, links) = read_map(&key(1), packet).unwrap();
        assert_eq!(links.len(), MAP_KEYS, "as many as there are keys for");
        assert!(packet.len() < 3 * 1024);
    }
}
