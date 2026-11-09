# Changelog

All notable changes to DNet. The format follows Keep a Changelog; versions
follow the app's `pubspec.yaml`.

## 0.3.0 — 2026-11-08

### Added
- **Keyboard shortcuts.** Ctrl+K finds a chat, Ctrl+N starts a new chat,
  Ctrl+1 to Ctrl+4 switch tabs, Ctrl+F searches the open channel, and Esc
  closes a sheet, a search box or the open screen. In the message box,
  Enter sends and Shift+Enter starts a new line. The empty pane on a PC
  lists them.
- **Members beside a channel** on a big window (about 1400 px and up), as a
  third pane. The members button shows and hides them.
- **Back to the newest message**: a round button appears once you scroll
  up in a chat or channel, with a count of what came in since. A pill at
  the top of a channel jumps up to where the new messages start.
- **Right click** on a message opens what can be done with it, as a long
  press does. With a mouse over a channel message, it lights up and a
  "more" button appears; in a chat the button sits beside the bubble.
- Tips on icon buttons when the mouse rests on them, a hover light and a
  click cursor on everything pressable, and the list pane's edge can be
  dragged to make it wider or narrower (a double click puts it back).
- **Terms of Use and Disclaimer**, which must be accepted before the app
  opens: read to the end, tick "I have read and agree", then Accept.
  Nothing (store, radios, Welcome) is opened before that. Decline keeps
  the app closed and offers to quit. The accepted version and date are
  kept in `terms.json` beside the other settings; raising `termsVersion`
  asks everyone again. On a PC: a side panel with a short summary and the
  controls, the full text, and clickable contents; keyboard scrolling with
  the arrows, Page Up/Down, Home and End. Same text in `TERMS.md`, kept in
  step by a test.
- **About page** in place of the About dialog: logo, version (tap to copy
  it for a bug report), what DNet is for and aims to do, how it works,
  where it honestly stands, the GitHub source code and Issues links
  (through the link check), the Terms of Use, the MIT License and the
  open-source licences, fonts included. Two columns on a wide window.
- **Long-range radio setup in three steps**: device, band (with the legal
  warning, and a search box over the bands), then "Say hello on the air"
  to test the link, each ticked when done. The Link card adds signal bars,
  the board's name, when a DNet device was last heard, the timed round
  trip, an airtime meter against the band's limit, and the radio's own
  words when it holds something back. Steps and link sit side by side on
  a wide window. Serial ports on Windows say what is behind them (the
  board's own USB, or a CP210x, CH340 or FTDI bridge chip).
- More LoRa bands, matching the Meshtastic firmware: Brazil, the
  Philippines, Nepal, Kazakhstan, Australia/NZ 433, New Zealand 865,
  Malaysia 433, Ukraine 433 and 2.4 GHz boards. In India the screen warns
  when the radio's preset is wider than the 200 kHz the rules allow.

### Changed
- **The start page on a PC** fills the window in two panes: DNet, what it
  does and a mesh drawing that draws itself in on the left, making the
  identity on the right. It rises into view as it opens, and Enter in the
  name box gets started once the check is done. Phones keep the designed
  single column. The short "privacy and terms" sheet on Welcome is gone:
  the full terms now come first.
- The version comes from one place, `lib/version.dart`, which a test holds
  to the pubspec. About used to say 0.1.0.
- The fonts' licence files now ship inside the app.
- **The app fills the window on a PC.** What is open beside the list now
  uses the full width, with no empty bands at the sides, and a window
  too narrow for two panes is filled edge to edge too. Chat bubbles grow
  with the window (up to twice their phone width) and a voice room puts
  more people in a row.
- Tabs fade in when switched, empty panes rise into view, buttons give a
  little when pressed, and Android gives its touch feedback and a light
  tick on tab and switch changes.

- **LoRa sends fuller packets and waits as long as the radio needs.**
  Frames fill a Meshtastic packet (201 bytes instead of 160), so a
  message takes fewer packets and fewer ACKs. Retry waits come from the
  preset's real airtime and then from measured round trips, instead of a
  fixed 6 s that could resend a frame on a slow preset before it had
  finished sending. ACKs go before chat and "DNet is here" goes last in
  the radio's queue, and the regular "DNet is here" stands aside once
  half the band's hourly airtime is spent.

### Fixed (security; see SECURITY.md, C1–C10)
- **Mesh flood (C1):** one device could have every device in range pass
  on an endless stream of packets. Each device now has an allowance for
  what it hands over to be passed on.
- **Look-alike names (C2):** characters that show as nothing or turn text
  around are taken out of names others chose, so "Mi\u200Bra" can no
  longer pass for a contact called Mira.
- **Local Wi-Fi (C3):** a connection that never said hello was never
  closed; 64 of them blocked every new link. It now gets 10 s.
- **LoRa (C4, C5):** beacons from made-up node numbers could each open a
  link and spend airtime on it; links are now capped and taken on at a
  pace. A small compressed message can no longer open to megabytes.
- **Windows Wi-Fi Direct (C6):** a group let in every device that asked
  to pair; it now lets in one.

### Fixed
- **Space descriptions.** A private space (the default kind) had no
  description box, and dropped what was typed; and no space showed its
  description anywhere but its settings. Every kind now takes one (a
  private space's reaches its members only, as it is never announced),
  it shows under the space's name, and one over 140 characters says so
  instead of "Give the space a name first".
- The copyright line in `LICENSE` read "The DNet authorss".
- **LoRa on Windows**: a USB radio could not work, because the COM port
  was opened twice (Windows allows one user) and its reads waited for a
  full buffer. It is now opened once through the Windows API, 115200 8N1
  with DTR and RTS on, as the official Meshtastic clients do. Not yet
  tried with a real radio.
- **Meshtastic signal strength** was read with the wrong protobuf type
  (zigzag instead of `int32`), giving nonsense from real firmware.
- **The Meshtastic device rebooted every time the radio started**: the
  band was sent again even when unchanged. It is now sent only when it
  differs, and the settings are read again after the reboot.
- **Meshtastic flow control**: packets now wait for room in the device's
  send queue, as the official clients do, instead of being dropped by a
  full queue; serial and TCP links send the wake bytes first; a refusal
  from the device (duty cycle, full queue, too large) fails the frame at
  once with the device's own words.
- **A LoRa link could fail to come back after a radio went away and
  returned**, and the two devices then ignored each other for five
  minutes. The protocol kept retrying frames of the link that had
  closed; arriving after the radio was back, they landed in the middle
  of the new link's handshake, which the core sends once, so neither
  side ever proved itself. Closing a link now cancels its retries, and
  every frame carries a tag of the link it belongs to: a frame of a
  link that has ended is dropped, and one with a new tag closes the old
  link at once. A radio on DNet 0.2.0 no longer links with one on 0.3.0.
- The LoRa tests that waited a fixed time now wait for what they check,
  with a deadline, so a busy machine no longer fails them.

## 0.2.0 — 2026-10-29

### Added
- **Long-range radio (LoRa) transport.** Chat through an external LoRa
  device: Meshtastic boards over USB serial, Bluetooth LE (Android) and
  Wi-Fi/TCP (a numeric local address; no DNS), or a bare SX126x/SX127x module behind DNet's own serial
  framing. One `RadioTransport` interface, a protocol layer with
  fragmentation, ACK/retry with backoff, dedupe, replay windows, hop
  limits, compression and an airtime budget per region, a mock driver
  for tests, a setup screen (device picker, band with a legal-use
  warning, link status, signal, counts) and per-message
  sent/relayed/delivered/failed status. Files never go by radio.
  `docs/RADIO.md`, `docs/HARDWARE.md`.
- Chat list previews for videos (first frame and length, with loading,
  not-here and cannot-play states), places (an offline pin snippet, the
  numbers, accuracy) and polls (question, top choices, votes).
- A deleted last message previews as "deleted" instead of a blank line.
- A retry toast: every space-settings action that the core refuses now
  says so where the user is and offers to try again. Join and leave
  outside settings too.
- GitHub Actions CI: Rust tests, clippy and `cargo audit`; Flutter
  analyze, format and tests; Android and Windows release builds.
- `ARCHITECTURE.md`, a findings table in `SECURITY.md`, this changelog.

### Changed
- The file transfer screen says which link the person was really found
  over ("Found Mira over Wi-Fi" for two PCs on one network) and which is
  carrying the file now, driven by the link's transport.
- "Nearby, by radio" and "Radio, chat only" wording where a person is
  reached only by LoRa.
- The Network screen has a Long-range row that opens the radio setup
  screen, and a radio line on the status card, on builds that can take a
  radio.
- Release APKs are signed with `android/key.properties` when it exists,
  and the build warns loudly when they fall back to the debug key.
- The Windows app carries the Visual C++ runtime beside `dnet.exe`, so it
  starts on a PC that has never had the Visual C++ Redistributable. Its
  file details name "The DNet authors" and the MIT License.
- The app tests load the core library by platform name, so they run on
  Linux and macOS as well as Windows.

### Fixed (security; see SECURITY.md)
- A picture from a contact could claim an enormous size and crash the app
  on decode. Pictures are now sized from their headers before any
  decoder runs (A1).
- Call media frames could be replayed or reordered by someone on the
  path; sequence numbers are now enforced (A2).
- A device on the same Wi-Fi could flood the app with "I am here" beacons
  and have it open connections and keep addresses without limit; all
  three are now bounded (B1, B3).
- `ctutils` updated past RUSTSEC-2026-0385 (B2).

### Fixed (local Wi-Fi link)
- When two copies connected to each other at the same instant, each end
  could keep a different one of the two connections and then close the
  other's, dropping a good link for a few seconds. Both ends now keep the
  connection the lower-numbered copy made, and only when it comes from
  the address the link already has.
- On Windows, "I am here" reached only the first place of each beat.
  Windows sends one datagram at a time and drops one sent while the last
  is still going out, so the call to each network by name (the one a
  Wi-Fi Direct group needs) and to each greeted address was mostly lost.
  They now go out one after another.
- A connection the other end reset as it was being made (its copy
  stopping, say) surfaced as an unhandled error instead of being treated
  as "not reachable". Same for the LoRa device's TCP link.

### Removed
- Nothing user-facing. A stray 3-byte "sticker" is no longer accepted as a
  picture.

## 0.1.0 — 2026-10-24

First build: identities, chat requests, direct chats, spaces, calls,
files, Bluetooth LE, local Wi-Fi and Wi-Fi Direct links, mesh relay,
verification by words, QR and NFC, app lock, emoji and stickers.
