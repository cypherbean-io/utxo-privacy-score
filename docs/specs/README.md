# Spec archive

`SPEC.md` at the repo root holds **one** spec: the work currently in flight. When that
work ships, move it here and start the next one:

```bash
git mv SPEC.md docs/specs/0004-rate-limiting.md
# add a status line at the top, then commit
```

Each archived file starts with:

```
Status: implemented 2026-08-24 (abc1234)
```

## Why not one growing SPEC.md

- Once a spec mixes shipped and planned work, neither you nor Claude can reliably tell
  which is which, and Claude will either rebuild something that exists or treat a
  deliberate deferral as a gap.
- The code is the source of truth for what the system does. A spec claiming otherwise is
  a confident wrong answer.
- `@SPEC.md` costs its full length in every session that references it.

## What this archive is for

Decision history: why auth is shaped this way, what was explicitly ruled out, what the
tradeoff was. Reach for it with `git log`, `/deep-research`, or by naming a file
directly.

**Do not import these into `CLAUDE.md`.** An `@docs/specs/0002-oauth.md` line looks like
a lazy load and is not - imported files are expanded into context at launch. This archive
should be findable, not resident.
