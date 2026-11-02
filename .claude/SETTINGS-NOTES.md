# What this project's settings.json can and cannot do

This repo runs on a fleet with `/etc/claude-code/managed-settings.json` in place. Managed
settings sit above every other level, and a lower level can only make a managed value
*stricter*, never looser. Check the live picture with `/status` (which managed source was
selected) and `claude doctor` (what got dropped).

## The permission lists here mirror the managed file

They are byte-for-byte the same rules. On a managed machine they are **ignored** -
`allowManagedPermissionRulesOnly: true` makes Claude Code disregard permission rules from
user, project, and local files and from `--allowedTools`. Only the managed rules apply.

They are kept here anyway for two reasons:

1. **Cloud sessions and CI do not read a device's managed file.** An Anthropic-hosted
   session or a CI container falls back to this file as its only permission policy. Without
   these rules, those contexts would run with no policy at all.
2. **One place to read.** A developer opening this repo sees the same policy that is in
   force, rather than having to go find the managed file.

The cost of the mirror is that it can drift. When the managed file changes, update this
file in the same commit, or the fallback policy silently diverges from the real one.

## The sandbox is off, deliberately

Managed settings no longer configure the sandbox, which means a project or user file
*could* turn it on. This file sets `sandbox.enabled: false` explicitly rather than
omitting the key, so a developer's own `~/.claude/settings.json` cannot re-enable it here.

The VM is the isolation boundary. Consequences worth knowing:

- `sandbox.credentials` deny and mask rules do not apply. Nothing unsets credential
  environment variables before a Bash command runs.
- There is no network egress allowlist on Bash. Outbound requests are governed only by
  the `Bash(curl *)` / `Bash(wget *)` ask rules and by whatever the VM's network permits.
- The permission deny rules still cover Claude's Read tool and the Bash commands it
  recognizes as file reads, but not an arbitrary script that opens a file itself.
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` still applies. It is set in the managed `env` block
  and works regardless of sandboxing.

## What this file genuinely controls

- **Hooks.** `allowManagedHooksOnly` is `false`, so the hooks in `.claude/hooks/` run
  alongside the managed ones. With the sandbox off, `protect-files.sh` and `guard-bash.sh`
  are the only deterministic control that travels with the repo. Treat them as
  load-bearing.
  - Both are registered with `"onFailure": "block"` and a 15-second `timeout`. If a script
    is missing, crashes, hangs, or prints malformed output, the tool call is blocked
    instead of allowed. The default is to let it through, and the default timeout is 600
    seconds. `onFailure` needs Claude Code 2.1.295 or later: check `claude --version`, and
    run `claude doctor` to confirm this file still loads on the version you have.
  - They use exec form (`"command": "bash"` plus `args`), so no shell parses the path and
    the scripts don't need the executable bit.
- **The security-guidance plugin's review model.** Its model-backed reviews default to a
  model that is not in the managed `availableModels` list, so `env` pins
  `SECURITY_REVIEW_MODEL` and `SG_AGENTIC_MODEL` to one that is.
- **Plugins**, skills, subagents, rules, and `CLAUDE.md`.

## The formatter hook

`format.sh` formats the whole file after every edit, not just the lines that changed. On a
codebase that is already formatted that is invisible. On one that isn't, Claude's first
one-line fix to a file arrives inside a whole-file style diff.

Repos prepared with `--existing` get the script but not the registration. To opt in, first
run the formatter over the codebase in one dedicated commit and add that commit's hash to
`.git-blame-ignore-revs`, then add this to the `hooks` object in `settings.json`:

```json
"PostToolUse": [
  {
    "matcher": "Edit|Write",
    "hooks": [
      {
        "type": "command",
        "command": "bash",
        "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/format.sh"],
        "timeout": 60
      }
    ]
  }
]
```

Leave `onFailure` at its default here: a formatter that fails should not block an edit.

## Two things that will not work here

- **MCP servers.** `allowManagedMcpServersOnly: true` with an empty `allowedMcpServers`
  means no MCP server loads. A `.mcp.json` in this repo would be inert.
- **Shell injection in skills.** `disableSkillShellExecution: true` replaces every
  `` !`command` `` in a project skill with `[shell command execution disabled by policy]`.
  The skills here ask Claude to run those commands as normal Bash calls instead. Do not
  reintroduce `!` injection - it will not fire, and the skill will read as a broken prompt.

## Skill tool grants

`allowManagedPermissionRulesOnly` also makes Claude Code ignore `allowed-tools` in project
and personal skills (Claude Code 2.1.282 or later), so the git commands `/commit`
pre-approves still prompt on the fleet. `/status` lists each skill whose grant was
ignored. Off the fleet, in cloud sessions and CI, the grant applies without a prompt, and
workspace trust never gates it.

## Model strings

`enforceAvailableModels: true` restricts models to the managed `availableModels` list.
Use exact strings in agent frontmatter (`claude-haiku-4-5`), never aliases (`haiku`).
