---
name: ralph-wiggum-codex
description: Use when a coding task needs repeated implement-validate-fix cycles with clear stop conditions and resumable state.
---

# Ralph Wiggum For Codex

Codex-native long-running refinement loop.

This skill is designed to be invoked as a Codex skill (`$ralph-wiggum-codex`).
The loop runner script is an internal execution engine for the skill, not the primary user-facing entrypoint.

## When To Use

Use this skill when:
- The task is unlikely to finish in one turn.
- You need repeated implement -> validate -> refine cycles.
- You want schema-based completion signaling with resumable state.
- You need unattended or semi-attended long-running execution with drift resistance.

Do not use this skill when:
- The request is a quick one-shot edit or explanation.
- No meaningful validation loop exists.
- The user wants manual step-by-step control each turn.

## Optional Prompt Generator

When the objective or guardrails are genuinely unclear, invoke `$ralph-prompt-generator` first to run the staged prompt-improver workflow for this skill.

Use the companion first when:
- Validation commands are unknown or incomplete.
- Scope/progress paths are unclear.
- The task is high risk and you want critique, revision, and review checkpoints before execution.
- You want the prompt saved as a reusable file in the repo.

Companion handoff pattern:
1. Run `$ralph-prompt-generator` with the raw request.
2. Review the saved planning artifacts after Steps 1-2.
3. Review the saved critique after Step 4.
4. Use the final prompt saved at `docs/prompt-improver-spec/final-prompts/<prompt-name>.md`.
5. Run the short Ralph-ready invocation snippet it returns at the end.

Skip the companion when the task is already clear enough to run directly.

## Skill-First Operating Contract

When this skill is invoked, execute this flow:

1. Collect or infer:
- `cwd`
- Objective text
- Validation commands (fastest checks first)
- Progress scopes (`--progress-scope`) for meaningful edits
- Runtime caps (`max-iterations`, `max-stagnant-iterations`, timeout settings)
- Only pin `codex-bin`, `model`, `profile`, or compatibility fields when the user or environment actually needs them

Default posture:
- Prefer the simplest workable invocation.
- Infer missing validations/scopes from repo context when practical.
- Do not force the companion generator or advanced flags when the task is already clear.

2. Prepare loop files under `<cwd>/.codex/ralph-loop/`:
- `objective.md` (objective to reload every iteration)
- `feedback.md` (optional operator steering)

3. Start the loop runner with objective/feedback files and validations.

4. Monitor run artifacts (`events.log`, `run-summary.md`, `iteration-history.md`, validation logs) and report concise progress.

5. If blocked, update `feedback.md` with corrective guidance and continue (`--resume`) instead of restarting from scratch.

## Execution Command Template

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --codex-bin codex \
  --objective-file /path/to/repo/.codex/ralph-loop/objective.md \
  --feedback-file /path/to/repo/.codex/ralph-loop/feedback.md \
  --max-iterations 40 \
  --max-stagnant-iterations 6 \
  --progress-scope "src/" \
  --idle-timeout-seconds 900 \
  --hard-timeout-seconds 7200 \
  --timeout-retries 1 \
  --validate-cmd "npm run lint" \
  --validate-cmd "npm run test"
```

## Long-Run Refinement Features

The runner supports long-running autonomy with iterative correction:
- Dynamic objective reload each iteration (`--objective-file`)
- Live operator feedback ingestion (`--feedback-file`)
- Auto-generated corrective feedback when codex/validation fails (`auto-feedback.md`)
- Iteration memory (`iteration-history.md`) injected into future prompts
- Stagnation detection (`--max-stagnant-iterations`)
- Scoped no-op prevention (`--progress-scope` + `no_change_justification`)
- Default-on watchdog timeouts with controlled retries
- Resumable state and lock-based single-run protection with stale lock recovery

## Output Contract

Completion is accepted when all of the following are true:
- `codex exec` output conforms to `.codex/ralph-loop/completion-schema.json`
- `status` is `COMPLETE`
- Validation commands pass
- Scoped progress gate passes (or includes `no_change_justification`)
- If compatibility mode is enabled, `completion_promise` equals `--completion-promise`

Schema fields:
- `status`: `IN_PROGRESS`, `BLOCKED`, `COMPLETE`
- `evidence`: non-empty array of concrete evidence
- `next_step`: one highest-impact next step
- `no_change_justification` (optional): include only for justified no-change iterations
- `completion_promise` (optional): include only when compatibility mode is enabled

## Core Files

- `.codex/ralph-loop/state.env`
- `.codex/ralph-loop/prompt.txt`
- `.codex/ralph-loop/events.log`
- `.codex/ralph-loop/events.jsonl` (with `--events-format jsonl|both`; default `both`)
- `.codex/ralph-loop/completion-schema.json`
- `.codex/ralph-loop/iteration-history.md`
- `.codex/ralph-loop/feedback.md`
- `.codex/ralph-loop/auto-feedback.md`
- `.codex/ralph-loop/last-message.txt`
- `.codex/ralph-loop/run-summary.md`
- `.codex/ralph-loop/progress/` (when `--progress-artifact` is enabled)
- `.codex/ralph-loop/validation/`
- `.codex/ralph-loop/codex/iteration-<n>-attempt-<m>.jsonl`
- `.codex/ralph-loop/.lock/meta.env` (while active)

`events.log` remains compatible for existing consumers; JSONL events are additive.

## Resume And Stop

Resume:

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --resume
```

Stop safely:

```bash
touch /path/to/repo/.codex/ralph-loop/STOP
```

## References

- Harness principles: `references/harness-principles.md`
- Operational runbook: `references/runbook.md`
- Reliability vNext: `references/reliability-vnext.md`
