# Prompt Improver Principles

Curated principles for turning rough prompts into staged, repo-backed improvements for `ralph-prompt-generator`.

## Source Basis

Distilled from the prompt-improver workflows:
- `prompt-improver.md` (analysis + draft)
- `prompt-improver-finalize.md` (critique + revision + polish)

## Core Rule

Clarify, do not prescribe.

The generator improves task framing, constraints, and verification criteria. It should not pre-complete work that the downstream coding agent should discover or implement.

## Workflow Posture

- Prompt improvement comes first; Ralph-specific config comes last.
- Save planning, draft, and final outputs in the repo-backed prompt-improver workspace.
- Reuse earlier artifacts during later phases instead of redoing analysis from scratch.
- Pause at explicit review checkpoints after Steps 1-2 and after Step 4.

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

## Final Ralph Wrapper Policy

When the prompt itself is finished:
- point `$ralph-wiggum-codex` at the saved production-ready prompt file
- add model or flag guidance only when it materially improves the run
- keep the wrapper short; do not restate the full prompt inline
