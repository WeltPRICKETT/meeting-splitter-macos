# Changelog

## 0.1.0 - 2026-07-28

This is a source release. It intentionally does not attach the locally built
application bundle because that artifact embeds a GPL-enabled Homebrew FFmpeg
build. A public prebuilt app will follow after the FFmpeg distribution,
corresponding-source, code-signing, and notarization path is complete.

- Import MP4 meeting recordings through file selection or drag and drop.
- Export MP3 audio at a custom bitrate from 32 to 320 kbps.
- Detect stable presentation pages with Vision feature prints.
- Export full-resolution presentation pages as PNG or JPG.
- Provide three page-detection sensitivity modes.
- Show actionable progress, cancellation, errors, and Finder handoff.
- Package a local Apple Silicon `.app` with an embedded FFmpeg runtime.
