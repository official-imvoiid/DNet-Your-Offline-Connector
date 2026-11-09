# DNet architecture

DNet is an offline, end-to-end encrypted messenger for Android and Windows.
Nothing in it talks to a server. This file is the map: where each kind of
code lives, how the layers fit, and what each trusts.

## Folders

| Folder | Language | What it holds |
|---|---|---|
| `app/lib/` | Dart (Flutter) | Screens, widgets, the app state, the radio glue, calls |
| `app/android/.../kotlin/` | Kotlin | Bluetooth LE, Wi-Fi Direct, USB serial and BLE for LoRa radios, camera, NFC, screen capture, the Keystore-wrapped master key |
| `core/` | Rust | Identity, sealing and opening messages, the encrypted vault, chats, spaces, calls, files, mesh relay. Loaded by the app over FFI as `dnet_core` |
| `radio_windows/` | Rust | Windows-only: Bluetooth LE, Wi-Fi Direct, webcam, microphone, speaker, screen capture. Loaded as `dnet_radio` |
| `design/` | HTML, PNG | The design kit the screens are checked against |
| `docs/` | Markdown | `RADIO.md` (the LoRa transport) and `HARDWARE.md` (what to buy) |
| `tool/` | Python | Generators for icons, emoji data and the bundled stickers |

## Layers, top to bottom

```
Screens (app/lib/screens, widgets)
   │  read and act on
AppState (app/lib/data/app_state.dart)
   │  one source per kind of thing
Store · Directory · SpaceBook · calls        (app/lib/data, app/lib/calls)
   │  JSON requests over FFI
CoreBridge (app/lib/core/core_bridge.dart)  ──►  Rust core (core/src/api.rs)
   │                                               identity, envelopes, vault,
LinkPump (app/lib/radio/link_pump.dart)            chat, spaces, files, relay
   │  frames, as hex
Radio (app/lib/radio/radio.dart)
   ├─ ChannelRadio   Bluetooth LE on Android (Kotlin BleRadio.kt)
   ├─ PolledRadio    Bluetooth LE on Windows (Rust radio_windows/src/ble.rs)
   ├─ LanRadio       the same Wi-Fi network, or a Wi-Fi Direct group
   ├─ LoRaRadio      an external LoRa device (app/lib/radio/lora/)
   └─ MultiRadio     runs the above side by side
```

### The core owns every secret

All cryptography is in `core/`, using reviewed crates: Ed25519 signatures
(`ed25519-dalek`), X-Wing HPKE (`hpke`: X25519 + ML-KEM-768, HKDF-SHA256,
AES-256-GCM) for envelopes, AES-256-GCM for the vault and call media,
Argon2 for the app-lock passcode. The Dart side never sees a private key,
never encrypts and never decrypts. It moves opaque hex frames.

The core is one function, `dnet_call(json) -> json`. Every request names an
`op`. Errors come back as `{"err": {"code", "message"}}` and surface in
Dart as `CoreException`. A panic in the core aborts the process
(`panic = "abort"`) rather than unwinding into Dart.

### Identity

An identity is an Ed25519 signing key (who you are) plus an X-Wing
encryption key, bound together by a signature (`core/src/identity.rs`). A
proof-of-work stamp (`proof.rs`, 20 leading zero bits in release builds,
8 in debug) is attached to a new identity so making accounts in bulk costs
CPU time. The secret half lives only in the vault.

### Envelopes

Every message between two people is an envelope (`core/src/envelope.rs`):
HPKE-sealed to the recipient's identity, with the sender's signing key and
signature *inside* the ciphertext. Carriers in between learn neither the
content nor the sender. The signature covers the recipient's identity
hash, so a message signed for Mira cannot be re-sealed to Noor as if it
had been written to her. There is no forward secrecy (no ratchet); this is
a known limit and is written in `SECURITY.md`.

### Links and frames

A radio only moves frames; it knows nobody. The core's link protocol
(`core/src/link.rs`) runs on every connection: each side sends a hello
(nonce + public identity + optional name), then signs the other's nonce.
Only after that proof are envelopes accepted from, or sent to, that link.
Messages are cut into frames that fit the radio (`max_frame`: ~180 bytes on
Bluetooth, 16 KB on Wi-Fi, 160 bytes on LoRa) on two lanes, chat and bulk,
so a chat never waits behind a file piece.

`LinkPump` carries frames between a `Radio` and the core, keeps one
priority queue per link (call media, chat, small-file pieces, big-file
pieces) and tells the core when links open and close. Chat goes out on
every link that reaches a person; file pieces go once, on the fastest.

### Relay (mesh)

When nobody in range is the recipient, a kept envelope is wrapped into a
packet (`core/src/relay.rs`: hops left, hops so far, 16-byte id, 8-byte
recipient tag, envelope) and handed to every device met, up to 4 hops.
Carriers keep at most 500 packets / 8 MB for 72 hours, never write what
they carry for others to disk, and drop anything seen before in the same
"round". Devices also exchange small signed-free maps of who hears whom
so the Nearby screen can draw the mesh. This is not an anonymity network.

### Storage

The vault (`core/src/vault.rs`) is one `redb` file. Every record is
AES-256-GCM sealed under a 32-byte master key with the record's group and
id as associated data. On Android the master key is wrapped by an
AndroidKeystore AES key (`MasterKey.kt`); on Windows by DPAPI
(`keyguard.rs`). The app-lock passcode is a separate Argon2 hash in the
vault; ten wrong tries wipe everything.

### Spaces

A space is a group with an owner, admins, roles, channels and voice
rooms (`core/src/space.rs`). Every item is sealed with the space key and
signed by its writer. The owner's manifest (name, channels, rules, roles,
members) is signed by the owner; removing a member from a private space
rotates the key.

### Files

A file is split into 1 KB to 1 MB chunks under a hash tree
(`core/src/file.rs`). Each piece carries its Merkle proof and is checked
before it is written. Names are reduced to their last path segment
(`safe_name`) so a sender cannot write outside the received-files folder.
A transfer resumes on any link.

### Calls

Call signalling goes in envelopes; audio and video frames (`d7` prefix)
go only over fast links, sealed by the core with a per-call key
(`core/src/call.rs`) and skip the link queue. Audio is IMA ADPCM
(`codec.rs`), 16 kHz mono.

## The LoRa radio transport (`app/lib/radio/lora/`)

A second, slower, much longer-range path for chat, through an external
LoRa device. See `docs/RADIO.md` for the user-facing picture.

```
LoRaRadio (a Radio for LinkPump; one core link per DNet peer heard)
   │  core frames (≤160 bytes), hex
RadioProtocol (radio_protocol.dart)
   │  fragments, reassembly, ACK/retry with backoff, dedupe,
   │  compression flag, replay window, airtime budget / duty cycle
RadioTransport (radio_transport.dart) ── one interface for every driver
   ├─ MeshtasticDriver   official protobuf API over a ByteLink:
   │     TcpByteLink (Wi-Fi, numeric local address only), DeviceFileSerialLink
   │     (USB on Windows/Linux/macOS), ChannelByteLink (USB and BLE on Android)
   ├─ SerialLoraDriver   bare SX126x/SX127x modules behind DNet's own
   │     serial framing (docs/RADIO.md describes the wire format)
   └─ MockRadioDriver    a shared "air" with loss, reorder, duplicates,
         delay and RSSI, for demos
```

The radio's own encryption (Meshtastic channel PSK) is treated as
nothing: everything that crosses it is still a core envelope, sealed and
signed end to end, and every peer still proves its identity with the link
handshake. File pieces never go over LoRa; the pump drops bulk-class
deliveries on radio links.
