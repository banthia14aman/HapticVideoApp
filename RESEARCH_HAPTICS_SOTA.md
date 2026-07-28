# State of the Art: Generating Haptics from Video (web sweep, 2026-07-27)

Three parallel research passes: academic (2020–2026), industry, and design craft.
Full agent reports condensed; every claim carries its source URL.

## The consensus architecture (everyone converged here)

**Amplitude envelope + frequency envelope + transient emphasis points, authored
offline into a sidecar track, played in sync with the media clock.** This is
Lofelt/Meta Haptics Studio's decomposition, Sony's DualSense pipeline, Apple
Music Haptics' architecture, and what MPEG standardized. Our pipeline now
matches it: envelope layer (curves) + accent layer (transients) + AI gate.

## What we already implement (validated by the sweep)

| Practice | Source | Status |
|---|---|---|
| Waveform-following envelope via parameter curves | Lofelt (github.com/Lofelt/NiceVibrations — open source, Rust) | ✅ envelope layer |
| Sidechain-duck bed around transients (masking is physics on one LRA) | Buettner pt.10; vibrotactile masking (pubmed 3746267) | ✅ 25% duck ±80ms |
| Fight habituation: no flat rumble, whitespace is a feature | Meta best practices; Android haptics UX | ✅ adaptation decay τ≈2s |
| Silence-before-impact staging, dynamic range expansion | Returnal (PS Blog); WWDC21 10278 | ✅ awe grading |
| Dialogue/semantic gate; class-based suppression | CHI 2023 sound-classification haptics | ✅ SoundClassifier gate |
| Merge onsets <30–50ms (machine-gun buzz kills crispness) | ACM 3756884.3766050 | ✅ 30ms dedup |
| Pre-scheduled pattern on haptic-server clock, not per-event firing | Apple F1 trailer (Mux teardown) | ✅ advanced players both paths |

## Highest-value upgrades not yet implemented (ranked)

1. **Frequency-shift conversion** (Lofelt/Immersion baseline): sum the audio with
   −12/−24-semitone pitch-shifted copies, band-pass ~250 Hz, envelope THAT —
   preserves rhythmic/pitch structure that pure RMS envelopes lose.
   Patents US10339772 / US9786287 (expired-adjacent prior art, read before shipping).
2. **Perceptual intensity linearization**: Core Haptics intensity is ~quadratic
   in/out — apply ~sqrt correction so 2× audio energy feels 2×.
   (danielbuettner.medium.com "10 things Core Haptics")
3. **Sharpness = spectral centroid mapped to 80–230 Hz** (0.0→80Hz, 1.0→230Hz,
   peak punch at ~0.73 ≈ 160Hz resonance). We partially do this; formalize the map.
4. **Class-specific curated effects**: swap generated transients for hand-designed
   patterns per sound class (gunshot/footstep/engine) via SoundAnalysis labels —
   CHI 2023 showed this beats blind conversion. We have the classifier already.
5. **JND deadband** (VC-PWQ codec, IEEE 9517217): drop curve points below the
   just-noticeable-difference — less buzz-noise, less battery.
6. **HapticLens-style visual haptics** (CHI 2026, dl.acm.org/10.1145/3772318.3790269):
   phase-based motion magnification on a user-selected video region → localized
   vibration. The most on-point "video not audio" paper; read before Phase 3.

## Sync budget (measured research numbers)

- Audio↔haptic JND for impacts: **~24ms**; audio-leading is detected sooner than
  haptic-leading → bias haptics EARLY, never late. (ACM 958432.958448)
- Envelope tolerance is looser: attack ~54ms, decay ~265ms. (arxiv 1906.11571)
- Our feed path now pre-schedules on the haptic server clock (~±10ms) after the
  polling path was measured ~30–70ms early with jitter.

## Strategic notes

- **ISO/IEC 23090-31 (MPEG haptics)**: HJIF (JSON interchange) + MIHS (binary,
  embeds in MP4 as a first-class track). RFC 9695 gives haptics/* a top-level
  media type. Keep our JSON schema convertible to AHAP + HJIF; MP4-embedded
  haptic tracks are where streaming distribution is heading.
  Reference software: github.com/MPEGGroup/HapticReferenceSoftware
- **Apple F1 trailer delivery pattern**: sidecar AHAP URL in the HLS manifest
  (`#EXT-X-SESSION-DATA:DATA-ID="com.apple.hls.haptics.url"`), client syncs to
  AVPlayer time. That's our cloud distribution blueprint verbatim.
  (mux.com/blog/how-apple-made-the-f1-movie-trailer-literally-shake-things-up)
- **Generative models** (HapticGen CHI'25, Sound2Hap arXiv 2601.12245, HapticLDM):
  all server-side, all validate that human-preference data beats fixed DSP —
  the editor-as-labeling-tool thesis. None justify on-device cost today.
- **Nobody owns short-video haptics.** TikTok has nothing real; Netflix's
  Rumble Pak died in 2019 (their finding: impacts delight, constant rumble
  annoys — same as ours).

Full source list in the agent reports (session transcripts); key URLs inline above.
