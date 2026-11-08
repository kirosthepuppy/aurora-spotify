# Device validation

No Spotify or iOS version is certified by this source repo yet. Record the Spotify version/build, iOS version, device, Xcode SDK, signing method, and Aurora commit with results. Do not include tokens, certificates, listening history, or unrelated app data in logs.

1. Run packaging tests and macOS native compilation. Launch the simulator harness; confirm its parser assertions pass, gradients render, and sample lyric lines advance.
2. Package your own decrypted IPA. Verify the app executable contains Aurora's load command and the archive includes `Frameworks/Aurora.dylib`.
3. Re-sign all code with a matching provisioning profile. Install on a test device and confirm Spotify still launches and signs in normally.
4. Start playback using Spotify's own UI. Open the overlay from both the sparkle button and the two-finger gesture. Verify actual song, artist, artwork, duration, and elapsed time. If metadata is missing, mark this version unsupported.
5. Test pause, resume, previous, next, seek, pauses, track boundaries, and returning from background. Verify commands affect the intended player. A command dispatch return value is not proof of playback success.
6. Import valid UTF-8 LRC, malformed text, a file larger than 1 MB, and multiple timestamps. Change songs while the file picker is open; verify lyrics attach to the originally selected song.
7. Test all appearance options, hiding the launcher, reopening with the gesture, persistence across relaunch, Reduce Motion, VoiceOver, large text, and landscape.
8. Confirm the original Spotify home, library, downloads, and player still work after dismissing Aurora. Check behavior with another audio app active and after app termination.

Only claim compatibility for combinations that pass. Full UI replacement, word-level lyric timing, DSP, and Live Activities are outside this initial implementation.
