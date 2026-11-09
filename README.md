# Aurora for Spotify

An independent native iOS UI tweak inspired by the idea of a glass music player. Objective-C, UIKit, a self-contained injected dylib, and a GitHub Actions build workflow. No web app, Theos, Substrate, or jailbreak is required by the source design.

**Status: experimental source repo, not a verified Spotify release.** Packaging tests pass on Linux. Native compilation, simulator execution, signing, and behavior inside Spotify have **not** been verified in this workspace. Run the included macOS workflow and test your own IPA on-device before relying on it. No particular Spotify version is claimed compatible.

## Included

- Full-screen native player launched from a floating sparkle button inside Spotify
- Two-finger, one-second long press as an alternate launcher
- Glass transport panel: runtime `UIGlassEffect` when available, dark material blur otherwise
- Album artwork, title, artist, elapsed time, duration, and experimental transport controls
- Artwork-derived color, animated gradients, three accents, true black, and Reduce Motion support
- Local `.lrc` import, timestamp highlighting, multiple timestamps per line, offsets, and tap-to-seek
- Settings stored in a separate defaults domain inside the app sandbox
- arm64 dylib build script, conservative IPA injector, and a simulator UI harness
- CI jobs for packaging tests and native compilation; optional unsigned IPA artifact

This adds a separate player overlay. It does not rebuild Spotify's home, search, or library screens. Lyrics are line-synced, not word-synced. Automatic lyric providers, EQ/audio DSP, vocal separation, lock-screen extensions, and a shader marketplace are not implemented. Nothing here changes Spotify account entitlements or streaming access.

## Build on a Mac

Install Xcode, launch it to finish setup, and select its developer tools:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
make test
make build
```

Requirements: macOS, Xcode with iPhoneOS SDK, Python 3, and Make. Output: `build/Aurora.dylib` for arm64, deployment target iOS 16.0. A recent SDK is recommended; glass is detected at runtime and does not require SDK 26 to compile.

## Build with GitHub Actions

1. Create your own repository from this source and push the `main` branch.
2. Open **Actions → Build Aurora → Run workflow**.
3. Download `Aurora-native` for the dylib and simulator harness.

For an unsigned IPA, configure a repository Actions secret called `SPOTIFY_IPA_URL` containing a direct HTTPS download URL to **your own decrypted Spotify IPA**, then run the workflow with `package_ipa` enabled. The URL is supplied as a secret, not a public workflow input. Use a private repository: workflow artifacts inherit repository access. The personal IPA artifact expires after one day. No Spotify app or signing credentials are included in this repo.

## Package your own IPA locally

```sh
make package IPA=/absolute/path/to/Spotify.ipa
```

Or, if you already built the dylib:

```sh
python3 scripts/package_ipa.py \
  --ipa /absolute/path/to/Spotify.ipa \
  --dylib build/Aurora.dylib \
  --output build/Spotify-Aurora-unsigned.ipa
```

The input must be a decrypted, thin arm64 Spotify app (`com.spotify.client`). The packager adds `@executable_path/Frameworks/Aurora.dylib` to the executable only if there is sufficient zeroed Mach-O header padding. It preserves executable offsets and ZIP metadata, removes stale signature resources/provisioning, and leaves the original IPA unchanged. It does **not** decrypt or sign the app. Universal/fat inputs, malformed binaries, and insufficient padding are rejected rather than rewritten.

Sign the resulting IPA with your preferred iOS signing tool and your own provisioning credentials. The signer must re-sign all nested code, including the new dylib and any extensions, and provision the app correctly. Existing Mach-O signatures become invalid after injection. Signing failures and extension entitlements depend on your input IPA and signer. Aurora loads when the bundle identifier is `com.spotify.client` or the app executable is still named `Spotify`, so signers that assign a new bundle identifier are supported.

## Use on-device

Start Spotify and play a song. Tap **✦** near the bottom-right, or hold two fingers on the screen for one second. Open the sliders icon for appearance settings. Turning off the floating launcher leaves the gesture available. Restart Spotify if a window was created before Aurora loaded.

Choose **Import synced lyrics (.lrc)** while the target song is playing. Files must be UTF-8 and smaller than 1 MB. The importer remembers the song selected when the file picker opened. Imported lyrics remain local, keyed by title, artist, and album. No network lyrics service is contacted.

```lrc
[ar:Your artist]
[ti:Your song]
[offset:0]
[00:00.00]The first line
[00:05.50]The second line
[00:10.00][00:20.00]A repeated line
```

## Simulator harness

```sh
make harness
# Start an iPhone simulator in Xcode, then:
xcrun simctl install booted build/AuroraHarness.app
xcrun simctl launch --console booted dev.aurora.harness
```

The harness supplies fictional metadata and original sample lyric text. It exercises native UI, settings, line highlighting, and LRC parser assertions without Spotify. It plays no audio and disables MediaRemote controls. Simulator compilation is part of CI; harness execution is a separate step.

## Integration limits

Metadata comes from `MPNowPlayingInfoCenter` inside Spotify, intercepted through its public setter. If a Spotify version publishes metadata through another path, the overlay will stay in its waiting state. Playback commands and seeking use optional dynamically resolved private MediaRemote symbols. Their availability and behavior vary with iOS and signing; they can fail or affect the system's active player. The overlay reports failures but a successful command dispatch does not prove playback changed. Use Spotify's original controls when necessary.

Before calling a version supported, follow [the device validation checklist](docs/DEVICE-VALIDATION.md). See [the architecture](docs/ARCHITECTURE.md) for adapter and extension points.

## Source map

| Path | Purpose |
| --- | --- |
| `Sources/AURCore.m` | Preferences, LRC parsing, metadata, transport adapter |
| `Sources/AURPlayer.m` | Native player, lyrics importer, appearance settings |
| `Sources/AURInjection.m` | Scoped bootstrap, metadata setter interception, launcher |
| `scripts/build.sh` | Native arm64 dylib compilation |
| `scripts/package_ipa.py` | Standalone IPA validation and load-command injection |
| `Harness/` | iOS simulator demo and parser assertions |
| `tests/` | Real binary-layout and archive packaging tests |

## License and attribution

Aurora is distributed under the repository’s GNU AGPL v3 license; see LICENSE. This project includes no Chroma source or assets and is not a Chroma fork. Chroma's current source license restricts modifications and redistribution: [upstream license](https://github.com/skopevoj/spoti.pw/blob/main/LICENSE). Spotify and Chroma belong to their respective owners; this independent project is not affiliated with either.
