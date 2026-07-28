# YC Application — Draft (jury-synthesized, 2026-07-26)

> Verdict of the 5-partner jury: 3 ADVOCATE (2 conditional), 2 LEAN-NO-convertible.
> Every juror converged on the same three conditions:
> 1. **Get human evidence tonight** — strangers feeling the demo, real numbers, including the bad ones.
> 2. **Demote "infrastructure" below the fold** — it's the destination, not the pitch. The pitch is the artifact + the test.
> 3. **Never claim what the POC can't back.** The honesty IS the strategy.

---

## One-liner (≤ 15 words)

> **Upload a video; our AI makes your phone vibrate perfectly in sync with it.**

Alternates:
- "We turn any video into something you can feel on your phone."
- "AI watches your video and writes the vibration track, synced frame by frame."

*(No "infrastructure," no "immersive," no "native media layer," no "Dolby for X" in the opener.)*

## What does your company do?

We turn video into touch. Our on-device AI analyzes any video — audio spectrum, sound events, motion — and generates a synchronized haptic track automatically, with a mobile editor for fine-tuning. Tracks export as a portable format and play back through the phone's haptic engine.

Today this is a working iOS proof-of-concept. The goal is the generation API, authoring tools, and cross-platform delivery SDK for haptics as a media track — the tooling layer that MPEG's new haptics standard (ISO/IEC 23090-31) created a slot for, and that nobody has built.

## What have you built so far?

A working iOS app, built solo in a few weeks. You drop in any video; an on-device AI model analyzes it and generates a synchronized vibration track — impacts, engine rumble, bass hits — with no manual work. A mobile timeline editor lets you drag, stretch, and retune each haptic event, then play it back in perfect sync. Tracks export as a portable JSON format that plays on any modern iPhone. It runs entirely on-device: no server, no upload.

## What problem are you solving, and for whom?

Haptics on video is where subtitles were in 2005: the spec exists, the hardware is in every pocket, but authoring cost keeps adoption at zero. Hand-authoring one minute of synced haptics takes hours — separately per platform, because nothing is cross-platform and Android hardware varies wildly across OEMs.

Our first integrator is not "creators" broadly. It's the mobile team at a short-form video app, sports-highlights product, or mobile game studio — 2–5 engineers who want haptic immersion as a differentiator but will never staff a haptics designer. They have video files and a deadline. We give them one API call: video in, portable haptic track out, plus an SDK that renders it correctly across devices.

The POC tested the core technical bet: that AI generation is good enough that the editor is a polish step, not a rescue step. It is — for music and action content. What I don't know yet, and am trying to learn, is which integrator segment feels the pain sharply enough to pay first. That's the next 90 days.

## Why now?

Three things converged in the last 24 months. **Hardware:** every flagship phone now ships a high-fidelity linear actuator, and Apple's Core Haptics plus iOS 18's Music Haptics proved system-level audio-to-touch works — but only as a generic pass. **Standards:** MPEG ratified ISO/IEC 23090-31, so haptics is now a codec-level media track — like subtitles in 2008, the container exists but the content doesn't. **AI:** on-device sound classification and motion analysis are now free and fast enough to generate a first-draft haptic track from any video in seconds. The only missing piece is authoring cost. That's what we collapse.

## What's your unfair advantage?

Honestly: today it's velocity. I built the full loop solo in weeks — on-device generation, a mobile timeline editor, synced playback, a portable track format. No users yet; I won't pretend otherwise.

The durable advantage is what the editor produces as exhaust. Every time a creator fixes the AI's draft — moves a transient, softens an impact, deletes a false positive — we capture the diff between the generated track and the corrected track, aligned to the underlying audio and motion features. That's paired supervision for "what humans wanted vs. what the algorithm did," collected exactly where the algorithm fails. Nobody else has a reason for humans to hand-label haptics at scale, because nobody else made correction the free byproduct of a tool creators already want. The current DSP pipeline is the cold-start; the correction corpus trains its replacement.

## What do you understand that others don't?

Everyone builds haptics as *feedback* — a UI confirmation, a game effect, fired by app logic. We think haptics is *media*: a fourth track alongside video, audio, and captions, authored once and played anywhere. MPEG just agreed — 23090-31 makes it a coded media stream.

Feedback needs an engineer per interaction; media needs a production pipeline and a portable format. Every media type that scaled did it the same way: generation got cheap, editing got accessible, a format let it travel. Haptics has playback hardware in two billion pockets and now a standard — but production still costs a specialist-day per minute of content. Whoever collapses that cost owns the layer. And because "correct" haptics is perceptual, not physical, the winner is whoever accumulates human taste data, not whoever writes the best signal processing.

## Why won't Apple/Google just build this?

They already built their halves — that's the problem I'm solving. Apple has Core Haptics, AHAP, Music Haptics, and the best actuator in the industry. Google has VibrationEffect. What neither has built — in seven years of shipping the primitives — is the layer between them: a cross-platform format, creator tooling, and a pipeline that makes one haptic track play correctly on a Taptic Engine and a mid-range Samsung LRA. Cross-platform portability is anti-strategic for Apple, and Google can't solve actuator inconsistency even on its own OS. Device abstraction across a fragmented fleet is a third-party problem by construction — the same reason Twilio existed despite carriers owning SMS.

If Apple ships haptic video system-wide, that validates the market — and honestly, I'd rather find out in 3 months than 3 years. The bet is that touch tracks need to travel with the video across ecosystems, and a platform owner structurally can't build the neutral layer.

## Why hasn't anyone won this market already?

Someone almost did. Lofelt built the best haptic tooling in the industry, was acquired by Meta in 2022, and was shut down — proof the tooling was worth buying and the market wasn't ready to run as a business. Three things were missing then that exist now: **a ratified standard** (Lofelt had to evangelize a proprietary format device-by-device; I get to build tooling for a settled one), **generation economics** (their unit economics required human designers; AI generation deletes that cost), and **the actuator install base** (the hardware penetration they were waiting for arrived — after they died).

On Immersion Corp: I take the patent portfolio seriously — they've licensed Apple, Sony, and Meta. My mitigation: build on the MPEG standard track rather than proprietary effect libraries, design around aging core claims, and budget for specialist IP counsel before revenue scale, not after the demand letter. It's a cost line, not an unknown.

## What's the biggest risk?

Demand. Nobody on earth has retention data for haptic video — including me. The failure mode is 3D TV: a format people admire in demos and never miss afterward. So I'm testing exactly that, now: same short clips, haptics on vs. off, blind order, on my working iOS build. I measure blind preference ("which one would you rather watch again?") and voluntary replays. If viewers don't prefer or rewatch haptic versions at a meaningful delta, the thesis is dead and I'll know in weeks, not years. Early numbers from strangers go in this application.

*(→ Insert the real numbers from tonight's test here: "X/10 preferred haptics-on for action content, Y/10 for talking-head — that split is the content wedge.")*

## Long-term vision (15 years)

Every screen you watch is deaf to your hands. Two billion phones already contain precision haptic hardware that video simply ignores — the way early film ignored sound. In 15 years, touch is a standard track in video, like audio and subtitles: generated by AI, tuned by creators, played everywhere — phones, wearables, cars, devices that don't exist yet. Companies like Dolby shaped how the world hears; we want to build the tools that shape how digital experiences feel.

## Founder video script (30–45s)

**[0:00–0:10] — Founder to camera, phone in hand, natural light.**
"I'm Aman — engineer, ex-MathWorks. Apple's F1 haptic demo gave me chills, and then a question I couldn't shake: audio went mono, stereo, surround. Why is touch still mono? So I built this."

**[0:10–0:30] — Over-the-shoulder on the real device. Film the phone, not a screen recording.**
"Drop in any video —" *(show it)* "— on-device AI generates a synchronized haptic track in seconds —" *(scrub the timeline editor)* "— and it plays back in sync."

**CUT TO: a stranger holding the phone, clip playing. Hold on their face — the flinch, the grin. Let it breathe 3 seconds. Their unscripted words.**

Voiceover: "That reaction is why I stop strangers. [X] of ten prefer the haptic version blind." *(Use the real number. If it's six, say six.)*

**[0:30–0:40] — Back to founder, tight.**
"Every phone already has this hardware. Nobody's built the format, the generation engine, or the tools. That's what we're building."

---

# Tonight's checklist (before the July 27 deadline)

1. **Hours 0–4 — The 10-stranger blind A/B.** Two 20-second clips on the POC: one high-texture (F1 onboard / dunk), one ordinary (talking head — the honest case). Cafe or campus. Both versions each, order randomized. One question: *"Which version would you rather watch again?"* Log: blind preference X/10 + unprompted physical reactions Y/10. Film with consent. Report the honest split — "8/10 on F1, 4/10 on talking head" is a *better* answer than "everyone loved it."
2. **Hours 4–6 — The replay test.** Hand 5 people a 3-clip mini-feed, say "play with it," shut up. Count voluntary replays of haptic vs. non-haptic clips. Behavior beats opinion.
3. **Hours 6–8 — One creator, one quote.** Any friend-of-friend creator >10k followers. Let them feel their own genre with haptics. One question: *"If adding this to your next post was one tap, would you?"* Verbatim answer — including the hesitation.
4. Everything above doubles as B-roll for the video. **No new code tonight.**

# Jury conditions & dissents (know these before the interview)

| Juror | Verdict | Their interview test for you |
|---|---|---|
| Maya (infra) | ADVOCATE | "Why aren't you Lofelt 2.0 / an Immersion licensee with no margin?" — wants: standard changed the game, patent map read, moat = customers' shipped content breaks if SDK is removed. Bonus: volunteer that the consumer app dies the day the first API customer signs. |
| Dev (AI) | ADVOCATE (cond.) | "Walk me through the training pair for the correction model — input, target, loss, and what you do when two creators correct the same clip differently." Averaging corrections = mush; disagreement is style, condition on it. DSP = cold-start, never the product. |
| Sofia (consumer) | ADVOCATE (cond.) | "How many people outside your circle have felt it, and what did the shrugs tell you?" — wants a number + the unflattering detail + how the negative signal became the content wedge. |
| Rui (hardware) | LEAN NO → flips | "Play your track on a Pixel and a $250 Redmi — what breaks at the actuator level and what does your transcode layer do?" — wants: narrowband LRA rise/ring-down physics, device capability profiles, perceptual-equivalence mapping, not "the standard handles it." |
| JB (skeptic) | LEAN NO → flips | Q1 currently kills the application: zero human data points. Fix = tonight's checklist. Also: delete the word "moat," demote "infrastructure" to one sentence, one Dolby reference max. |
