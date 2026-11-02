---
name: kickoff
description: Build the walking skeleton and the verification loop for a new project - structure, one end-to-end path, one real test, and working scripts. Run once in a fresh session after the spec exists.
disable-model-invocation: true
argument-hint: "[optional: path to spec file, defaults to SPEC.md]"
---

## First, look around

Run `ls -A` and `git ls-files | head -50` to see whether this repo is genuinely empty or
already has content to match.

## Your task

Read the spec ($ARGUMENTS, or `SPEC.md` if no path was given) and `CLAUDE.md`.
If neither the named file nor `SPEC.md` exists, stop and ask me for a one-line
description of the project before doing anything else.

This session builds the skeleton only. Not the feature.

1. **Structure and toolchain.** Project layout, dependency manifest, configuration.
   Match whatever is already committed rather than introducing a second convention.
   Ask before adding any dependency the spec does not name.
2. **One end-to-end path.** The thinnest slice that actually runs: one input in, one
   output out. Hardcoded values are correct at this stage.
3. **One real test** exercising that path end to end. Not a placeholder assertion.
4. **Working scripts** for test, lint, typecheck, and build.
5. **Update the Commands table in `CLAUDE.md`** with the real commands, and fill any
   TODO markers the spec now answers.

## Finish

Run every check and paste the actual terminal output. Do not assert that it works,
show it.

Then stop. Do not start on features, do not commit, and do not expand scope beyond the
five items above. List anything you deliberately deferred.
