# Prompt Improver Principles

Curated principles for turning rough requests into high-signal execution briefs.

## Source Basis

Distilled from the prompt-improver workflows:
- `prompt-improver.md` (analysis + draft)
- `prompt-improver-finalize.md` (critique + revision + polish)

## Core Rule

Clarify, do not prescribe.

The generator improves task framing, constraints, and verification criteria. It should not pre-complete work that the downstream coding agent should discover or implement.

## Rewrite Checklist (Practical)

1. Make the objective testable.
- Convert vague goals into concrete targets.
- Prefer one primary objective; split unrelated asks into separate runs.

2. Preserve constraints and intent.
- Copy explicit must/must-not rules.
- Do not "helpfully" relax constraints.

3. Add non-goals.
- When the user prompt is broad, add 2-5 non-goals to prevent drift.

4. Define success criteria.
- Prefer criteria that map to validations.
- If success is subjective, ask for an objective proxy.

5. Use delimiters.
- Separate objective, constraints, validations, and settings.
- Keep the prompt readable and scannable.

## Anti-Patterns

Do not:
- Provide filled-in example outputs that are effectively the answer.
- Prescribe step-by-step execution details (tools, commands, file edits) unless the user explicitly requested an implementation plan.
- Add extra deliverables (reports, dashboards, docs) that were not asked for.
- Inflate the prompt with generic "be thorough" language when it doesn't change execution.

## Clarification Heuristic

Ask questions only when ambiguity changes execution behavior:
- Missing `cwd` / target repo
- Missing validation commands
- Missing scope (what files are allowed to change)
- Conflicting requirements
- No measurable success criteria

If ambiguity is non-critical, proceed with explicit assumptions.

## Suggested Output Policy

Always ask whether to include a suggested output section.

If included:
- Keep it optional and flexible.
- Do not conflict with Ralph's schema-based completion contract.
- Prefer suggestions like what to include in `evidence` over rigid report schemas.
