# Hardware for the long-range radio

What to buy to use DNet's LoRa transport. Prices are approximate retail
(late 2026, before shipping and tax) and move with exchange rates. Every
board here runs Meshtastic, which is what DNet speaks.

**Read before buying:**

- **Band.** Boards are sold per band and cannot be changed. Buy the one
  for your country: 865–867 MHz in India (buy the "868" or "865" variant,
  it covers it), 868 in Europe, 915 in the Americas and Australia, 433
  only where 868/915 are not allowed. See [RADIO.md](RADIO.md#bands-and-the-law).
- **Never power a LoRa board without its antenna attached.** The output
  stage can be destroyed in a second of transmitting into nothing.
- **Antenna band must match the board.** A 433 MHz antenna on an 868 MHz
  board wastes power and can damage the radio over time.
- The cheapest boards are the ones most often sold as the wrong band or
  without an antenna. Check the listing twice.

## Recommended boards

| Board | Price | Radio | Connects to DNet by | Battery | GPS | Best for |
|---|---|---|---|---|---|---|
| **Heltec WiFi LoRa 32 V3** | $20–28 | SX1262 | USB-C (serial), Bluetooth LE, Wi-Fi (TCP) | add a 3.7 V LiPo (JST 1.25) | no | phone or laptop; the all-round first buy |
| **LILYGO T-Beam (Supreme or v1.2)** | $35–55 | SX1262 | USB-C, BLE, Wi-Fi | 18650 cell holder built in | yes (NEO-6M/8M or u-blox) | a fixed or vehicle node, long days out |
| **Heltec WiFi LoRa 32 V4** | $25–35 | SX1262 (more transmit power) | USB-C (the chip's own), BLE, Wi-Fi | LiPo connector, solar input | GNSS header | the V3's successor; laptop or relay |
| **LILYGO T-Echo** | $55–70 | SX1262 (nRF52840) | USB-C, BLE | 850 mAh built in, e-paper screen | yes (L76K) | phone: weeks on a charge, pocketable |
| **Seeed SenseCAP T1000-E** | $40–45 | LR1110 (nRF52840) | magnetic USB cable, BLE | built in, card-sized | yes | a pocket tracker that also carries DNet |
| **Station G2** | $100+ | SX1262 with a power amplifier | USB-C, BLE, Wi-Fi | 12 V or USB-PD | no | a fixed base or relay where the law allows its power |
| **RAK WisBlock (RAK4631 core + RAK19007 base)** | $45–60 for the pair | SX1262 (nRF52840) | USB-C, BLE | LiPo and solar input on the base | optional RAK12500 module (~$25) | the most reliable; a roof relay or a phone companion |
| **Budget: LILYGO T3S3 or Heltec V2 clone, or a bare ESP32 + SX1262 module (RA-01SH / E22-900M22S)** | $12–20 | SX1276/SX1262 | USB (serial), BLE, Wi-Fi | LiPo header on most | no | tinkering; the DNet serial firmware path |

### Notes per board

- **Heltec V3.** Buy the version with the 0.96" OLED; it shows the node's
  status without the app. Its USB-C goes through a CP2102 bridge chip:
  Windows usually fetches the Silicon Labs driver itself; if the port
  does not appear, install it. The port shows in DNet as "USB bridge chip
  (CP210x)". Short stub antenna included; replace it.
- **Heltec V4.** USB through the ESP32-S3's own port, so no driver. More
  transmit power than the V3: keep within the band's limit.
- **T-Beam.** Older v1.1 boards use a CP2102 USB bridge (Windows needs the
  Silicon Labs driver). The Supreme has a better GPS and USB-C. The
  18650 holder means a day of use on a single cell.
- **T-Echo.** No Wi-Fi. Its USB is the nRF52840's own and carries the
  Meshtastic API as well as charging, so a PC reaches it over USB and
  Android over USB or Bluetooth. Best battery life of the list.
- **SenseCAP T1000-E.** Its magnetic cable carries USB data; a plain
  charging cable for it does not. Its LR1110 radio speaks LoRa like the
  SX1262 boards.
- **Station G2.** Its amplifier can exceed what many bands allow (up to
  about 30 dBm); set the power within your band's limit.
- **RAK WisBlock.** Modular: core, base and optional modules click
  together. Lowest power draw; the usual choice for solar relays. Its USB
  appears as a CDC serial port, which both Android and Windows handle
  without a driver.
- **Budget boards.** Often sold without an antenna or as the wrong band.
  Check the listing. CH340 USB bridges work on Android with the app's
  serial code and on Windows with the WCH driver.

## Band variants to buy

| Where you are | Board variant | Antenna |
|---|---|---|
| India | 868 (covers 865–867) | 868 MHz |
| EU, UK, Türkiye, Middle East, most of Africa | 868 | 868 MHz |
| USA, Canada, Mexico, Brazil, Australia, NZ | 915 | 915 MHz |
| Japan, Korea, Taiwan, Thailand, Malaysia, Singapore | 915 or 923 variant where sold; check the region table in the app | 915 MHz |
| China | 470 | 470 MHz |
| Where only 433 is allowed | 433 | 433 MHz |

## Antennas

- The stock 2–3 cm stub is a compromise. A **half-wave dipole or whip for
  your band** (about 16 cm at 868/915 MHz, 33 cm at 433 MHz), SMA male to
  match the board's SMA female, costs $5–10 and roughly doubles range.
- For a fixed relay, a **5–6 dBi fibreglass outdoor antenna** on a pole
  ($20–40) with a short low-loss cable (LMR-200 or better) makes the
  single biggest difference to a mesh.
- Check the connector: most boards are SMA female; some are RP-SMA (the
  pin is on the antenna). Adapters exist; losses are small.
- Keep it vertical, in the open, above head height when you can.

## Cables and power

- **Phone (Android):** a USB-C to USB-C cable if both ends are USB-C
  (most 2023+ boards), or a **USB-OTG adapter** (USB-C male to USB-A
  female, $3–6) plus a USB-A to USB-C or micro-USB cable. The phone powers
  the board; expect 100–150 mA while listening. Or skip the cable and use
  Bluetooth.
- **Laptop:** any data-capable USB-C cable. Charge-only cables are the
  most common reason a board "does not show up".
- **Battery:** a 3.7 V LiPo with a JST-PH 1.25 mm plug for Heltec and RAK
  (check the polarity against the board's marking; a reversed plug kills
  the board), an 18650 cell for the T-Beam. 1000–3000 mAh gives a day to
  a week of standby.
- **Solar relay:** RAK WisBlock base + a 6 V 1–2 W panel + a 3000 mAh
  LiPo in a weatherproof box, antenna outside.

## Optional

- **GPS** is not used by DNet. Meshtastic uses it for its own position
  features; turn position broadcasting off if you do not want your node
  to announce where it is.
- **Screen:** nice for seeing the node is alive; not needed.
- **Case:** 3D-printed cases exist for every board above; a $3 case
  protects the antenna connector, which is the part that breaks.

## Which to pick

- **One phone, cheapest working setup:** Heltec V3 + half-wave antenna +
  OTG cable, about $35.
- **Phone, no cable, best battery:** T-Echo, about $65, over Bluetooth
  (Android; Bluetooth to a radio is not built for Windows in this
  release, but USB is).
- **Laptop:** Heltec V3 or RAK WisBlock over USB; RAK if it will stay on
  for days.
- **Extending everyone's range:** one RAK WisBlock solar relay on a roof
  for the whole group.

## What to avoid

- Any board without a stated band, or a "universal" band: there is no
  such thing.
- A board with no antenna in the box, unless you buy one for the right
  band before powering it.
- Reversed LiPo plugs on Heltec boards: check the red wire against the
  board's `+` mark.
- Charge-only USB cables.
- Older SX1276 boards for a new mesh: they work, but the SX1262 boards
  listen better and use less power.
- Boards with 2.4 GHz LoRa (`LORA_24`): legal everywhere, but short range
  indoors and no mesh of others to join.

These are the boards the Meshtastic community reports as reliable.
