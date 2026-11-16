## Context

Skill definitions own plain-text metadata in independent Dart modules; PlayerSkillsPage displays that description through the shared message dialog. Effort already has a numeric string representation.

## Goals / Non-Goals

Expose actual effort in existing details without changing execution, storage or tile density.

## Decisions

- Interpolate Effort values into action mentions using `Action (value)`, including Skip Recovery's normal-effort skip and block. This keeps values beside their meaning and avoids a detached legend.
- Add a shared definition details getter that includes a manual skill's activation label and its existing description. Passive skills retain only their description. This avoids skill-specific UI branches or Flutter imports in skill modules.
- Continue using the existing wrapping, scrollable dialog; no new dialog framework or editable priority fields.

## Risks / Trade-offs

Free-text metadata could omit a future action's effort → define the authoring requirement in the spec and verify the shipped skill and injected manual definition. Numbers use Effort values rather than duplicated numeric literals.

## Migration Plan

No persisted changes. Build and install-replace the debug app while preserving emulator data.
