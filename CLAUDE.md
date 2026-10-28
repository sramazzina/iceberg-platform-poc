## Subagent model policy

- **Code exploration / fact-finding subagents** (reading the Hop sources, enumerating
  symbols, reporting usages, verifying claims) MUST be launched with `model: "sonnet"`.
- **Synthesis, architectural judgement, writing of deliverables** stays with the main
  (default) model; do not delegate these to cheaper models.
- Explorer subagents must use Serena (`initial_instructions` → `activate_project("hop")`)
  and report file paths and symbol names for every claim.

## Writing style

- Provide explanations in the spirit of ASD-STE100 (Simplified Technical English): keep sentence structures direct, limit each procedural step to a single action, and avoid unnecessary synonyms (use one term for one concept).
