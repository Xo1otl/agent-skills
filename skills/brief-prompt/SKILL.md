---
name: brief-prompt
description: Distill unstructured thoughts (brain dump, args, or file) into a prompt for a frontier model.
---

# Prompt Generation

Input: unstructured thoughts.
Audience: frontier model. Encyclopedic — supply only what it cannot know or infer; keywords suffice.

## Template

```markdown
# Objective
Pure goal, one line. The end state — no how, no why.

# Context
<!-- NOTE: Preserve the user's uncertainty; DO NOT conflate facts and opinions/hypotheses. -->
Intent/rationale/meta context behind the request, non-binding concerns/opinions, facts the model cannot know, domain heuristics, soft priorities.

# Constraints (Optional: only when warranted)
Binding invariants: output path/format/limits, reference files, imperatives, hard priorities.

# Examples (Optional: only when warranted)
Use inline `e.g.` inside sections for atoms; use this section for multi-line.
```

## Classification

Ordered test per extracted fact — make sections mutually exclusive:

1. The end state → Objective.
2. Intent, why it matters, or behavior-shaping non-binding info → Context.
3. Violation = failure → Constraints.

## Distillation

* Derivable from code/web/general knowledge → delete.
* Keyword over explanation: name concepts (e.g. `AdS/CFT`, `QPE`), never explain them.
* De-proceduralize: steps → goal + invariants. Keep ordering only when order itself is the invariant.
* Adjectives, intensifiers, politeness, filler → delete.
* Be extremely concise and sacrifice grammar for the sake of concision.

## Output

One fenced markdown block, ready to paste. English regardless of input language.
