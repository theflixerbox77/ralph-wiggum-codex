# Ralph Prompt Generator

`ralph-prompt-generator` is the companion skill that turns a rough coding request into an execution-ready prompt block for `$ralph-wiggum-codex`.

It standardizes prompt structure, preserves constraints, selects model + reasoning effort defaults, and proposes loop guardrails so long-running Ralph sessions start with better instructions.

## When To Use

Use `$ralph-prompt-generator` first when:
- The objective is incomplete or ambiguous.
- You want explicit model/reasoning/flag recommendations.
- You want a reusable prompt block for future runs.

Skip it when you already have a fully formed Ralph handoff prompt with validated settings.

## Workflow

1. Provide your raw objective.
2. The generator always asks:
   - `Do you want a suggested output section included in the generated prompt?`
3. It asks additional questions only if required (cwd, validations, scopes, success criteria).
4. It emits one final markdown code block that starts with:
   - `/skills`
   - `$ralph-wiggum-codex`
5. You paste/run that generated block as your Ralph invocation prompt.

## Optional Auto-Discovery

If you did not provide validation commands, the generator may infer likely candidates by scanning repo metadata (for example `package.json` scripts) and then ask you to confirm before finalizing.

## Output Contract

Final output must be exactly one fenced markdown code block containing:
- `/skills`
- `$ralph-wiggum-codex`
- An optimized objective/constraints/validation structure
- Recommended model and reasoning effort
- Recommended loop settings (`--autonomy-level`, iteration limits, progress scopes, timeouts, retries, and validation commands)

## Example

### Example input

```text
$ralph-prompt-generator
Refactor auth middleware and prevent regressions.
```

### Example generated output

```text
/skills
$ralph-wiggum-codex
Run this in: /path/to/repo
Objective: Refactor auth middleware for maintainability while preserving behavior.
Constraints:
- Keep public API behavior unchanged.
- Avoid unrelated refactors.
Non-goals:
- No new auth features.
Success criteria:
- Existing auth behavior preserved and tests pass.
Validation:
- npm run lint
- npm run test -- auth
Progress scope:
- "src/auth/"
Recommended model: gpt-5.3-codex
Reasoning effort: high
Risk profile: medium (auth-sensitive)
Suggested runner flags:
--autonomy-level l2
--max-iterations 24
--max-consecutive-failures 3
--max-stagnant-iterations 4
--progress-scope "src/auth/"
--idle-timeout-seconds 900
--hard-timeout-seconds 5400
--timeout-retries 1
--events-format both
--progress-artifact
--validate-cmd "npm run lint"
--validate-cmd "npm run test -- auth"
```

## Recurring Usage Patterns

1. Feature delivery kickoff
- Convert product requirements into a testable engineering objective with explicit validations.

2. Bugfix hardening
- Enforce regression validation and tighter iteration caps.

3. Cross-service migration
- Select `xhigh` reasoning and stronger timeout/stagnation guardrails before long unattended runs.

## Relationship To Ralph Loop Skill

- `ralph-prompt-generator` optimizes briefing and configuration.
- `ralph-wiggum-codex` executes the autonomous refinement loop.

Recommended sequence:
1. `$ralph-prompt-generator`
2. Run the generated `$ralph-wiggum-codex` block

## References

- `skills/ralph-prompt-generator/SKILL.md`
- `skills/ralph-prompt-generator/references/prompt-improver-principles.md`
- `skills/ralph-prompt-generator/references/openai-codex-prompting-2026.md`
- `skills/ralph-prompt-generator/references/ralph-flag-selection-matrix.md`
- `skills/ralph-wiggum-codex/SKILL.md`
