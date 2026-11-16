# Design

## Context

See proposal.md. SkillPolicy currently owns Skip Recovery deadlines, deduplication and next-track checks; metadata lives in a feature enum and the page addresses one skill directly. The dispatcher already supplies ordered evaluation and success callbacks.

## Goals / Non-Goals

Make individual skills independently implementable and testable without app imports. Preserve existing gameplay and storage. No plugin loader, rule language, new abilities or new UI flow.

## Decisions

- Use `lib/skills/skill.dart` for stable IDs, neutral action events and definition/runtime interfaces; `registry.dart` holds static supported definitions. Individual modules live in named subfolders, initially `skip_recovery/skip_recovery.dart`.
- Skill events contain string player/request identities, a small canonical action enum and elapsed time. The application adapter translates its profile/action types. Importing feature types into skills would recreate coupling; moving the whole feature would not separate responsibilities.
- Definitions own immutable metadata and create fresh runtimes. Skip Recovery owns its duration, deadlines, deduplication and successful-next-track effects. The adapter owns clock access, assignment filtering, dispatcher compatibility and change notifications.
- Policy recovery inspection is generic across registered runtimes. Assignment guards use the active skill's metadata; the page iterates registered definitions and queries per-skill recovery. Icon selection stays in presentation, since Flutter icons must not leak into skill logic.
- Keep `skip-recovery` and storage version 1 unchanged. Replace old imports rather than retaining a competing feature catalog. Verify independent source imports, direct skill behavior, adapter delegation and existing end-to-end tests.

## Risks / Trade-offs

- Neutral action types require explicit translation → exhaustive adapter switch and contract tests.
- Accidental behavior drift during extraction → retain dispatcher/persistence/widget tests and add isolated deadline/deduplication tests.
- Future modules could import app services → enforce dependency direction with an architecture test.

## Migration Plan

No persisted data migration. Deploy the new implementation over existing assignments. Rollback uses the same IDs and format. Fresh policy construction still begins a new runtime session.
