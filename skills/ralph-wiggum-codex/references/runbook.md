# Runbook

## Companion Prompt-Generator Path

If the prompt itself is still rough, start with `$ralph-prompt-generator` instead of forcing execution details too early.

Recommended flow:
- provide `<user_prompt>` and optional `<examples>` / `<feedback>`
- review `docs/prompt-improver-spec/artifacts/implementation_plan.md` after Steps 1-2
- review the critique appended to `implementation_plan.md` after Step 4
- use the final prompt saved at `docs/prompt-improver-spec/final-prompts/<prompt-name>.md`
- run the short Ralph-ready invocation snippet returned at the end

## Primary Usage

Use `$ralph-wiggum-codex` and let Codex orchestrate the loop.

Recommended invocation payload:
- objective
- acceptance criteria
- working directory
- optional source-of-truth artifacts
- optional verification commands
- progress scope (`--progress-scope`) when the task is narrow or high risk
- runtime caps (`max-iterations`, `max-stagnant-iterations`, timeout settings) when the run needs them
- reviewer overrides only when a different reviewer model/profile is actually needed

## Loop Inputs

Under `<cwd>/.codex/ralph-loop/` maintain:
- `objective.md`: canonical task objective
- `acceptance-criteria.md`: ship gate for the reviewer
- `feedback.md`: operator steering notes
- `review-feedback.md`: reviewer guidance from the prior iteration

## Script Command

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --objective-file /repo/.codex/ralph-loop/objective.md \
  --acceptance-file /repo/.codex/ralph-loop/acceptance-criteria.md \
  --feedback-file /repo/.codex/ralph-loop/feedback.md \
  --events-format both \
  --progress-artifact \
  --source-of-truth docs/tasks/task.md \
  --max-iterations 40 \
  --max-stagnant-iterations 6 \
  --progress-scope "src/" \
  --idle-timeout-seconds 900 \
  --hard-timeout-seconds 7200 \
  --timeout-retries 1 \
  --validate-cmd "npm run lint" \
  --validate-cmd "npm run test"
```

## Resume

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --resume
```

## Manual Stop

```bash
touch /repo/.codex/ralph-loop/STOP
```

## Observability And Triage

Review these files first:
- `.codex/ralph-loop/events.log`
- `.codex/ralph-loop/events.jsonl`
- `.codex/ralph-loop/run-summary.md`
- `.codex/ralph-loop/work-summary.md`
- `.codex/ralph-loop/review-feedback.md`
- `.codex/ralph-loop/review-result.txt`
- `.codex/ralph-loop/work-schema.json`
- `.codex/ralph-loop/review-schema.json`
- `.codex/ralph-loop/codex/iteration-<n>-<phase>-attempt-<m>.jsonl`
- `.codex/ralph-loop/validation/iteration-*/`
- `.codex/ralph-loop/RALPH-BLOCKED.md`

## Runtime Notes

- The review phase is mandatory and fresh-context.
- Acceptance criteria are the ship gate.
- Optional verification is evidence, not the whole task.
- `--progress-scope` plus `no_change_justification` only blocks fake no-op completion.
- `task_complete` and `task_blocked` are the primary semantic stop reasons.
- Update `feedback.md`, `objective.md`, or `acceptance-criteria.md` and resume instead of restarting from scratch.
