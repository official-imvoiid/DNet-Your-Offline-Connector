# DNet design spec

DNet is a phone app for chatting and sending files with people nearby, with no internet needed. This file describes the design in words. The exact values live in `reference-html/`, and `screens/` shows what each screen must look like.

## 1. Which file wins

1. `reference-html/NN-name.html` is the exact design. Every colour, size, radius, gap and string is in its inline styles.
2. `screens/NN-name.png` is the visual check, rendered from that HTML at 3x (1170 x 2532 px for a 390 x 844 pt screen).
3. This file explains behaviour, rules and anything a still image cannot show.

If two of them disagree, the lower number wins.

## 2. Product rules

These are requirements, not suggestions.

- **Nearby is the core.** Bluetooth and nearby Wi-Fi are on by default. Internet is an optional switch that starts off.
- **No account.** No phone number, no email, no contact upload. Identity is a key made on the phone.
- **Request before chat.** Nobody can send a direct message until the other person accepts a chat request. Declined people are not told. Blocked people cannot ask again.
- **Direct messages and spaces are separate.** The Chats tab holds one-to-one chats only. Group conversation happens in channels inside spaces.
- **Spaces are private or public.** Private spaces need an invite and never appear in search. Public spaces can be found and joined. A public channel lets only its owner post.
- **Verification.** A person stays tagged "Not verified" until both people compare four words or scan a code.
- **User choices are plain on/off switches.** Sharing switches start off, which is the private setting.
- **Protection is not a user choice.** Encryption, post-quantum keys, encrypted storage and key-change alerts are always on and have no switch. The link protections on the Network screen are automatic and have no switch.
- **Data stays on the phone** until the user wipes it. Auto-delete and erase-on-wrong-passcode exist but start off.
- **Wording.** Radio problems are called "interference" or "link trouble" in all user-facing text.

## 3. Design tokens

### Colour

| Token | Hex | Use |
|---|---|---|
| bg | #1C1D22 | Screen background |
| surface | #24252B | Cards, tab bar, sheets, composer |
| raised | #2D2F36 | Secondary buttons, chips, their chat bubbles, icon circles |
| selected | #34363E | Selected channel row |
| line | #383A42 | 1 px dividers and borders |
| text | #F2F3F5 | Primary text |
| text-2 | #B3B6C0 | Secondary text |
| text-3 | #8E919C | Timestamps and footnotes, on bg or surface only |
| accent | #4DA3FF | Primary buttons, links, active icons, unread badges |
| accent-ink | #0B1A2B | Text and icons on accent |
| accent-soft | #1E2F45 | Tinted highlight backgrounds |
| own-bubble | #244B78 | The user's own chat bubbles, selected poll bar |
| green | #3DD68C | Verified, online, speaking, working |
| green-ink | #0B2A1C | Text on green |
| green-soft | #1B3A2C | Green chip background |
| amber | #F5C451 | Not verified, caution |
| amber-soft | #3D3218 | Amber chip and alert background |
| red | #FF6B6B | Destructive actions, no signal |
| red-ink | #2B0F10 | Icon on red |
| switch-off | #4A4D57 | Switch track when off, sheet grabber |

Avatar colour pairs (background, text): rose #6B2F45 / #FFD3E0, blue #2B4E7A / #CFE4FF, violet #4A3B78 / #E0D6FF, amber #6A5216 / #FFE9A8, teal #1D5560 / #C5F1F7, green #1F5A45 / #C9F5DF, red #5A2A2A / #FFD6D6, grey #3A3C44 / #F2F3F5. Each person and each space keeps one pair everywhere.

### Type

- **Figtree** for everything: weights 400, 500, 600, 700, 800.
- **JetBrains Mono 500** for codes, key fingerprints, verification words and transfer speed.
- Base text 15 px, line height 1.4.
- Screen title on tab screens: 28 px, weight 800, letter spacing -0.01em.
- Top bar title: 18 px, weight 700.
- Row title: 16 px, weight 700. Row detail: 13 to 14 px in text-2.
- Section label: 13 px, weight 600, text-2, sentence case.
- Timestamp: 12 px, text-3.

### Shape and size

- Screen: 390 x 844 pt. Side padding 16 or 20.
- Radius: 8 chips, 10 channel rows and poll bars, 12 small buttons and inputs, 14 large buttons, 16 cards, 20 hero cards and voice tiles, 28 sheet top. Circles for people, rounded squares (radius one third of size) for spaces.
- Touch targets are at least 44 x 44.
- Cards have no border, only the surface colour. Lists use 1 px dividers or nothing.
- Icons: outline, 2 px stroke, round caps and joins, 24 unit grid.

## 4. Components

- **Tab bar.** Four tabs: Chats, Spaces, Nearby, You. Surface background, 1 px top line. Each tab is 52 high with radius 14. Active tab: raised background, text colour for the label at weight 700, accent icon. Inactive: text-2 at weight 500.
- **Top bar.** 56 high. Back button, optional avatar, title with optional one-line subtitle, up to two icon buttons.
- **Buttons.** Large: 52 high, radius 14, 16 px. Compact: 44 to 48 high, radius 12, 15 px. Primary is accent with accent-ink text. Secondary is raised with text colour. Success is green with green-ink. Danger is a 1 px red outline with red text.
- **Switch.** Track 52 x 30, radius 15, 3 px inset, white 24 px knob. Accent when on, switch-off when off. The tappable area is 52 x 44.
- **Avatar.** Sizes 24, 38, 40, 44, 48, 56, 64, 68. Initial at 40 percent of the size, weight 700. Online: green dot with a 3 px ring in the background colour. Speaking: 3 px gap then a 3 px green ring.
- **Chip.** 12 px, weight 600, padding 2 x 8, radius 8. Tones: neutral, amber, green, accent.
- **Chat row.** 72 high, avatar 48, name plus verified badge, one-line preview, time on the right, optional unread badge (22 high pill, accent).
- **Bubbles (direct messages).** Theirs: raised, radius 20 20 20 6. Mine: own-bubble, radius 20 20 6 20. Padding 10 x 14, maximum width 280. Time and read ticks in 12 px below the text.
- **Channel message (spaces).** No bubble. Avatar 40, then name, verified badge and time on one line, then content below.
- **Composer.** Surface pill, radius 26. Plus button on the left, text field, round accent microphone button on the right.
- **Voice note.** Pill with a round accent play button, 14 waveform bars (played bars in accent, the rest text-3), and the duration in mono.
- **Sheet.** Surface, top radius 28, 40 x 4 grabber, content dimmed behind at 30 percent opacity.

## 5. Navigation

- Tabs: Chats (02), Spaces (07), Nearby (14), You (17).
- 01 Welcome goes to 02 Chats.
- 02 Chats: the requests banner opens 03; the add-person button opens 04; a row opens 06.
- 03 Chat requests: Accept opens 06 with that person.
- 04 New chat: after a request is accepted, offer 05 Verify.
- 06 Direct message and 08 Channel: the plus button opens 09 Share sheet; "Send a big file nearby" starts 10 File transfer.
- 07 Space: a text channel opens 08; a voice room opens 11; the megaphone icon in the rail opens 13; the plus icon opens 12.
- 12 Find a space: Open goes to 13 for a channel; Join adds the space to the rail.
- 14 Nearby: Chat opens 06; Request sends a chat request; the code button scans.
- 17 You: "Privacy and security" opens 18; "Network" opens 15.
- 16 Link trouble appears from 15, or as a banner tap, when links fail together.

## 6. Screens

### 01 Welcome
First launch. Logo tile, the name DNet, one-line promise, three points with icons. At the bottom: a name field prefilled with a suggestion, a Random button that replaces it with a generated name, and Get started. Get started creates the identity key and opens Chats. The name may be anything and can be changed later.

### 02 Chats
Direct messages only. Title with search and add-person buttons. A banner shows the number of waiting chat requests and is hidden when there are none. Rows: avatar with online dot, name, verified badge, last message preview, time, unread count. A clock icon marks chats with disappearing messages. "Saved messages" is a private notes chat that never leaves the phone. Footnote explains the request rule.

### 03 Chat requests
"Waiting for you" cards show who is asking, whether they are verified, what you have in common, and their optional note. Actions: Accept, Decline, Block. "Sent by you" lists outgoing requests with Cancel. A request from someone with nothing in common shows that fact in amber.

### 04 New chat
The user's own code as a QR image and a short spoken code (two words and a number), with Share link and Copy. Four ways to reach someone: scan their code, find nearby, tap phones together, paste an invite link. Each one sends a chat request; none opens a chat directly.

### 05 Verify a person
Four words in a 2 x 2 grid in mono. Both people must see the same words. Alternative: scan the other person's code. "The words match" marks the person verified and removes the amber tag everywhere. "They do not match" keeps them unverified and warns the user.

### 06 Direct message
Top bar shows the person, verified badge, and how they are connected right now ("Nearby, on Bluetooth"). A centred note states the chat is encrypted. Bubbles for text, a voice note pill, read ticks on the user's messages, and a clock with "Gone in 1 day" on messages set to disappear.

### 07 Space
Left rail (72 wide, surface) lists the user's spaces as rounded squares; the selected one has an accent ring; a dashed plus opens Find a space. The main column shows the space name, a Private or Public chip, member count and an invite button. Channels are grouped under Info, Text and Voice. The selected channel has the selected background and an unread badge. An active voice room lists who is inside, with a green ring on whoever is speaking. Footnote: the space is kept on members' phones.

### 08 Channel
Channel name with a hash icon, the space and how many members are nearby. A pinned message strip under the bar. Messages are flat rows. Shown here: a reply reference, a file attachment, reaction pills (the user's own reaction is tinted and outlined in accent), a poll with percentage bars and an anonymous vote count, a voice note, and a disappearing message.

### 09 Share sheet
Opens over a chat or channel. Eight round options in a 4 x 2 grid: Photo, File, Voice, Poll, Contact, Location, View once, Camera code. A highlighted row sends a big file to someone nearby at Wi-Fi speed. One switch: remove location from photos, on by default.

### 10 File transfer
File name, size and recipient. A card with percent complete, speed in mono, a progress bar, amount sent and time left. Three steps show how the link was made: found over Bluetooth, key checked, switched to Wi-Fi for speed. Two facts: AES-256 encryption, and the transfer resumes by itself if the link drops. Pause and Cancel.

### 11 Voice room
A 2 x 2 grid of people with their state: Speaking (green ring and label), Listening, or Muted. A call key card shows four words that every participant should see. Controls: microphone, speaker, camera, leave (red).

### 12 Find a space
Search field for public spaces. Results show an icon, name, type (Channel or Community), a short description, and Open or Join. A note says results come from phones around the user and there is no central list. A card for private spaces offers Paste link and Scan code. Create a space at the bottom.

### 13 Public channel
Only the owner posts. Each post shows a "Signed by the owner" line with a green badge. Readers can react and comment. The footer states that the owner cannot see who follows, with Following and Mute.

### 14 Nearby
The app's core screen. A radar graphic places nearby people around the user's own dot, beside the count of people in range and "No internet needed". The list shows each person's link: "Wi-Fi, fast" in accent, "Bluetooth, chat only", or "2 hops, through Mira". Friends get a Chat button; others get Request. People out of range are dimmed.

### 15 Network
A status card summarises current links. "Links" has four switches: Bluetooth (on), Wi-Fi nearby (on), Long-range add-on (off, needs extra hardware), Internet (off, optional). "Keeps you connected" lists five automatic protections with a green "Automatic" chip and no switches: sends on both radios at once, changes band when one is crowded, long-range mode for weak signal, rebuilds files from any pieces, holds messages until a path opens. A last line states the encryption and that it is always on.

### 16 Link trouble
Shown when links fail together while people are still in range. An amber card names it "Strong interference". A list shows each radio as "No signal" (red) or "Working" (green). A signal meter with five bars says whether the link to a person is getting better or worse as the user walks. "What DNet is doing" lists the automatic actions taken. Buttons: pass messages by camera code, and try all radios again. The app must never claim to know the cause.

### 17 You
Avatar, name, key fingerprint in mono, and chips stating no phone number and no email. Three grouped lists: identity (names in spaces, linked devices, recovery contacts), settings (privacy and security, network, storage), and about. A code button shows the user's own code.

### 18 Privacy and security
Seven sharing switches, all off by default: show when I am online, let strangers find me by name, let strangers add me to groups, show my IP address in calls, send read receipts, show when I am typing, allow screenshots of chats. Three phone switches: app lock (on), auto-delete old messages (off), erase after 10 wrong passcodes (off). An "Always on" card lists the four protections that cannot be switched off. A note says data is saved on the phone until wiped, above a red "Wipe everything now" button that needs a confirmation step.

## 7. States the images do not show

Design these in the same system when you build them:

- Empty states for Chats, Chat requests, Spaces and Nearby.
- Permission prompts for Bluetooth, nearby devices, camera and microphone, each with a plain reason.
- Radios switched off, and a person going out of range mid-chat.
- Message sending, sent, delivered, failed, and held for later delivery.
- Transfer paused, failed and completed.
- Confirmation dialogs for Block, Wipe everything, leaving a space, and deleting a chat.
- Loading and error states for joining a space and scanning a code.
