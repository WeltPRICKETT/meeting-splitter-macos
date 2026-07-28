# Changelog

## 0.2.0 - 2026-07-28

- Scan video keyframes first and automatically fall back to one-second sampling
  when keyframe gaps could hide presentation pages.
- Use a lightweight grayscale signature before Vision, so unchanged frames no
  longer pay the cost of a Vision feature-print request.
- Extract MP3 audio and scan presentation pages concurrently.
- Export all confirmed pages through one `AVAssetImageGenerator` batch instead
  of starting a separate FFmpeg process for every page.
- Preserve candidate timestamps at millisecond precision.
- Keep progress monotonic while concurrent media work is running.
- Reduce the measured end-to-end time for a synthetic 120-second, four-page,
  720p recording from 3.44 seconds to 0.72 seconds on the development Mac.

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
