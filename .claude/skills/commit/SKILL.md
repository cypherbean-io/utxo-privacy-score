---
name: commit
description: Stage, review, and commit the current changes with a Conventional Commit message.
disable-model-invocation: true
allowed-tools: Bash(git add *) Bash(git commit *) Bash(git status *) Bash(git diff *)
---

## First, gather state

Run `git status --short`, `git diff --cached`, and `git diff`, and read the output before
doing anything else.

## Instructions

1. If nothing is staged, stage only files belonging to one logical change. Never
   `git add -A` without first listing what it would include.
2. Scan the diff for secrets, debug statements, commented-out code, and stray TODOs.
   Stop and report if you find any; do not commit.
3. Write a Conventional Commit message: `type(scope): summary` under 72 characters, then
   a body explaining *why*, not *what*.
4. Commit. Do not push.
5. Report the commit hash and a one-line summary.
