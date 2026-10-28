## Subagent model policy

- **Code exploration / fact-finding subagents** (reading the sources, enumerating
  symbols, reporting usages, verifying claims) MUST be launched with `model: "sonnet"`.
- **Synthesis, architectural judgement, writing of deliverables** stays with the main
  (default) model; do not delegate these to cheaper models.
- Explorer subagents must report file paths (and symbol names, where they apply) for
  every claim.

## Git

- Never add a `Co-Authored-By` line (or any other Claude co-author trailer) to a git commit
  message. This rule applies to every commit, including commits made by subagents.

## Writing style

- Provide explanations in the spirit of ASD-STE100 (Simplified Technical English): keep sentence structures direct, limit each procedural step to a single action, and avoid unnecessary synonyms (use one term for one concept).
