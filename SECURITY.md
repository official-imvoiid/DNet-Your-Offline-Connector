# Security

DNet has had one internal security review (October 2026, two passes:
cryptography and storage; transports and sync). Its findings and fixes are
listed below. It has **not** had an independent review, and none of its
radio code has been run between real devices. Until both have happened,
do not rely on it to protect anyone.

## Reporting a problem

Please **don't open a public issue** for a security problem. Report it
privately through GitHub instead:

1. Open the repository's **Security** tab.
2. Click **Report a vulnerability**.

Include what you found, how to reproduce it, and which version or commit
you tested.

## What's in scope

- the Rust core (`core/`): identity, sealing and opening messages, the
  encrypted vault, the app lock, the proof-of-work stamp, verification,
  file pieces, mesh routing
- the link protocol between devices, over Bluetooth, Wi-Fi Direct, local
  Wi-Fi and LoRa radio
- the LoRa protocol layer and drivers (`app/lib/radio/lora/`)
- the Windows radio library (`radio_windows/`) and the Android radio,
  USB, camera, NFC and screen-capture code
- anything that leaks data, such as names, keys, messages or locations, to
  people who shouldn't see it

## The security model, in short

- **Identity** is an Ed25519 signing key plus an X-Wing (X25519 +
  ML-KEM-768) encryption key, bound by a signature, made on the device and
  never leaving it. A proof-of-work stamp makes bulk identities costly.
- **Every message** is an HPKE envelope sealed to the recipient, with the
  sender's signature inside, bound to the recipient's identity. A device
  passing it on learns neither content nor sender.
- **Every link** (Bluetooth, Wi-Fi, LoRa) starts with each side signing
  the other's fresh nonce. Nothing is handed to a device that has not
  proved it holds the identity it showed. The radio's own encryption
  (Wi-Fi Direct's password, Meshtastic's channel key) is treated as
  nothing.
- **Storage** is one `redb` file with every record AES-256-GCM sealed under
  a master key kept by the Android Keystore or Windows DPAPI. The app lock
  is an Argon2 hash; ten wrong tries wipe the device.
- **Replay**: links drop a copy of an envelope seen in the last two
  minutes; the chat layer drops a message id it already holds; call
  media frames and LoRa frames carry sequence numbers and old ones are
  dropped.
- **Parsing**: everything that arrives over a radio is bounded and
  checked before memory is set aside for it; pictures are sized from
  their headers before any decoder runs; the LoRa parsers are fuzzed.

## Known limits

- **No forward secrecy.** A recipient's encryption key is long-lived.
  Someone who records envelopes and later takes the key can open them. A
  ratchet is not built.
- **The master key crosses the FFI as text.** The native buffer is zeroed
  after use, but a Dart `String` cannot be, so the key may linger in the
  Dart heap until collected.
- **Windows DPAPI is per user.** Any program running as the same Windows
  user can unwrap the vault's master key.
- **Mesh maps are claims.** A proved device can lie about who it hears.
  Maps only draw the Nearby screen; they never decide trust.
- **A LoRa link is loud.** Anyone with a radio on the band sees that two
  DNet devices are talking, their radio node numbers, when, and how much.
- **Debug builds** accept weaker proof-of-work stamps (8 bits, not 20).

## Findings of the October 2026 review

| # | Severity | Where | What | Status |
|---|---|---|---|---|
| A1 | Medium | `app/lib/data/*` picture paths | A contact's small PNG/GIF/WebP could declare a 30,000 × 30,000 size and have the app allocate gigabytes on decode (crash). | Fixed: headers are read first (`image_bounds.dart`); limits 8192 px a side, 20 Mpx. Regression tests. |
| A2 | Low | `app/lib/calls/call_engine.dart` | Call media frames carried a sequence number the app ignored, so an on-path LAN attacker could replay or reorder captured audio inside a live call. | Fixed: per call/sender/kind monotonic sequence; replays dropped. Regression test. |
| A3 | Info | `core/src/envelope.rs` | No forward secrecy. | Documented; needs a ratchet. |
| A4 | Info | `core/src/keyguard.rs` | DPAPI is user-scoped on Windows. | Documented. |
| A5 | Low | `app/lib/core/core_bridge.dart` | Master key as a Dart `String`. | Documented; native buffer is zeroed. |
| A6 | Info | `core/src/proof.rs` | Debug builds accept weak stamps. | By design; documented. |
| A7 | Info | `core/src/relay.rs` | Mesh maps are unauthenticated claims from proved peers. | Documented; maps never decide trust. |
| A8 | Low | `app/android/app/build.gradle.kts` | Release builds were silently signed with the debug key. | Fixed: `key.properties` is used when present; a loud warning otherwise. |
| B1 | Medium | `app/lib/radio/lan_radio.dart` | Anyone on the LAN could send "I am here" beacons with made-up ids from spoofed sources and have the device open a TCP connection per beacon to any host and keep an unbounded list of addresses to greet (connection flood, reflection, memory). | Fixed: at most 32 greeted addresses, 8 connects at once, one per source address, 64 open links. Regression tests. |
| B2 | Medium | `core/Cargo.lock` | `ctutils` 0.4.3 had non-constant-time comparisons (RUSTSEC-2026-0385). | Fixed: updated to 0.4.7; `cargo audit` is clean and runs in CI. |
| B3 | Low | `app/lib/radio/lan_radio.dart` | Accepted TCP connections were unbounded. | Fixed with B1. |
| B4 | Info | LoRa transport | Meshtastic channel encryption must not be trusted. | Designed in: every frame on the air is a core envelope or a signed handshake. |
| B5 | Info | LoRa parsers | New untrusted-input parsers. | Written to never throw; fuzzed in `radio_protocol_test.dart`, `meshtastic_proto_test.dart`, `serial_lora_driver_test.dart`; reassembly bounded. |

## Findings of the November 2026 radio review

Bluetooth (Android and Windows), local Wi-Fi, Wi-Fi Direct and LoRa, read
as someone in radio range with their own device would attack them.

| # | Severity | Where | What | Status |
|---|---|---|---|---|
| C1 | Medium | `core/src/relay.rs` | Any proved peer could hand over an endless stream of new packets, and every device in range passed each one on to everyone in range of them (mesh flood). | Fixed: a per-device allowance for passing on (a burst of 600 packets / 32 MB, then 5 packets and 2 MB a second); packets for this device are never limited. Regression tests. |
| C2 | Medium | `app/lib/data/safe_name.dart` | A stranger's name could carry characters that show as nothing or turn the text around (`Mi\u200Bra`, `\u202EMira`), look exactly like a contact's, and slip past the `Mira·4F2A` same-name tag. | Fixed: such characters are taken out of every name others chose before it is shown or compared; the joiners scripts and emoji need are kept. Regression tests. Look-alike letters from other alphabets are not caught; verifying is the answer. |
| C3 | Low | `app/lib/radio/lan_radio.dart` | A TCP connection that never said hello was never closed, and such connections count towards the 64 allowed, so 64 silent connections from the same network blocked every new local link. | Fixed: 10 s to say hello. Regression test. |
| C4 | Medium | `app/lib/radio/lora/lora_radio.dart` | Beacons from made-up node numbers each opened a LoRa link, and each link spends airtime on the handshake: a cheap way to use up the band, and on a duty-cycle band the legal budget, on nobody. The list of nodes left alone grew without limit. | Fixed: at most 32 links; 8 new ones at once, then one every 10 s; 1024 nodes left alone at most. Regression test. |
| C5 | Low | `app/lib/radio/lora/radio_protocol.dart` | A compressed message was opened whole before its size was checked: 4 KB on the air could make the app build about 4 MB, again and again. | Fixed: opened in pieces and stopped at the limit. Regression test. |
| C6 | Low | `radio_windows/src/direct.rs` | A Windows Wi-Fi Direct group let in every device that asked to pair, which does not take the group's password. | Fixed: one device per group (a group is made for one person). Whoever comes in must still prove who they are. **To check on devices:** whether a phone joining by name and password comes this way at all. |
| C7 | Info | `core/src/link.rs` | The link proof is not bound to the radio connection, so a device in the middle can pass the handshake along and then drop what it carries. It can read and change nothing. | Documented. Binding needs a key agreement in the hello. |
| C8 | Info | `core/src/link.rs` | Making an identity for a link costs nothing (the proof-of-work stamp is asked only of chat requests), so C1 and C4 limits are per device, and many made-up devices get many allowances. | Documented. Users can turn passing-on off in Privacy. |
| C9 | Low | `BleRadio.kt`, `ble.rs` | The list of Bluetooth addresses to leave alone a while is never pruned; addresses that change can grow it slowly. Four outgoing connection slots can be held by fake devices that never finish connecting (others can still connect in). | Open; low impact. |
| C10 | Info | `radio_windows/src/ble.rs` | Windows' own advertising for a GATT service may add the PC's name to its scan response; Android leaves the phone's name out on purpose. | **To check on devices** with a Bluetooth scanner; rename the PC if it shows. |

## What the core uses

All cryptography is in the Rust core, using reviewed RustCrypto and dalek
libraries:
- Ed25519 for signatures
- X-Wing HPKE (ML-KEM plus X25519) to seal messages
- AES-GCM and HKDF
- Argon2 for the app lock passcode
- `redb` for storage that's encrypted at rest

No primitive is written by hand. `cargo audit` runs in CI on both crates.
