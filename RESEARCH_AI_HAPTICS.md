# AI-Enabled Haptics — Research

> Replacing the FFT/spectral-flux pipeline with models that **understand** what's happening in the video, not just what frequencies are loud.

This document inventories the techniques, recently-published models, and on-device frameworks that can lift HapticVideoApp's haptic generation from a DSP heuristic to a semantic, multimodal system. It ends with a phased roadmap that's realistic for an iOS app shipping today.

---

## 1. What the app does today (the baseline)

`AudioAnalyzer.swift` implements a clean classical pipeline:

| Stage | Implementation |
|---|---|
| Windowing | 2048-sample Hann window, 512-sample hop (~11.6 ms / 23.2 ms at 44.1 kHz) |
| Spectrum | `vDSP` FFT → magnitude → dB-scaled |
| Features | RMS energy, 5-band energy (subBass / bass / lowMid / mid / high), spectral flux, spectral centroid |
| Onset | Adaptive threshold (`mean + 1.5σ`) + local-max peak picking on spectral flux |
| Event mapping | Hard-coded band → type table (subBass → continuous, bass → impact, mid/high → transient) |
| Event placement | Onset frames + top-30% RMS frames, 100 ms cooldown, deduplicated within 30 ms |

This is solid for *energy*-driven content (music with a strong beat, action with explosions). It's blind to **semantics**:

| Scene in the video | What current pipeline does | What it should do |
|---|---|---|
| Dialogue spoken over a bass-heavy score | Fires `impact` haptics on every consonant because of bass-band leakage from the score | Suppress haptics during dialogue, ride the score in the background |
| Punch landing in an action scene | Sometimes fires a `transient` because of cymbal/whoosh accompaniment, but misses the punch itself if it's body-on-body (low-onset) | Strong `impact` haptic exactly on the punch land frame |
| Glass shattering | Fires a `transient` (correct) but uniform intensity regardless of "how big" the break feels | Sharp transient with intensity proportional to visual debris/score |
| Footstep on a quiet shot | Often missed (RMS too low, no flux peak) | Soft `transient` per step |
| Continuous rain | Fires nothing or fires a noisy stream | Subtle, evenly-modulated `continuous` |
| Slow-motion explosion | Fires multiple high-intensity impacts during the slowed audio | One sustained `continuous` building to a `transient` peak when impact returns to real-time |

The gap is **semantic understanding**. Every cell in that "should do" column requires the system to know *what is happening*, not just *what frequencies are present*.

---

## 2. Approach landscape

The literature splits into four families. Each family solves a different sub-problem; the strongest production system would compose them.

### Family A — On-device audio classification (semantic tagging)

Replace "the bass band is loud" with "a kick drum is hitting now" or "a glass break occurred now."

| Option | Notes | Ship cost |
|---|---|---|
| **Apple SoundAnalysis + built-in classifier** | Apple ships a CoreML model recognizing ~300 sound classes (`SNClassifySoundRequest`) and the framework handles channel mapping, resampling, and reblocking for you. Runs entirely on-device. | Zero — already in iOS |
| **YAMNet via Core ML** | Google's 521-class AudioSet model, converted to Core ML. Public, well-documented, ~3 MB. | Bundle a model, ~3 MB |
| **PANNs (Cnn14_DecisionLevel)** | Larger AudioSet model, frame-level outputs, better at timestamped events than YAMNet. Convertible to Core ML. | Bundle ~80 MB, slower |
| **Custom MLSoundClassifier (Create ML)** | Train your own classifier on a small set of haptically-relevant categories (kick / snare / glass / impact / dialogue / silence). 5–10 minutes per class needed for a usable model. | Training data collection |

**Direct win for our app:** swap the rigid band→type mapping (`AudioAnalyzer.FrequencyBand.hapticType`) for "if the SoundAnalysis classifier says *gunshot* with high confidence, emit `transient` regardless of which FFT band is loudest." This single change kills the worst false positives (dialogue, score bleed).

### Family B — Music-specific deep learning

Strictly more accurate than spectral-flux for any musical content.

| Model | What it does | Why it helps |
|---|---|---|
| **BeatNet** | CNN+RNN joint beat & downbeat tracker | Beat-aligned haptics on music videos — much tighter than energy-onset alignment |
| **madmom** | Classical + DL onset & beat tracking library | Reference implementation; not iOS-portable directly, but the trained weights are |
| **Demucs (HtDemucs)** | Source separation: drums / bass / vocals / other from a stereo mix | Run onset detection *per stem* — drum stem gives clean impact onsets, vocals stem tells you to suppress haptics |
| **Spleeter** | Lighter source separation, faster | Same idea, less faithful |

**Concrete value:** "haptics on every drum hit, silence on every vocal phrase" is a single Demucs+onset pipeline and would dramatically improve any music-video output.

### Family C — Direct audio → haptic learned models

A whole-pipeline replacement. Audio in, haptic event stream out, trained end-to-end on human preferences.

| Model | Architecture | Training | Status |
|---|---|---|---|
| **Sound2Hap** (CHI 2026) | CNN autoencoder | 4,000 audio-vibration pairs with human ratings on Haptic Experience Index (HXI) | Published Jan 2026; outperforms 4 signal-processing baselines |
| **GAN-based vibrotactile generation** | Generator/discriminator on texture images | Texture datasets | Older, image-conditioned, less applicable to video |
| **Multimodal multitask DL** (Nature Sci Reports 2024) | Joint audio + haptic generation | Stylus interaction dataset | Domain-specific (digital pen), but the joint-output architecture is reusable |

Sound2Hap is the most directly relevant. Its weights and training data are not yet public; once they are, this becomes the single biggest unlock — replace the entire `AudioAnalyzer.generateHapticEvents` function with one forward pass.

### Family D — Video understanding (visual motion → haptic)

Use the *visual* channel, not the audio channel. Essential for silent video and for events that happen on-screen but not audibly.

| Approach | What it does | iOS path |
|---|---|---|
| **Vision framework — `VNGenerateOpticalFlowRequest`** | Per-pixel motion magnitude/direction | Built into iOS; cheap; gives a per-frame "how much is the screen moving" signal |
| **Saliency requests (`VNGenerateAttentionBasedSaliencyImageRequest`)** | Where the viewer is likely looking | Reduce false positives — only haptic-react to motion in salient regions |
| **Scene classification (Vision)** | Action / nature / indoor scene tags | Bias the haptic budget by genre |
| **VideoMAE / TimeSformer / SlowFast** | Action recognition; outputs verbs (e.g., "throwing", "punching") | Larger, needs Core ML conversion, but produces *semantic* events |
| **HapticLens (CHI 2026)** | Spatially-localized motion → vibrotactile generation, explicitly designed for "video → haptic" with arbitrary content | The most directly applicable published research. Open-source GUI; algorithms are vision-only and could be ported |

**Killer combo for our use case:** optical-flow magnitude + saliency + audio onset. A "punch land" is high optical flow at the saliency centre coincident with an audio onset.

### Family E — Multimodal foundation models

Skip building a custom system and let a general-purpose model do scene-by-scene understanding.

| Model | Inputs | Outputs | Notes |
|---|---|---|---|
| **Gemini 2.5 Pro / Flash** | Full video (up to ~hours, 1 fps default, configurable) | Structured JSON with `MM:SS` timestamps | The native video-understanding model with the strongest timestamped-event performance. Returns scene segments, action labels, and free-form annotations at timestamps |
| **Claude 4.x with vision** | Frame samples + audio transcript | JSON | Strong at structured output; sample frames yourself, send 1 fps |
| **GPT-4o / GPT-4.1** | Frame samples + audio | JSON | Comparable, slightly weaker on long video |
| **CLAP** (Contrastive Language-Audio Pre-training) | Audio + text prompts | Similarity score | Lets you ask "is this audio more like [punch/footstep/glass]?" without training |
| **ImageBind / VideoCLIP** | Joint image-audio-text embedding | Embedding vector | Use as a feature extractor that then drives a small head |

**Prompted LLM pipeline (works today, no training):**

```
1. Extract video → 1 fps frames + audio
2. Send to Gemini 2.5 Pro with a prompt:
     "For this video, list every moment that should trigger a haptic.
      Output JSON: [{time:'MM:SS.s', type:'tap'|'beat'|'hold',
                    intensity:0..1, sharpness:0..1, duration_s:0..2,
                    reason:'...'}]"
3. Parse the JSON, render as HapticEvent[]
```

This is the **fastest path to "AI-enabled" haptics that actually understand the video**. Costs ~$0.01–$0.10 per video at current Gemini Flash pricing; ~3–10 s latency for a 30 s clip.

### Family F — Hybrid (the realistic recommendation)

The best system is layered, not a single replacement. Sketch:

```
                              ┌─ optical flow (Vision) ──┐
                              │                          │
   Video ─┬─ frames ──────────┤  saliency (Vision) ──────┤
          │                   │                          │
          │                   └─ action labels (VideoMAE)┤
          │                                              ▼
          │                                       ╔═══════════════╗
          │   ┌── beat / downbeat (BeatNet) ────► ║   Fusion +    ║
          │   │                                   ║   Conflict    ║
          └─ audio ── ┬─ source separation (Demucs)───────► ║ Resolution    ║──► HapticEvent[]
                     │                              ║   (small NN   ║
                     │                              ║   or rules)   ║
                     └─ class labels (SoundAnalysis)║               ║
                                                    ╚═══════════════╝
                                                          ▲
                                                          │
                                              (optional) LLM verifier:
                                              "review and prune"
```

Each lane in the bus is independently useful; turning any one on improves output over today's DSP baseline.

---

## 3. Comparison: cost, privacy, latency, dependency

| Approach | Per-video cost | Latency (30 s clip) | Privacy | Net new dependency | Quality lift vs current |
|---|---|---|---|---|---|
| **SoundAnalysis (Apple)** | $0 | ~real-time on device | On-device | None — built into iOS | Removes dialogue/score false positives |
| **YAMNet via Core ML** | $0 | ~real-time | On-device | +3 MB model | Same as above, more classes |
| **Demucs source separation** | $0 (on-device with CoreML port) | 0.5–2× real-time | On-device | +60 MB model | Big lift on music videos |
| **BeatNet** | $0 | real-time | On-device | +5 MB model | Tight beat alignment |
| **Sound2Hap** (when weights released) | $0 | real-time | On-device | model bundle | Replaces whole `generateHapticEvents` |
| **Vision framework (optical flow + saliency)** | $0 | real-time | On-device | None | Catches visual-only events |
| **VideoMAE / TimeSformer** | $0 | 5–15 s | On-device | +200 MB model | Adds semantic actions |
| **Gemini 2.5 Pro (video)** | ~$0.02 / 30 s | 3–10 s | Cloud (Google) | API key | Full semantic understanding; today's best ROI |
| **Claude + vision (frames)** | ~$0.03 / 30 s | 5–15 s | Cloud (Anthropic) | API key | Strong structured-output reliability |

---

## 4. Recommended roadmap

Three phases ordered by quality-per-effort. Each phase ships independently and improves output measurably.

### Phase 1 — Drop-in semantic gate (1–2 weeks, on-device, $0)

Add Apple's `SoundAnalysis` + Vision optical flow to the existing pipeline as a *filter*, not a replacement.

- Run `SNClassifySoundRequest` (built-in classifier) over the same audio buffer in parallel with the FFT.
- Maintain a frame-aligned `Set<String>` of active class labels.
- In `generateHapticEvents`, before emitting an event at time `t`, check: *what is happening at `t` according to the classifier?*
  - If `speech` or `dialog` with confidence > 0.7 → **drop or attenuate to 0.3× intensity**.
  - If `gunshot`, `glass`, `explosion`, `slam` with confidence > 0.5 → **upgrade event to `transient`/`impact` and boost intensity** regardless of which band was dominant.
  - If `music` with `drum_kit` → keep current pipeline but tighten cooldown.
- Run `VNGenerateOpticalFlowRequest` on 4 fps frames. Compute mean flow magnitude per second.
- If `flow_magnitude > μ + 2σ` and no audio onset within ±100 ms → emit a *visual-only* `impact` (catches silent action: punches with no Foley, etc.).

**Cost:** zero (all built into iOS).  
**Net code change:** ~200 LOC in `AudioAnalyzer.swift` plus a new `VideoMotionAnalyzer.swift`.  
**Risk:** SoundAnalysis has a known iOS 18 bug when the device is locked; mitigate by only running while the app is foregrounded.

### Phase 2 — Cloud "auto-tune" pass (2–3 weeks, opt-in)

Add a "✨ Auto-tune with AI" button on the editor that calls Gemini 2.5 (or Claude) to post-process the Phase-1 result.

- After Phase-1 generates an initial `[HapticEvent]`, render the video + the JSON event stream into a prompt:
  > "Here is a video and a draft haptic timeline. Identify events that feel wrong (timing off, intensity miscalibrated, missing key moments) and return a corrected JSON."
- Receive corrected events, diff against the original, present as a non-destructive suggestion the user can accept all / cherry-pick.
- Persist the LLM's `reason` strings as metadata so the editor can show "*added — explosion at 0:12*" next to events.

**Cost:** ~$0.02–$0.10 per call (Gemini Flash); free for the user if you swallow the cost, or BYO API key in settings.  
**Net code change:** new `AIHapticService.swift`, prompt-engineering work, JSON schema definition.  
**Risk:** privacy (uploads video to a cloud provider) — make it opt-in and explain clearly.

### Phase 3 — Custom on-device model (months, optional)

If usage volume warrants it, train a small custom model on user-collected haptic-edit data and ship it via Core ML.

- Log (anonymously, opt-in) tuples of `(audio_features, video_features, final_user_edited_events)`.
- Train a transformer-decoder that emits `HapticEvent[]` token-by-token (architecture is small enough to live in Core ML at ~30 MB).
- Or wait for **Sound2Hap** weights to be released and port them to Core ML.
- Ship as the default generator; keep Phase 1 as fallback.

**Cost:** training time + storage.  
**Risk:** dataset quality; need a careful UX for the opt-in.

---

## 5. Phase-1 implementation sketch

Concrete starting point for the engineering team — turn this into a PR.

### 5.1 New file: `Services/SoundClassifier.swift`

```swift
import SoundAnalysis
import AVFoundation

@MainActor
class SoundClassifier: NSObject, SNResultsObserving {
    private let analyzer: SNAudioFileAnalyzer
    private var hits: [(time: Double, label: String, confidence: Double)] = []

    init(audioFile: AVAudioFile) throws {
        self.analyzer = try SNAudioFileAnalyzer(url: audioFile.url)
        super.init()
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 600)
        request.overlapFactor = 0.5
        try analyzer.add(request, withObserver: self)
    }

    func classify() async -> [(time: Double, label: String, confidence: Double)] {
        await withCheckedContinuation { cont in
            analyzer.analyze { _ in
                cont.resume(returning: self.hits)
            }
        }
    }

    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let cr = result as? SNClassificationResult else { return }
        let top = cr.classifications.prefix(3)
        for c in top where c.confidence > 0.4 {
            Task { @MainActor in
                self.hits.append((cr.timeRange.start.seconds, c.identifier, c.confidence))
            }
        }
    }
}
```

### 5.2 New file: `Services/VideoMotionAnalyzer.swift`

```swift
import Vision
import AVFoundation

struct MotionSample { let time: Double; let magnitude: Float }

class VideoMotionAnalyzer {
    func analyze(asset: AVURLAsset, fps: Double = 4.0) async throws -> [MotionSample] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let duration = try await asset.load(.duration).seconds
        let count = Int(duration * fps)
        var samples: [MotionSample] = []
        var prevPixelBuffer: CVPixelBuffer?

        for i in 0..<count {
            let t = Double(i) / fps
            let cm = CMTime(seconds: t, preferredTimescale: 600)
            let cg = try await generator.image(at: cm).image
            let pb = cg.toPixelBuffer()
            if let prev = prevPixelBuffer {
                let req = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: pb, options: [:])
                let handler = VNImageRequestHandler(cvPixelBuffer: prev, options: [:])
                try handler.perform([req])
                if let obs = req.results?.first as? VNPixelBufferObservation {
                    samples.append(MotionSample(time: t, magnitude: meanMagnitude(obs.pixelBuffer)))
                }
            }
            prevPixelBuffer = pb
        }
        return samples
    }

    private func meanMagnitude(_ pb: CVPixelBuffer) -> Float { /* sum √(dx²+dy²) over the buffer */ 0 }
}
```

### 5.3 Modification in `AudioAnalyzer.generateHapticEvents`

```swift
// Inject the new context
func generateHapticEvents(
    from frames: [AudioAnalysisFrame],
    videoDuration: Double,
    soundHits: [(time: Double, label: String, confidence: Double)] = [],
    motion: [MotionSample] = []
) -> [HapticEvent] {
    // ... existing loop, but before `events.append(event)`:

    // 1. Suppress during dialogue
    if isLabelActive("speech", at: frame.time, in: soundHits, confidence: 0.7) {
        continue
    }

    // 2. Upgrade for known impact classes
    let highImpactLabels: Set<String> = ["gunshot", "glass", "explosion", "slam", "crash"]
    if let lbl = topLabel(at: frame.time, in: soundHits),
       highImpactLabels.contains(lbl.label), lbl.confidence > 0.5 {
        event.type = .impact
        event.intensity = min(1.0, event.intensity * 1.4)
    }

    // 3. Emit visual-only events on motion spikes that audio missed
    // ... in a second pass after the main loop
}
```

### 5.4 Tests to add

- `SoundClassifier` returns ≥1 `speech` hit when given a dialogue-only WAV.
- `generateHapticEvents` produces 0 events on a 5-second dialogue-only clip with the new gate enabled.
- Motion analyzer returns monotonically-increasing magnitude on a synthetic fade-in-of-motion clip.

---

## 6. Open questions & risks

| Question | Why it matters | Suggested resolution |
|---|---|---|
| **Are Sound2Hap weights / training data public?** | Determines whether Phase 3 needs custom training or can use an off-the-shelf model | Email the authors; check the project page for releases |
| **What's Gemini 2.5's actual timestamp accuracy for sub-second events?** | If it's only ±0.5 s, the LLM pipeline is a coarse pass not a fine pass | Run a small eval: 20 clips, hand-label ground-truth events, measure |
| **Will users tolerate cloud calls for haptic auto-tune?** | Phase 2 viability | Make it opt-in; explain clearly; offer "process locally" fallback |
| **Does optical flow drain battery in long editing sessions?** | UX risk | Cap fps at 2–4; cache results per-video |
| **How do we handle SoundAnalysis's iOS 18 lock-screen bug?** | Reliability | Only analyze while foregrounded; pause when entering background |
| **Should classifier confidence thresholds be user-tunable?** | "Pro" users may want control; novices won't care | Hide behind an "Advanced" toggle, ship sensible defaults |
| **Privacy on cloud paths** | App may handle copyrighted footage | Document clearly; never auto-upload; explicit user action only |

---

## 7. Sources

- [Sound2Hap: Learning Audio-to-Vibrotactile Haptic Generation from Human Ratings (arXiv 2601.12245)](https://arxiv.org/abs/2601.12245)
- [HapticLens: Interactive Vibrotactile Haptic Generation from Spatially Localized Video Motion (CHI 2026)](https://dl.acm.org/doi/10.1145/3772318.3790269)
- [HapticVLM: VLM-Driven Texture Recognition Aimed at Intelligent Haptic Interaction (arXiv 2505.02569)](https://arxiv.org/html/2505.02569v1)
- [A multimodal multitask deep learning framework for vibrotactile feedback and sound rendering (Nature Scientific Reports, 2024)](https://www.nature.com/articles/s41598-024-64376-y)
- [Apple SoundAnalysis — Framework documentation](https://developer.apple.com/documentation/soundanalysis)
- [Apple MLSoundClassifier — Create ML documentation](https://developer.apple.com/documentation/createml/mlsoundclassifier)
- [Apple SNClassifySoundRequest documentation](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest)
- [Apple Vision framework — VNGenerateOpticalFlowRequest](https://developer.apple.com/documentation/vision/vngenerateopticalflowrequest)
- [Gemini API video understanding documentation](https://ai.google.dev/gemini-api/docs/video-understanding)
- [Advancing the frontier of video understanding with Gemini 2.5 (Google Developers Blog)](https://developers.googleblog.com/en/gemini-2-5-video-understanding/)
