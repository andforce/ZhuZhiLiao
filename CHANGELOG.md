# Changelog

## 1.0.1 - 2026-08-07

### Refactor

- Reorganize the Android and iOS projects into dedicated platform directories.

## 1.0.0 - 2026-08-05

### Features

- Add a native Android 10+ client built with Kotlin, classic Views, and OpenGL ES 3.0.
- Recreate the toy physics, motion-sensor input, touch fallback, sound, haptics, and four seasonal themes.
- Add anonymous identity, global statistics, personal scores, and the global leaderboard.
- Add Wah Earth with privacy-preserving coarse location cells, clustering, live activity, and multi-voice ambient audio.

### Fixes

- Correct the Android gravity direction after recalibration.
- Align the Android leaderboard bottom sheet, score columns, and personal-rank section with the iOS presentation.
- Preserve Earth audio expiry, mute state, and local activity while switching app lifecycle states.

### Documentation

- Document Android development, testing, privacy behavior, and local release-signing configuration.
