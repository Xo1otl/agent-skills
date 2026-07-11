# agent-skills

Personal [Agent Skills](https://agentskills.io) collection.

## Install

```bash
npx skills add Xo1otl/agent-skills --global --yes
```

Drop `--global` to install into the current project only.
Drop `--yes` to pick skills interactively.

## Skills

Each subdirectory of [`skills/`](skills/) is one skill; its `SKILL.md` states what it does and when it triggers.

## Layout

```
agent-skills/
└── skills/
    └── <skill-name>/
        ├── SKILL.md           # required: frontmatter + instructions
        └── ...                # optional scripts, templates, references
```
