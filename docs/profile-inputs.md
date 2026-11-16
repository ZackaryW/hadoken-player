# Profile inputs

Three fixed slots, P1–P3, each have an editable display name and one optional
combination per action: play/pause, next, previous, forward/back ten seconds and
stop. A display name never changes a slot's identity.

There are three input buttons: Forward, Pause and Backward. Tap and hold give
six stroke types. A binding contains one to five ordered strokes. Only an
identical complete combination is exclusive across all profiles and actions;
shared prefixes are legal. Runtime ownership comes from the matched binding,
independent of the profile being edited.

## Stored document

`hadoken_profiles_v1` is a single JSON document in SharedPreferencesAsync,
independent of Troona playback-session keys. `version: 1` contains `profiles`
(three objects with `id`, `name`, and a `bindings` map from action IDs to ordered
`{button, kind}` objects) and `timing` (`holdMs`, `gapMs`). Enum names are the
version-one stable serialized IDs. Timings default to 600 and 500 milliseconds
respectively, must be positive, and are not part of combination identity.

All writes are serialized, validated against the latest committed catalog, and
published to observers only after persistence succeeds. A failed write preserves
the previous catalog. The uncached preferences API avoids exposing failed writes
through the legacy preferences cache. On load, malformed bindings and every
member of a duplicate-combination group are inactive. Valid unrelated bindings
survive; recovery messages remain visible until the next successful save.

## Timing and matching

A press shorter than 600 ms is a tap; exactly 600 ms or longer is a hold.
Holding lights the button after the threshold, but emits a single stroke only
on release. There are no repeated hold strokes or simultaneous-button chords.
Overlapping presses discard the attempt until all pointers lift. Losing focus
discards held inputs and pending matches. Completed recorder strokes remain in
the draft; changing mode, catalog or shared timing clears that draft too.

For P1 **Forward tap** and P2 **Forward tap → Backward hold**, P1 waits up to
500 ms after Forward is released. A Backward down at 499 ms protects the
continuation while it is held, even if that hold lasts several seconds. On
release, P2 matches and P1 does not run. A down at exactly 500 ms comes after
expiration: P1 already wins, and that new down starts a fresh attempt.

A terminal combination fires immediately. If a continuation mismatches, the
longest complete prefix wins; the mismatching stroke is discarded rather than
replayed as a second action. Without a complete prefix, timeout/mismatch simply
resets. Cancellation never runs a deferred prefix. Five strokes end an attempt.

Recording never matches, dispatches, auto-saves or splits a draft on a long gap.
Practice matches and shows the owner without touching playback. These examples
are exercised with an injected clock in `combo_input_test.dart`.

## Setup and use

Open Settings → Player profiles and combos. Pick P1, P2 or P3 and use Rename
player if desired. Choose Set beside an action, record the buttons and select
Save combo. Undo removes the last stroke; Clear draft starts over; Cancel keeps
the existing saved binding. A sixth stroke is rejected. Duplicate feedback names
the existing profile and action. Shared-prefix warnings explain the delay.

Open combo pad to use saved bindings. Play mode controls the current music;
Practice reports the matching player and action without changing playback.
Recording is also silent. The Pause input button is just an input symbol: it
does not directly pause unless the completed saved combo maps to play/pause.
Change shared timing on the profile page. No keyboard, headset or background
raw-input capture is provided in this version.

## Playback and the Stage 2 seam

`ProfileControls` shares the existing `AudioServicePort` through
`PlaybackCommandsAdapter`. Pages create/dispose only input sessions, never the
audio player. Regular transport, notification controls and automatic advancement
do not enter `PlayerActionDispatcher` and produce no player-attributed outcomes.

A request has a session-unique ID, immutable binding/owner/action and monotonic
recognition time. Ownership is validated and captured from the committed catalog
at arrival. Requests run serially: `PlayerAbilityPolicy.denialFor`, playback,
then `recordSuccess` only on an observed success. Stage 1 uses `AllowAllAbilities`.
Stage 2 can install hardcoded skills here; it is not implemented in this change.
Every ID retains its result for the service session, including denied, no-op and
failure results. Re-delivery never executes or publishes a second outcome.

Profile next/previous commands briefly pause the native player, verify that the
same queue occurrence remains current, then skip and restore the original
play/pause state. This prevents automatic advancement during an awaited operation
from earning player credit. Occurrences use queue indices, so two copies of one
track are distinct. Boundaries are no-ops. Conventional controls keep Troona's
existing fades. A successful skip still counts if restoring play/pause later
fails; the outcome includes a warning. A post-success policy error preserves the
actual playback success and blocks further profile requests until restart, so a
future skill implementation cannot silently continue with inconsistent state.

Outcomes are success, denied, noOp or failure. Gameplay pause uses zero fade.
Seeks also quiesce playback, clamp to the known duration and require the observed
position to equal the target before restoring playback. This prevents ordinary
clock progression near a boundary from being mistaken for a successful seek.
Errors or unchanged playback never report a successful action.
