# Long-range radio (LoRa)

DNet can send chat through an external LoRa radio plugged into a phone or
a PC. LoRa reaches kilometres where Bluetooth reaches metres, at the price
of being slow: a few hundred bytes a second, shared with everyone on the
band. This document says what works, what it needs, and what it cannot do.

## What it is for

- Chat, chat requests, receipts, verification words, space messages:
  anything short. A text message is about 1.4 KB sealed, which is ten
  seconds of airtime on the default radio settings.
- Not files. A file piece is up to a megabyte; the link pump drops file
  pieces on radio links, and they wait for Bluetooth or Wi-Fi. Not calls.
- People far beyond Bluetooth: across a valley, a campus, a town, through
  other Meshtastic nodes in between.

## Supported devices

| Device | How it connects | Driver |
|---|---|---|
| Any Meshtastic device (Heltec, LILYGO, RAK, Seeed, and many more) | USB serial, Bluetooth LE (Android), TCP over Wi-Fi | Meshtastic |
| A bare SX126x / SX127x module on a microcontroller running the DNet serial firmware | USB serial | Serial LoRa |

Meshtastic is the first choice: it is what most LoRa boards ship with or
can be flashed with, it routes through other nodes (mesh), and the app
speaks its official protobuf API. The bare-module driver is for people who
build their own node. See [HARDWARE.md](HARDWARE.md) for what to buy.

### By platform

| Platform | USB serial | Bluetooth LE | TCP (Wi-Fi) |
|---|---|---|---|
| Android 10+ | yes, with a USB-OTG cable; Android asks for permission | yes | yes |
| Windows | yes (COM port, through the Windows API) | not in this release | yes |
| Linux, macOS (not official build targets) | yes (/dev/ttyUSB*, /dev/cu.*) | not in this release | yes |
| iOS | no: Apple allows apps no serial access | would be the only way | yes |

iOS is not a build target of this repository. If it ever is, the radio
will reach a device only over Bluetooth LE or Wi-Fi. Bluetooth on Windows
needs the Rust radio library to grow a GATT client; it is not built.

## Setting up

1. Flash the device with Meshtastic (`https://flasher.meshtastic.org`) if
   it did not come with it. Pick the firmware for your board and region.
2. **Attach the antenna before powering the board.** A LoRa radio
   transmitting with no antenna can burn out its output stage.
3. On the Meshtastic app or web client, set the region once. Set the
   modem preset to `LONG_FAST` (the default) unless you know better.
4. In DNet: You → Network → Long-range add-on (the row's text opens the
   setup screen).
   - **Device**: choose USB, Bluetooth or Wi-Fi, then the device. On
     Windows each COM port says what is behind it (the board's own USB,
     or a CP210x, CH340/CH9102 or FTDI bridge chip); Bluetooth serial
     ports are listed last, since they are almost never a radio.
     Over Wi-Fi, type the node's numeric address on your local network
     (port 4403), such as `192.168.1.40`. DNet refuses addresses that are
     not on a local network, and does not take names: looking a name up
     would be a DNS request, and the app makes no network requests of its
     own.
   - **Band**: choose the region that is legal where you are (the list
     can be searched). DNet sends the choice to the device, which reboots
     to apply it, but only when it differs from what the device already
     has. Until you choose, the device keeps its own setting, and the
     screen says so.
   - Switch **Long-range** on under Links.
   - **Test the link**: "Say hello on the air" sends one "DNet is here"
     at once. DNet radios in range answer with their own; the step is
     ticked when one is heard.
5. The Link card shows the connection, the board, firmware, preset and
   band, signal bars with RSSI and SNR, how many DNet devices were heard
   and when, the last timed round trip, counts, the airtime spent against
   the band's limit, and the device's own words when it holds something
   back ("Duty cycle limit exceeded. You can send again in 12 mins").
   On a wide window the steps and the Link card sit side by side.

Each DNet device says "DNet is here" on the air every two minutes (seven
bytes: "DNet", a version, and two bytes that change each time its radio
comes back). Hearing one, the app opens a link and runs the same
handshake as over Bluetooth: each side shows its identity and signs the
other's random number. Nothing is sent to a device that has not proved
itself.

Every frame on a link carries a tag of the sender's link (four random
bytes, chosen when the link opens). The handshake's hello is sent once
and a link takes one hello, so a frame of an old link must never reach a
new one: a retry of the old link arriving in the middle of the new
hello would leave both sides unproved. So a frame tagged for a link
that has ended is dropped; a frame with a tag not heard before means
the other end began a new link, and the old one is closed at once, even
if its "my radio came back" beacon was lost; and closing a link stops
the protocol retrying what was in flight on it.

## Bands and the law

**You must choose the band that is legal in your country.** Transmitting
on another band is an offence almost everywhere and can interfere with
emergency and licensed services. DNet never guesses the region: it is
blank until you choose.

| Region (DNet / Meshtastic) | Band | Limits |
|---|---|---|
| India (`IN`) | 865–867 MHz | licence-free; 1 W transmitter power, 4 W ERP, 200 kHz carrier bandwidth |
| Europe (`EU_868`) | 869.4–869.65 MHz | 10 % airtime, 500 mW |
| Europe (`EU_433`) | 433.05–434.79 MHz | 10 % airtime, 10 mW |
| Americas (`US`) | 902–928 MHz | 400 ms dwell, no duty cycle |
| Brazil (`BR_902`) | 902–907.5 MHz | |
| Australia / NZ (`ANZ`, `ANZ_433`), New Zealand (`NZ_865`) | 915–928, 433.05–434.79, 864–868 MHz | |
| Japan (`JP`) | 920.5–923.5 MHz | listen before sending (ARIB STD-T108); DNet keeps to 10 % |
| Thailand (`TH`) | 920–925 MHz | 10 % airtime |
| Ukraine (`UA_868`, `UA_433`) | 868–868.6, 433–434.7 MHz | 1 %, 10 % airtime |
| Korea (`KR`), Taiwan (`TW`), China (`CN`), Russia (`RU`), Malaysia (`MY_919`, `MY_433`), Singapore (`SG`), Philippines (`PH_915`, `PH_868`, `PH_433`), Nepal (`NP_865`), Kazakhstan (`KZ_863`, `KZ_433`), 2.4 GHz boards (`LORA_24`) | see the app | |

**India and bandwidth.** The licence exemption limits each signal to
200 kHz. Meshtastic's default preset, `LONG_FAST`, is 250 kHz wide. If
the device reports a wider preset while the band is India, the Band step
says so and suggests `LONG_MODERATE` (125 kHz), which is set in the
Meshtastic app. DNet does not change the preset itself: every node on a
mesh must use the same one.

Where a band has an airtime (duty-cycle) limit, DNet budgets its own
sending against it: a packet that would overspend the hour waits. The
device's firmware enforces its own limit too. Where there is no limit,
DNet still sends nothing it does not have to.

## Range and antennas

- With the stock stubby antenna at head height, expect 1–3 km in a town,
  5–10 km with line of sight, more from a hill. Range is set far more by
  height and line of sight than by power.
- A proper half-wave antenna tuned for your band (868 or 915 MHz: about
  16 cm long) roughly doubles range over the stub. An antenna for the
  wrong band (a 433 MHz antenna on an 868 MHz board) wastes most of the
  power and can damage the radio.
- Keep the antenna vertical, away from your body and metal.
- A relay node on a roof or hill with a solar panel extends every other
  device's reach: Meshtastic passes packets on for up to the hop limit
  (DNet asks for 3).

## Limits

- **Airtime.** `LONG_FAST` carries about 1 kbit/s. A sealed DNet text is
  ~1.4 KB: around 10 seconds on the air, before retries. A chat request
  (the identity plus the proof) is larger. In a 10 % duty-cycle region
  that is roughly 30 messages an hour. Keep messages short.
- **Packet size.** A LoRa packet carries at most 255 bytes. Meshtastic
  takes 16 for its header, 12 for public-key encryption of a direct
  packet and 8 for the tags around the app's bytes, which leaves 219;
  DNet uses 212 and keeps a few spare. The core cuts messages into
  frames that fill one packet (201 bytes on Meshtastic, after the
  protocol's 6-byte header and the link's 5-byte tag); fewer, fuller
  packets cost less airtime than
  more, smaller ones, since each pays for a preamble and a header and is
  answered by an ACK. Frames go one at a time per link, each
  acknowledged before the next, so a retry can never overtake the frame
  after it: the core rebuilds a message in arrival order.
- **Message size.** Nothing over 4 KB goes by radio at all. Files never do.
- **Hops.** A packet may be passed on by up to 3 nodes (Meshtastic's
  default). DNet's own relay (the mesh of DNet devices) is separate and
  still works across radio links.
- **Latency.** Seconds per frame (a full frame is about 2 s on the air
  on `LONG_FAST`, about 11 s on `LONG_SLOW`), minutes for a handshake over
  several hops. "Delivered" means the other DNet device acknowledged
  every fragment.
- **Privacy on the air.** Meshtastic's channel key is shared by everyone
  on the channel and is treated as nothing. Every DNet frame on the air
  is a core envelope (HPKE, signed inside) or a link handshake. What a
  listener learns: that two DNet devices are talking, their radio node
  numbers, when, and how much. DNet leaves the device's "OK to MQTT"
  off, which asks every node on the way not to pass its packets to an
  internet bridge; official firmware honours that on the default
  channel keys. A node with its own key and a bridge could still carry
  them; they stay sealed end to end.

## What the protocol adds on top of the radio

`app/lib/radio/lora/radio_protocol.dart`:

- fragments and reassembly (any order), per sender and message number;
- ACK naming the missing fragments; only those are resent; exponential
  backoff with jitter, up to a limit, then "failed", with the reason in
  plain words;
- waits worked out from the radio: before a round trip to a device has
  been timed, the airtime of the fragments and the ACK times the hops
  they may cross; after, the measured round trip with room for its
  spread (RFC 6298), never timing a message that was resent (Karn's
  rule);
- priorities for the radio's own queue: ACKs first, chat next, "DNet is
  here" last;
- dedupe and replay windows per sender (a 16-bit message number that only
  goes up within a run); on top of the core, which drops any envelope it
  has already seen and checks every signature;
- a hop limit handed to the radio;
- raw-deflate compression when it shrinks a message (sealed envelopes do
  not shrink; beacons and plain control frames do);
- an airtime budget from the region's duty cycle and each packet's
  real time on the air (Semtech's formula from the preset's spreading
  factor, bandwidth and coding rate); the regular "DNet is here" stands
  aside once half the band's allowance for the hour is spent;
- bounded reassembly (32 messages, 3 minutes) so a stranger cannot make a
  device hold memory for ever;
- parsers that never throw on bad bytes;
- compressed messages opened in pieces and stopped at the size limit.

The protocol can also leave acknowledgement to the radio below
(`reliable: false`): Meshtastic then sends with `want_ack`, and its
routing answers are used instead: a reply from a node in between is
"relayed", one from the destination is "delivered", an error is
"failed". DNet runs with its own ACKs on every radio, since they come
from the other DNet device and not just the other radio, and so that
the same waits apply over Meshtastic and a bare module alike. Either
way, a refusal from the device (duty cycle, full queue, too large) fails
the frame at once with the device's reason.

### Talking to a Meshtastic device

- On a serial or TCP link, 32 bytes of `0xC3` go first, as the official
  clients send them: they wake a sleeping device and make one whose
  reader was halfway through a broken frame look for a new one.
- The device answers every packet handed to it with a `QueueStatus`
  saying how much room its send queue has left. A packet handed to a
  full queue is dropped, so DNet waits for room (up to 30 s) before
  handing over the next.
- A `ClientNotification` about one of DNet's packets (the firmware sends
  one when the hour's duty cycle is spent) fails that packet with the
  device's own words, and the Link card shows them.
- Changing the band is an admin message to the device itself; from the
  app's own link it needs no session key. The device saves it and
  reboots. DNet sends it only when the band differs, and asks for the
  device's settings again afterwards, for links that stay open across
  the reboot (a USB bridge chip keeps the port while the radio restarts).
- `rx_rssi` is an `int32`: a negative value arrives as a ten-byte varint.
  0.2.0 read it as zigzag (`sint32`), which gave nonsense signal readings
  from real firmware. It is now read as the official encoder writes it.

## Generic serial modules

For a bare SX126x/SX127x module behind a microcontroller, the app speaks
its own small framing over the serial port at 115200 baud
(`serial_lora_driver.dart`). Every frame:

```
A5 5A | length (2 bytes, big-endian: type + payload + CRC) | type | payload | CRC-16/CCITT-FALSE over type and payload
```

| Direction | Type | Payload |
|---|---|---|
| app → module | `01` PING | none |
| app → module | `02` CONFIG | frequency kHz (u32), SF (u8), bandwidth kHz (u16), coding rate (u8), power dBm (i8) |
| app → module | `03` SEND | to (u32), hop limit (u8), id (u32), data |
| app → module | `04` STATUS | none |
| module → app | `81` PONG | node number (u32), firmware name (text) |
| module → app | `83` RECV | from (u32), to (u32), id (u32), hops (u8), RSSI (i16), SNR ×4 (i8), data |
| module → app | `84` STATUS | frequency kHz (u32), SF (u8), bw kHz (u16), CR (u8), power (i8), bits/s (u32) |
| module → app | `85` SENT | id (u32), ok (u8) |
| module → app | `8F` ERROR | code (u8), text |

Addresses are 32-bit; `FFFFFFFF` is everyone. The module does any mesh
forwarding it likes; the app only needs RECV for packets addressed to it
or to everyone. A reference firmware for RadioLib is a few hundred lines;
none ships with this repository.

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| "nothing answered on the port" | wrong port, wrong firmware, or the board is in bootloader mode | pick the other port; reflash; press reset |
| "could not open COM5. Another app may have it open" (Windows) | a COM port has one user at a time: the Meshtastic web client, Arduino, a terminal | close the other app, or unplug and replug |
| The board's port does not appear (Windows) | a charge-only cable, or no driver for its bridge chip (CP210x: Silicon Labs; CH340/CH9102: WCH) | try another cable; install the bridge's driver |
| "The radio says: Duty cycle limit exceeded" | the band's hourly airtime is spent | wait the minutes it says; send less |
| "could not use the radio: permission" (Android) | USB permission refused, or no OTG support | unplug and replug, allow the dialog; try another phone |
| Connected, but "No DNet devices heard" | different regions or presets on the two radios, or out of range | set both to the same region and `LONG_FAST`; move higher |
| Messages "failed" | the other radio is gone, or airtime budget spent | wait; check the band's duty cycle on the screen |
| Signal "Faint" | at the edge of range | better antenna, height, line of sight |
| Everything slow | normal for LoRa | keep messages short; do not send files |
| The device reboots when the band is chosen | expected: Meshtastic reboots to apply the region | wait a few seconds; the link comes back on its own |

## What has not been verified

- Any real LoRa hardware, over any of the three connections.
- The Android USB serial code (`RadioSerial.kt`) and Bluetooth code
  (`RadioBle.kt`): written against the platform APIs, not yet run on a
  phone.
- The Windows COM-port link (`windows_serial.dart`): checked on Windows
  only for listing ports and failing cleanly on one that is not there.
  No bytes have crossed a real COM port.
- The firmware's `QueueStatus`, `ClientNotification` and reboot
  behaviour as DNet now uses them: written from the firmware and the
  official Python client's source, checked against a stand-in.
- Meshtastic firmware other than the 2.5 to 2.7 protobufs the codec was
  checked against (field numbers are stable across 2.x).

## What we learned, and the choices it led to

Research done in November 2026 against the Meshtastic protobufs,
firmware and Python client, Semtech's documents and the regional rules.

- **Payload.** The firmware's packet limit is 255 bytes with a 16-byte
  header; public-key encryption of direct packets (firmware 2.5 and
  later) adds 12 more, and the firmware refuses a packet that will not
  fit with `TOO_LARGE`. `DATA_PAYLOAD_LEN` (233) is the limit without
  it. So DNet sends at most 212 bytes a packet and gives the core
  frames that fill one: the old 160-byte frames left a quarter of every
  packet empty and needed more packets and more ACKs per message.
- **Airtime decides everything.** A full packet on `LONG_FAST` (SF11,
  250 kHz, 4/5) is about 2 s on the air; on `LONG_SLOW` (SF12, 125 kHz,
  4/8) about 11 s. The fixed 6-second first retry of 0.2.0 could resend
  a frame on a slow preset before its first copy had finished sending,
  doubling the airtime it used. Waits are now worked out from the
  preset, then from measured round trips.
- **The device has a queue and says how full it is.** The official
  clients wait for room (`QueueStatus.free`); handing packets to a full
  queue loses them. DNet now does the same.
- **The firmware enforces the duty cycle itself** where the region has
  one, and says so with a `ClientNotification` and a `DUTY_CYCLE_LIMIT`
  routing error. DNet's own budget keeps it under that; when the device
  refuses anyway (other traffic from the same node counts too), the
  device's words reach the screen instead of a silent failure.
- **Regions.** The firmware's table had grown: Brazil, the Philippines,
  Nepal, Kazakhstan, Australia/NZ 433 and New Zealand 865 were added;
  Thailand has a 10 % duty cycle; Japan's band is 920.5–923.5 MHz at
  13 dBm. DNet's table now matches, and keeps a 10 % budget for Japan
  (ARIB STD-T108 limits transmissions there, and the firmware does not
  budget for it).
- **Windows serial.** A COM port opens for one handle only, and a read
  with the driver's default timeouts waits for its whole buffer, so the
  0.2.0 approach (the port opened twice as a file, the speed set with
  `mode`) could not work. DNet now opens it once through the Windows API
  with reads that return at once, and sets DTR and RTS on together, as
  the official clients' serial library does: boards with a native USB
  port (nRF52, ESP32-S3) only talk once DTR is on.
- **Boards.** The Heltec V3 talks through a CP2102 bridge chip; the
  Heltec V4, RAK4631, T-Echo and T1000-E through the chip's own USB.
  Windows 10 and 11 need no driver for the native ones and usually fetch
  the CP210x and CH340 drivers themselves.

Sources:

- Meshtastic protobufs, `mesh.proto` and `config.proto`:
  https://github.com/meshtastic/protobufs
- Meshtastic firmware, `RadioInterface.cpp`, `RadioInterface.h`,
  `MeshRadio.h`, `Router.cpp`, `AdminModule.cpp`:
  https://github.com/meshtastic/firmware
- Meshtastic client API (BLE UUIDs, stream framing, TCP port 4403):
  https://meshtastic.org/docs/development/device/client-api/
- Meshtastic LoRa settings (regions, presets, hop limits):
  https://meshtastic.org/docs/configuration/radio/lora/
- Meshtastic Python client, `stream_interface.py` and
  `mesh_interface.py` (wake bytes, heartbeat, queue status):
  https://github.com/meshtastic/python
- Semtech AN1200.13, "LoRa Modem Designer's Guide" (time on air).
- RFC 6298, "Computing TCP's Retransmission Timer".
- ERC Recommendation 70-03 and ETSI EN 300 220 (Europe, 869.4–869.65
  MHz: 500 mW, 10 %).
- India, Department of Telecommunications: licence exemption for
  865–867 MHz (G.S.R. 564(E), 2008, and the 2021 short-range device
  rules): https://dot.gov.in
- ARIB STD-T108 (Japan, 920 MHz):
  https://www.arib.or.jp/english/std_tr/telecommunications/desc/std-t108.html
