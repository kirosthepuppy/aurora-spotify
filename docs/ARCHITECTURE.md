# Architecture

`AURInjection` checks the host bundle identifier before initializing. It replaces only `MPNowPlayingInfoCenter.setNowPlayingInfo:` and chains the previous implementation, then copies metadata onto the main queue. It observes foreground and key-window notifications to attach an in-app launcher to each active scene. It creates no new overlay window and does not replace Spotify's root controller. Defaults live in `dev.aurora.spotify`.

`AURPlayback` owns the metadata snapshot and receipt time. It extrapolates elapsed time from the published playback rate, clamped to duration. Identical snapshots do not reset the receipt clock. A two-second foreground poll discovers initial metadata; UIKit notifications drive the window lifecycle. Polling stops in the background. A view timer updates the visible lyric line and is invalidated when the player disappears.

The MediaRemote adapter uses `dlopen`/`dlsym`; its absence does not prevent the UI from loading. No private Spotify class names are assumed. The simulator harness compiles the same UI with `AUR_HARNESS`, excluding automatic injection and private playback commands. Missing metadata remains an explicit waiting state. There is no synthetic Spotify session or fallback demo inside the injected tweak.

The player uses native constraints inside a scroll view, including in landscape. The transport surface uses a runtime glass factory when available and material blur otherwise. It never claims to convert Spotify's entire UI to Liquid Glass. Appearance animations respect Reduce Motion when settings are applied. Imported LRC files are atomically saved by SHA-256 of track metadata, not by unsafe filenames or artwork URLs.

The injector edits only verified zero header padding in a thin arm64 Mach-O. It adds an `LC_LOAD_DYLIB`, increments the command count/size, and leaves sections and file length intact. This invalidates old signatures. Packaging is atomic, input-preserving, archive-size bounded, and does not extract archive paths. The tool rejects encrypted main executables, but is not a complete Mach-O security verifier or an extension decryptor. It does not distribute or download Spotify itself outside an explicitly enabled personal CI job.

## Next extension points

- Add a version-specific metadata adapter only after inspecting your own supported binary on-device. Keep private class hooks isolated, version-gated, and optional.
- Word-level lyrics need an enhanced timestamp model, provider licensing, and tests; plain LRC is line-level only.
- Real EQ and vocal separation need an audio pipeline integration. MediaRemote transport commands do not expose Spotify's audio buffers.
- Lock-screen Live Activities need an embedded signed extension and corresponding entitlements. An injected dylib alone is insufficient.
