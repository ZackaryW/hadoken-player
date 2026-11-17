# Spec Delta

## ADDED Requirements

### Requirement: Optional declared combo filters
A declared combo listener SHALL receive completed attributed combos matching its player scope and activation state. Omitting its combo filter SHALL match any such combo; supplying a filter SHALL match only that complete sequence. Other trigger types SHALL NOT receive combo events.

#### Scenario: Unfiltered cross-player listener
- **WHEN** P1 equips an active all-player combo listener without a filter and P2 completes a valid runtime combo
- **THEN** the listener receives one event retaining P1 as owner and P2 as actor

#### Scenario: Filter and activation remain enforced
- **WHEN** a combo listener is disabled, its scope excludes the actor, or its explicit filter does not match
- **THEN** it receives no callback

## MODIFIED Requirements

### Requirement: Manual force skip
An equipped Force Skip SHALL use its owner's saved one-to-five-stroke macro to request next track at effort 100, with activation effort 100. It SHALL use ordinary effort reconciliation and playback validation. Duplicate delivery within the bounded retention window SHALL execute at most once; failures and end-of-queue no-ops SHALL not be reported as a successful skip.

#### Scenario: Override commitment
- **WHEN** the owner completes Force Skip's macro during Song Commitment
- **THEN** one next-track request at effort 100 overcomes the effort-90 block

#### Scenario: Strongest tie
- **WHEN** another valid restriction blocks next track at effort 100
- **THEN** Force Skip is denied because ties block

#### Scenario: Inactive macro
- **WHEN** the skill is removed or belongs to another player
- **THEN** the former owner's macro cannot activate it
