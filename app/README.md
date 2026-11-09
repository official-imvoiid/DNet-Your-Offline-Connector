# DNet app

The Flutter app for Android and Windows. It talks to the Rust core over
FFI and to the radios on each platform: chats, files, spaces, calls,
screen sharing, the Nearby mesh maps and the long-range LoRa radio. The
[top-level README](../README.md) lists what the app does.

## Run it

Flutter and `cargo` must both be on PATH, because building the app also
builds the Rust core and, on Windows, the radio library. See **Build from
source** in the [top-level README](../README.md) for the versions.

```
flutter run -d windows
flutter run -d <android device id>
```

Release builds go to `../dist/`: `flutter build apk --release` writes
`dist/DNet-Android.apk`, and `flutter build windows --release` writes
`dist/DNet-Windows/`.

## Check it

```
cargo build --manifest-path ../core/Cargo.toml
flutter analyze --fatal-infos
```

## Where things are

| Path | What it holds |
|---|---|
| `lib/design/` | Colours, type and radii from the design spec, and the icon set |
| `lib/widgets/` | Shared pieces: buttons, switch, avatar, bars, composer, sheets |
| `lib/shell/` | The tab bar, the two-pane layout on wide windows and the keyboard shortcuts |
| `lib/screens/` | One file per screen, named after the design kit |
| `lib/data/` | `AppState`, the one object the screens read and change, and `Store`, what is kept between runs |
| `lib/core/` | The bridge to the Rust core, and the two things only the operating system knows |
| `lib/radio/` | The radios (Bluetooth, Wi-Fi Direct, local Wi-Fi, LoRa) and the link pump that puts chats ahead of files |
| `lib/calls/` | The call engine and screen sharing |
| `lib/l10n/app_en.arb` | Every piece of interface text |
| `lib/routes.dart` | Every move between screens |
| `lib/version.dart` | The app's version, as `pubspec.yaml` gives it |
| `../core/` | The Rust core: identity, encryption, storage |

## Rules that bind this code

- The icons are generated. Change the design HTML, then run `python tool/gen_icons.py` from the repository root. Do not edit `lib/design/app_icons.g.dart`.
- Interface text goes in `app_en.arb`, never in a widget.
- Radio problems are called "interference" or "link trouble" in anything a user can read.
- The protections on the Privacy screen have no switch, and none may be added. The core has no setting for them either.
- Cryptography lives in the Rust core and uses reviewed libraries. No primitive is written by hand, on either side.
