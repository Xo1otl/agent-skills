---
name: claude-usage-guard
description: Keep token-heavy Claude Code loops from exhausting the usage quota. Use before starting one.
---

# Claude Usage Guard

Usage is capped per 5-hour window. `scripts/notifier.sh` tracks consumption and
tells you when to stop and when to resume. The weekly cap is out of scope.

## Process

Run `bash "<absolute-skill-path>/scripts/notifier.sh" --help`, ask the user for each argument's value, then launch:

```text
Monitor(
  command: bash "<absolute-skill-path>/scripts/notifier.sh" <arguments>,
  persistent: true,
)
```

Follow its notifications.
