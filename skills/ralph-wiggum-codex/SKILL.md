---
name: ralph-wiggum-codex
description: Use when a coding task needs multi-iteration autonomous refinement with explicit completion criteria, validation commands, resumable loop state, and long-running progress control.
---

# Ralph Wiggum For Codex

Codex-native long-running refinement loop.

This skill is designed to be invoked as a Codex skill (`$ralph-wiggum-codex`).
The loop runner script is an internal execution engine for the skill, not the primary user-facing entrypoint.

## When To Use

Use this skill when:
- The task is unlikely to finish in one turn.
- You need repeated implement -> validate -> refine cycles.
- You want strict completion signaling (`<promise>...</promise>`) and resumable state.
- You need unattended or semi-attended long-running execution with drift resistance.

Do not use this skill when:
- The request is a quick one-shot edit or explanation.
- No meaningful validation loop exists.
- The user wants manual step-by-step control each turn.

## Skill-First Operating Contract

When this skill is invoked, execute this flow:

1. Collect or infer:
- `cwd`
- Objective text
- Validation commands (fastest checks first)
- Completion promise (if strict completion is required)
- Runtime caps (`max-iterations`, `max-stagnant-iterations`)

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
  --objective-file /path/to/repo/.codex/ralph-loop/objective.md \
  --feedback-file /path/to/repo/.codex/ralph-loop/feedback.md \
  --completion-promise "DONE" \
  --max-iterations 40 \
  --max-stagnant-iterations 6 \
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
- Resumable state and lock-based single-run protection

## Output Contract

If `--completion-promise` is set, completion is accepted only when model output is exactly:

```xml
<promise>YOUR_PROMISE</promise>
```

Any extra text invalidates completion. If validations fail, completion is rejected and the loop continues.

## Core Files

- `.codex/ralph-loop/state.env`
- `.codex/ralph-loop/prompt.txt`
- `.codex/ralph-loop/events.log`
- `.codex/ralph-loop/iteration-history.md`
- `.codex/ralph-loop/feedback.md`
- `.codex/ralph-loop/auto-feedback.md`
- `.codex/ralph-loop/last-message.txt`
- `.codex/ralph-loop/run-summary.md`
- `.codex/ralph-loop/validation/`

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
