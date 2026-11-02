---
name: deep-research
description: Research a topic across the codebase in an isolated context and return a cited summary. Use for "how does X work" questions that would otherwise read many files.
context: fork
agent: Explore
background: false
argument-hint: "[topic or question]"
---

Research this thoroughly and report back: $ARGUMENTS

1. Find the relevant files with Glob and Grep before reading anything.
2. Read only what the question requires.
3. Return: a short summary, then the specific `path:line` references supporting it, then
   anything that contradicts the obvious answer.

Do not modify any file. If the answer is not in the codebase, say so rather than
inferring it.
