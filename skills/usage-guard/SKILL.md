---
name: usage-guard
description: Keep token-heavy loops from exhausting usage limits. Use before starting one.
---

# Usage Guard

`scripts/notifier.sh` tracks usage and tells you when to stop and resume.

## Process

Run `bash "<absolute-skill-path>/scripts/notifier.sh" --help`, ask the user for the threshold and interval values, then launch:

```text
bash "<absolute-skill-path>/scripts/notifier.sh" <arguments>
```

Follow its notifications.
