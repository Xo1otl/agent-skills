---
name: claude-usage-guard
description: Keep token-heavy Claude Code loops from exhausting the usage quota. Use before starting one.
---

# Claude Usage Guard

Usage is limited per 5-hour window. Let `scripts/notifier.sh` pace you so you don't hit the limit. The weekly limit is out of scope (i.e. don't wait for the weekend).

## Process

Run `bash "<absolute-skill-path>/scripts/notifier.sh" --help`, ask the user for each argument's value, then launch:

```text
Monitor(
  command: bash "<absolute-skill-path>/scripts/notifier.sh" <arguments>,
  persistent: true,
)
```

Follow its notifications.
