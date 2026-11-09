# Contributing to DNet

Thanks for helping. This file covers how to set up, the rules this code follows and how to send a change.

Bug reports, design feedback and pull requests are all welcome.

## Set up

Follow **Build from source** in the [README](README.md).

## Making a change

1. Open an issue first for anything bigger than a small fix, so the approach can be agreed before you spend time on it.
2. Make a branch from `main` with a short name, such as `fix/nearby-map-crash` or `feature/here-mentions`.
3. Keep each pull request to one change. Small pull requests get reviewed faster.
4. Run the checks before you push:

   ```bash
   cargo clippy --manifest-path core/Cargo.toml --all-targets -- -D warnings
   cargo build --manifest-path core/Cargo.toml
   cd app
   flutter analyze --fatal-infos
   dart format --output=none --set-exit-if-changed lib
   ```

   The same checks run in CI (`.github/workflows/ci.yml`), together with
   `cargo audit` and the Android and Windows release builds.

5. Open the pull request and fill in its template. Say which devices you ran it on.

## Rules this code follows

**Privacy and security**
- Cryptography lives only in the Rust core and uses reviewed libraries. Never write a primitive by hand, on either side.
- An identity needs nothing but a name. Never ask for a phone number, an email address or any other personal data.
- The app makes no network calls of its own. Bundle data and fonts; never fetch them.
- Never mark someone as verified from data that came only over the radio link, because a man-in-the-middle could control that link. Being seen over Bluetooth is not proof.
- Never trust a radio's own encryption (Wi-Fi Direct's password, Meshtastic's channel key). Everything on the air is a core envelope or a signed handshake.
- Every parser that reads bytes from a radio must be bounded and must never throw.
- Anything a stranger in range can make this device do (pass on, link, connect) must have a limit.
- Names other people chose go through `safeName` before they are shown or compared.
- The protections on the Privacy screen have no switch, and none may be added.
- Every dependency ships inside an app whose job is to keep messages private. Add one only when it's worth reviewing, and justify it in a comment, like the existing ones in `app/pubspec.yaml` and `core/Cargo.toml`.

**Text the user reads**
- Interface text goes in `app/lib/l10n/app_en.arb`, never in a widget.
- If a string mentions a phone, it needs PC wording too: `{device, select, pc{…} other{…}}`.
- Radio problems are called "interference" or "link trouble".

**Generated files** (don't edit these by hand)
- Icons: change the design HTML, then run `python tool/gen_icons.py` from the repository root. It writes `app/lib/design/app_icons.g.dart`.
- Emoji data: `python tool/gen_emoji.py` writes `app/lib/data/emoji_data.g.dart`.
- Built-in stickers: `python tool/gen_stickers.py` draws `app/assets/stickers/`.

**Design**
- The design is in `design/design-spec.md`, and the screen images are in `design/screens/`.
- On a wide window the app fills the window: no page-wide empty margins.

**Platforms**
- If a platform can't do something, hide that feature on that platform and say why. Don't show a switch that does nothing.

## Code style

- Dart: `dart format` your files, and keep `flutter analyze` clean.
- Rust: format only the files you changed, with `rustfmt <file>`. `cargo fmt` reformats the whole crate and makes unrelated diffs.
- Line endings are LF everywhere (`.gitattributes` handles this).
- Match the comment style around your code: short comments that explain why, not what.

## Commit messages

Write a short summary line in the present tense, such as "Keep chats ahead of file pieces on Bluetooth". Add a body if the reason isn't obvious.

## Be kind

Be respectful and patient in issues, reviews and discussions. Criticise code, not people. Harassment of any kind isn't welcome here.
