---
name: semantic-minifier
description: Compact llm-facing text (code comments, CLAUDE.md, dev notes) by cutting everything the reader can infer.
---

# LLM-Content Compaction

Input: llm-facing text — code comments, CLAUDE.md / AGENTS.md, dev notes (file/scope via args, else content under discussion).
Reader: frontier model. Encyclopedic — supply only what it cannot know or infer; keywords suffice.

LLM edits accrete narration — comments, rationale, walkthroughs; default to delete.

## Distillation

* Changes reader behavior? No → delete.
* Restates the code/content it sits on (e.g. walkthrough, `// increment counter`) → delete.
* Parenthetical restating its head term (e.g. `Overrides (take precedence over defaults)` → `Overrides`) → delete.
* Default behavior (e.g. "write clean code", "make tests green") → delete.
* Edit-time commentary: why the change is correct, what it replaced, review notes → delete.
* Adjectives, intensifiers, politeness, filler → delete.
* Derivable from general knowledge, the codebase, or elsewhere in the doc → delete.
* Pointers over mirrors.
* Keyword over explanation: name concepts, never explain them.
* Be extremely concise and sacrifice grammar for the sake of concision.

## Output

Edit in place; Comments/docs only. English regardless of input language.
