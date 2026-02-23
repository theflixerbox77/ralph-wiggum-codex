---
name: ralph-wiggum-codex
description: Use when running Ralph-style iterative autonomous coding loops in Codex with explicit stop conditions, validation gates, resumable state, and harness-style safeguards for repository integrity.
---

# Ralph Wiggum For Codex

Codex-native adaptation of the Ralph loop pattern.

Claude Code plugins rely on `.claude-plugin` hooks that Codex does not support. This skill provides equivalent behavior through a deterministic loop runner around `codex exec`.

## Core Behavior

- Re-run Codex on the same objective across iterations.
- Persist state and logs under `.codex/ralph-loop`.
- Stop only when a strict completion contract is met, or when guardrails trigger.

## Guardrails (Harness-Style)

- Preflight checks before first iteration.
- Source-of-truth references to reduce drift.
- Validation loop (`--validate-cmd`) after each iteration.
- Failure budget (`--max-consecutive-failures`).
- Stop sentinel file for operator intervention.
- Lock directory to prevent concurrent loop collisions.

## Quick Start

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --prompt "Implement feature X with tests" \
  --completion-promise "DONE" \
  --max-iterations 20 \
  --validate-cmd "npm run lint" \
  --validate-cmd "npm run build"
```

## Suggested Operating Pattern

1. Declare source-of-truth files (`spec`, `plan`, `requirements`).
2. Add at least one validation command.
3. Set a concrete completion promise.
4. Set a finite max-iteration cap.
5. Monitor `events.log` and `run-summary.md`.

## Resume and Stop

Resume an interrupted run:

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --resume
```

Stop a running loop:

```bash
touch /path/to/repo/.codex/ralph-loop/STOP
```

## Output Contract

When completion promise is set, the loop only accepts exact output:

```xml
<promise>YOUR_PROMISE</promise>
```

Any additional text invalidates completion. If validations fail, completion is rejected and the loop continues.

## Key Files

- State: `.codex/ralph-loop/state.env`
- Prompt: `.codex/ralph-loop/prompt.txt`
- Iteration events: `.codex/ralph-loop/events.log`
- Last model output: `.codex/ralph-loop/last-message.txt`
- Final summary: `.codex/ralph-loop/run-summary.md`

## Recommended Flags

- `--source-of-truth <path-or-url>`: anchor decisions to canonical artifacts.
- `--validate-cmd <command>`: enforce objective evidence.
- `--preflight-cmd <command>`: fail fast before expensive loops.
- `--autonomy-level <l0|l1|l2|l3>`: annotate risk profile.
- `--sandbox <mode>`: explicit safety control.

## References

- Harness principles: `references/harness-principles.md`
- Operational runbook: `references/runbook.md`
