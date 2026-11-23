# Architecture decision records

An architecture decision record (ADR) is a short document that states one decision that shapes the
code base, why it was made, and what follows from it. ADRs exist so that code comments, tests and
pull requests can point at a stable, public reason ("see ADR 0002") instead of repeating it or
citing a private note.

An ADR records what the code on `main` does. It is written from the code and the docs, cites the
files that carry the decision, and is kept true: when the decision changes, a new ADR supersedes
the old one, and the old one is marked `Superseded by NNNN` instead of being rewritten.

## Numbering and file names

- Four digits, in the order the records are added: `0001`, `0002`, ... Numbers are never reused.
- File name: `NNNN-short-title-in-kebab-case.md`.
- Status is one of `Proposed`, `Accepted`, `Superseded by NNNN`, `Deprecated`.

## Template

```markdown
# NNNN. Title in a few words

- Status: Proposed | Accepted | Superseded by NNNN | Deprecated
- Date: YYYY-MM-DD

## Context

What problem or force makes a decision necessary; what is true in the code today.

## Decision

The decision, stated so a contributor can follow it. Name the files that carry it.

## Consequences

What becomes easier, what becomes harder, what every later change has to respect, and which
checks enforce it.
```

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-rulebook-parity.md) | Rulebook parity between the table and the rules core | Accepted |
| [0002](0002-rules-epochs.md) | Rules epochs: recorded games replay byte-identically | Accepted |
| [0003](0003-generated-board-dressing.md) | Generated-board dressing: the grid is the truth, modules are the look | Accepted |
| [0004](0004-dressing-materials-and-kit-manifest.md) | Dressing materials and the kit manifest | Accepted |
| [0005](0005-snapshot-pins.md) | Compare-cleanup literals are snapshot pins | Accepted |
