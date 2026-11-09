## What this changes

<!-- One or two sentences. Link the issue it fixes, e.g. "Fixes #12". -->

## How it was checked

- [ ] `cargo clippy --manifest-path core/Cargo.toml --all-targets -- -D warnings` is clean
- [ ] `flutter analyze --fatal-infos` is clean
- [ ] `dart format` changes nothing
- [ ] The app builds for the platforms it touches

**On real devices:** <!-- Which devices did you run it on, and what did you try? -->

## Rules

- [ ] Interface text is in `app_en.arb`, with PC wording wherever it mentions a phone
- [ ] No new network calls, no personal data asked for, no hand-written cryptography
- [ ] Any new dependency is justified in a comment
- [ ] Generated files were regenerated with their tool, not edited by hand
