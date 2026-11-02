## What changed

<!-- One paragraph. What this does and why, not a list of files. -->

## Why

<!-- The problem this solves. Link the spec or issue: Closes #N / Refs #N,
     and docs/specs/NNNN-*.md if there is one. -->

## Verification

<!-- Paste the actual check output. "Tests pass" is not verification. -->

```
typecheck:
lint:
test:
build:
```

## Out of scope

<!-- What was deliberately not done here, and why. Prevents scope-creep review. -->

## Security

- [ ] No secrets, keys, or tokens in the diff
- [ ] Input validated at any new trust boundary
- [ ] No new dependency, or a new one is justified above
- [ ] No change to `.github/workflows/**` permissions or secrets access
- [ ] Nothing new logged that could contain credentials or PII
