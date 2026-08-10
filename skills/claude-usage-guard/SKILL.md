---
name: claude-usage-guard
description: Guard long-running Claude Code loops against usage quota exhaustion.
---

# Claude Usage Guard

Ask whether to customize consumption thresholds for the usage quota that resets every five hours; defaults: graceful stop at 90%, force stop at 98%.

```text
Monitor(
  command: bash "<absolute-skill-path>/scripts/watchdog.sh" --graceful <graceful> --force <force> --interval 60,
  persistent: true,
)
```

Cancel the monitor when work completes.
