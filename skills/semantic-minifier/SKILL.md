---
name: semantic-minifier
description: Compact llm-facing text (code comments, CLAUDE.md, dev notes) by cutting everything the reader can infer.
---

# LLM-Content Compaction

Input: llm-facing text — code comments, CLAUDE.md / AGENTS.md, dev notes (file/scope via args, else content under discussion).
Reader: frontier model. Encyclopedic — supply only what it cannot know or infer; keywords suffice, its knowledge fills in.

LLM edits accrete narration — comments, rationale, walkthroughs; default to delete.

## Deletion

* Changes reader behavior? No → delete. 
* Restates the code/content it sits on (e.g. walkthrough, `// increment counter`).
* Parenthetical restating its head term (e.g. `Overrides (take precedence over defaults)` → `Overrides`).
* Derivable from general knowledge, the codebase, or elsewhere in the doc.
* Reader's default behavior anyway (e.g. "write clean code", "make tests green").
* Edit-time commentary: why the change is correct, what it replaced, review notes.

## Distillation

* Keyword over explanation: name concepts, never explain them.
* State once at the authoritative place; pointers over mirrors.
* Cut adjectives, intensifiers, politeness, filler.
* Be extremely concise and sacrifice grammar for the sake of concision.

## Output

Edit in place; Comments/docs only. English regardless of input language.
