# Secret handling

- Never read, echo, log, or copy the contents of `.env*`, `secrets/**`, `*.pem`, `*.key`,
  or any file containing a credential. Read `.env.example` for variable *names* only.
- Never write a credential into source, tests, fixtures, comments, or commit messages.
- Never paste a credential into a URL, a shell command, or a tool argument.
- If a task appears to require a real credential, stop and ask instead of improvising.
- If you find what looks like a leaked credential in the repo, report it and do not
  reproduce its value.
