# Security guidance for this repository

<!-- Read by the security-guidance plugin's model-backed reviews. Combined cap
     across all locations is 8 KB. Keep it to rules specific to THIS repo — the
     plugin already carries a general vulnerability checklist. -->

## Data handling
- Never log request bodies, `email`, `password`, `token`, or any `*_secret` field at any
  level.
- TODO: point at your data-classification doc and name the fields that must be redacted.

## Authorization
- TODO: state the authorization invariant, e.g. "every route under /admin calls
  requireRole('admin') before any data access" or "object lookups scope by tenant".

## Cryptography
- Token and signature comparison uses a constant-time function, never `===` or `==`.
- No homemade crypto. Use the platform library.

## Dependencies
- A new runtime dependency is a finding unless the diff includes a justification comment.
- Any package with a postinstall script is a finding.
