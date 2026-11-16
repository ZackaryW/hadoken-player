# Proposal

## Why

The independent skill contract currently supports action eligibility and successful-action cooldown effects only. The requested game mechanics need explicit capabilities for queue changes, audio effects, cross-player restrictions, temporary input changes and macro activation/listening.

## What Changes

- Extend independent skill contracts with typed capability requests and outcomes, routed through application adapters rather than direct app-service imports.
- Support adding/removing song occurrences in the current playback loop, selected future loops or a range of future loops.
- Support live noise and two-song mixing effects, coordinated with the existing background playback session.
- Support targeted action restrictions against other players or all players.
- Reconcile actions and restrictions using code-defined effort: normal levels 0–99, -1 as infinite minimum and 100 as infinite maximum. Higher effort wins; ties block. Route skill-generated playback actions through the same reconciliation.
- Support temporary effective-combo overrides for other players with expiry, restoration and conflict handling.
- Support custom manual activation macros and skill-controlled listening macros that observe any player's runtime combos, using the existing six tap/hold input types and one-to-five-stroke limit.
- Preserve predefined code-owned skill behavior, exclusive skill ownership, concise tile UI and the independent `lib/skills/` boundary.

## Capabilities

### New Capabilities

None proposed; extend the existing cohesive capability boundaries.

### Modified Capabilities

- `player-skills`: capability requests/results, targets, effect lifetimes and activation/listening contracts.
- `player-actions`: ordered skill activations, attributed skill-generated playback, effort reconciliation, cross-player restrictions and capability execution outcomes.
- `audio-playback`: current/future-loop queue editing and coordinated temporary mixing effects.
- `input-recognition`: manual/listening macro recognition and temporary effective bindings.
- `player-profiles`: macro ownership/configuration and saved versus temporary bindings.

## Impact

`lib/skills`, the feature skill adapter, action dispatcher, input recognizer/profile binding views, audio port/adapter and background service lifecycle. The current queue has one playback cycle; the audio adapter owns one decoder; input matches currently resolve only saved playback actions. These are real integration changes, not empty capability methods.

The upstream [just_audio documentation](https://pub.dev/packages/just_audio#working-with-multiple-players) supports simultaneous players, and [setPitch](https://pub.dev/documentation/just_audio/latest/just_audio/AudioPlayer/setPitch.html) provides pitch adjustment. This supports investigating layered audio with the existing backend; it does not establish sample-aligned mixing or correct background/interruption behavior in this app. Those need bounded implementation validation before claiming support.

The user confirmed current and future loop targets, cross-player listening, and the existing six input types with the five-stroke limit. This change provides capability implementations and developer-facing contracts; it does not introduce a configurable rule engine or invent an additional catalog of gameplay skills.
