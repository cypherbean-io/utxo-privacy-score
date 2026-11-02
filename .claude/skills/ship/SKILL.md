---
name: ship
description: Push the current branch and open a pull request. Runs pre-push checks, writes the PR body from the commits and spec, and stops before merge.
disable-model-invocation: true
argument-hint: "[optional: draft | ready]"
---

## First, verify it is safe to push

Run each of these and read the output before doing anything else:

- `git status --short` - the tree must be clean. If it is not, stop.
- `git rev-parse --abbrev-ref HEAD` - never push `main` or `master`. Stop if that is the
  current branch and tell me to make a branch first.
- `git remote -v` - confirm `origin` points at the expected repository. If the push target
  would be anything other than a named remote you can see here, stop.
- `git log origin/main..HEAD --oneline` - the commits about to be published.
- `git diff origin/main...HEAD` - scan for secrets, debug statements, commented-out code,
  and anything under `.github/workflows/`. If you find any, stop; do not push.

Then run the project's check suite (the commands are in `CLAUDE.md`) and paste the output.
Do not push on a red suite.

## Push

Run `git push -u origin <branch>`. If the remote has moved on, report it and stop. Do not
force push, and do not rebase without asking me first.

## Open the PR

Follow `.github/pull_request_template.md` if it exists. Draw the content from the commits,
from `SPEC.md` (or the archived spec under `docs/specs/`), and from the issue if `/slice`
resolved one.

- Title in Conventional Commit style, matching the main change.
- Use `Closes #N` only if this PR fully resolves the issue; otherwise `Refs #N`.
- Body: what changed and why, how it was verified (paste the check output), and what was
  deliberately left out of scope.
- Use `gh pr create --draft` unless I passed `ready` in $ARGUMENTS.

## Stop

Report the PR URL. Do not merge, do not enable auto-merge, do not add reviewers, and do
not run `gh pr merge`. That is my call.
