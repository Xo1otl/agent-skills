# agent-skills

Personal [Agent Skills](https://agentskills.io) collection.
The skills follow the open [SKILL.md standard](https://agentskills.io/specification),
so they work in any skills-compatible agent (Claude Code, Codex, Cursor, …) and
are installed with the [`skills` CLI](https://github.com/vercel-labs/skills).

## Install

```bash
npx skills add Xo1otl/agent-skills --global --yes
```

`--global` makes the skills available in all your projects (drop it to install
into the current project only); drop `--yes` to pick skills interactively.
Re-run the same command to update. To uninstall: `npx skills remove --global`.

## Skills

Each subdirectory of [`skills/`](skills/) is one skill; its `SKILL.md` states
what it does and when it triggers.

## Layout

```
agent-skills/
└── skills/
    └── <skill-name>/
        ├── SKILL.md           # required: frontmatter + instructions
        └── ...                # optional scripts, templates, references
```
