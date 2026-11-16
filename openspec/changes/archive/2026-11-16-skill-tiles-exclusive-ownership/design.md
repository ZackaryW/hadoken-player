# Design

## Context

See proposal.md for motivation. SkillAssignmentRepository serializes persistent mutations, while SkillControls joins the playback dispatcher queue to guard cooldown edits. The current screen uses a wide row and switch. There is one supported skill.

## Goals / Non-Goals

Keep exclusivity enforced below the UI, preserve atomic persistence, and make assignment visible through tile color and text. No changes to skill effects, audio handling, input bindings or additional catalog entries.

## Decisions

- Add an owner lookup and typed conflict in the assignment domain; check inside its serial mutation queue. UI disabling alone would not cover concurrent callers. Reject ownership conflicts instead of automatically stealing a skill.
- Decode known duplicate IDs in stable P1–P3 order, considering added profiles on repository open. Retain unknown IDs and show recovery feedback. Existing v1 format can represent the normalized state; the next successful edit saves it without adding a startup write failure path.
- Replace the switch row with responsive square tiles. Whole-tile taps toggle assignment; a separate 44dp info control opens the existing description. Assigned tiles use the app's lilac accent and glow, inactive tiles use neutral gray. Text indicates Active, recovery time, or owner. One real skill means one tile in the grid, with no fake filler skills.
- Choose columns from available width and text scale so 360px at 2x uses one column. Keep natural text wrapping and scroll access. Preserve subscriptions and lifecycle refresh.

## Risks / Trade-offs

- Legacy duplicates cannot all remain owners → deterministic recovery and visible notice; unknown identities preserved.
- Ownership may change after rendering → repository remains authoritative, typed conflict refreshes feedback.
- Tiles could clip large text → responsive column count plus layout tests and actual emulator review.

## Migration Plan

Keep the v1 storage format and normalize on read; persist normalized assignments on the next successful edit. Deploy over existing app data. Old binaries could create duplicates again; reinstalling the new build normalizes them on open.
