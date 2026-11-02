---
paths:
  - "tests/**"
  - "**/*.test.*"
  - "**/*.spec.*"
---

# Testing rules

- Write the failing test first, then the fix. Show the failure before the fix.
- One behavior per test. The test name states the behavior, not the function name.
- No mocks for code we own. Mock only at process boundaries (network, clock, filesystem).
- Never weaken an assertion, add a `skip`, or widen a matcher to make a suite pass. If a
  test is wrong, say so and explain why rather than editing it into agreement.
- Deterministic only: no real network, no real time, no ordering dependence.
