---
name: spec
description: Interview the user in depth about a feature, then write a complete, self-contained spec to SPEC.md.
disable-model-invocation: true
argument-hint: "[one-line feature description]"
---

First, check whether `SPEC.md` already exists.

If a `SPEC.md` already exists, stop and tell me before writing anything. It is either
work still in flight, or a finished spec that should be archived to
`docs/specs/NNNN-<slug>.md` first. Never overwrite it.

Interview me about this feature using the AskUserQuestion tool: $ARGUMENTS

Ask about technical approach, data model, UI/UX, failure modes, security and privacy
implications, and the tradeoffs I may not have considered. Skip obvious questions; dig
into the hard parts. One focused question at a time.

Keep interviewing until every open question is closed, then write `SPEC.md` containing:

1. **Problem** — what breaks today, for whom.
2. **Scope** — what is in, and an explicit list of what is out.
3. **Design** — the approach, the files and interfaces involved, alternatives rejected.
4. **Security & privacy** — data touched, trust boundaries crossed, new attack surface,
   what is logged and what is redacted.
5. **Test plan** — the specific cases, including the edge cases we discussed.
6. **Verification** — one end-to-end command or procedure that proves it works.

Do not write any implementation code in this session.
