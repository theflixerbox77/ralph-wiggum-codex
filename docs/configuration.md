# Ralph Loop Configuration Reference

This document describes the runner for `ralph-wiggum-codex`:
`skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh`.

The runner now operates as an objective-first Ralph loop:
- work phase
- optional verification
- fresh-context review phase

If the prompt itself still needs critique, drafting, and revision, use `ralph-prompt-generator` first and see:
- `docs/ralph-prompt-generator.md`
- `docs/prompt-improver-spec/README.md`

## Common Usage Modes

1. Use `ralph-prompt-generator`, review the saved prompt-improver artifacts, then run the final prompt with `$ralph-wiggum-codex`.
2. Use `$ralph-wiggum-codex` directly when the objective and acceptance criteria are already clear.
3. Run the runner script directly for advanced operator workflows.

## Quick Start

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --objective-file /path/to/repo/.codex/ralph-loop/objective.md \
  --acceptance-file /path/to/repo/.codex/ralph-loop/acceptance-criteria.md \
  --feedback-file /path/to/repo/.codex/ralph-loop/feedback.md \
  --progress-scope "src/" \
  --validate-cmd "npm test" \
  --max-iterations 40
```

## Flag Precedence, Defaults, And Resume Semantics

Within a single run, including `--resume`, the runner applies:
1. explicit CLI flags for this invocation
2. saved state values loaded from `<state-dir>/state.env` when resuming
3. built-in defaults

`--resume` reloads the prior run state. The primary operator control surface is file-backed:
- `<cwd>/.codex/ralph-loop/objective.md`
- `<cwd>/.codex/ralph-loop/acceptance-criteria.md`
- `<cwd>/.codex/ralph-loop/feedback.md`

Key defaults:
- `--max-iterations`: `20`
- `--max-consecutive-failures`: `3`
- `--max-stagnant-iterations`: `6`
- `--idle-timeout-seconds`: `900`
- `--hard-timeout-seconds`: `7200`
- `--timeout-retries`: `1`
- `--codex-bin`: `codex`
- `--events-format`: `both`

## Core Options

- `--cwd <dir>`: required working directory.
- `--state-dir <dir>`: state/artifacts directory; default: `<cwd>/.codex/ralph-loop`.
- `--prompt <text>`: task objective text for this run.
- `--prompt-file <file>`: load the task objective from file at startup.
- `--objective-file <file>`: objective text reloaded every iteration.
- `--acceptance-file <file>`: acceptance criteria reloaded every iteration.
- `--feedback-file <file>`: optional operator steering; read every iteration.
- `--resume`: resume from existing state in `--state-dir`.
- `--max-iterations <n>`: stop after `n` iterations. `0` requires `--allow-unbounded`.
- `--allow-unbounded`: required when `--max-iterations 0`.
- `--max-consecutive-failures <n>`: stop after `n` consecutive work/review phase failures.
- `--max-stagnant-iterations <n>`: stop after repeated identical work/review outputs.
- `--sleep-seconds <n>`: sleep between iterations.

## Harness And Safety Options

- `--autonomy-level <l0|l1|l2|l3>`: risk profile label used to pick the default worker sandbox.
- `--source-of-truth <path-or-url>` (repeatable): anchors the task to explicit artifacts.
- `--preflight-cmd <command>` (repeatable): run once before the loop starts.
- `--validate-cmd <command>` (repeatable): optional verification run after each work phase.
- `--progress-scope <pathspec>` (repeatable): Git pathspecs used only for anti-no-op protection. Defaults to `.`.
- `--stop-file <path>`: sentinel file; if present, the loop stops cleanly.
- `--reclaim-stale-lock`: force reclaim an existing lock if metadata is missing or corrupt.

## Codex Execution Options

- `--codex-bin <path-or-name>`: which `codex` binary to execute.
- `--sandbox <mode>`: worker sandbox passed to `codex exec`.
- `--model <model>`: worker model override.
- `--profile <profile>`: worker profile override.
- `--review-model <model>`: reviewer model override; defaults to the worker model.
- `--review-profile <profile>`: reviewer profile override; defaults to the worker profile.
- reviewer sandbox: fixed to `read-only` to keep review non-mutating.
- `--idle-timeout-seconds <n>`: kill a phase when JSONL output is idle for `n` seconds.
- `--hard-timeout-seconds <n>`: kill a phase when wall time exceeds `n` seconds.
- `--timeout-retries <n>`: retry timeout-killed phase attempts.
- `--events-format <tsv|jsonl|both>`: run-level event log format.
- `--progress-artifact`: write per-iteration progress artifacts under `<state-dir>/progress/`.
- `--full-auto`: pass `--full-auto` to work and review phases.
- `--dangerous`: pass `--dangerously-bypass-approvals-and-sandbox` to the work phase.
- `--codex-arg <arg>` (repeatable): pass extra CLI args through to both phases.

## Work/Review Contracts

The runner writes two machine-readable contracts:
- `<state-dir>/work-schema.json`
- `<state-dir>/review-schema.json`

Work phase required fields:
- `status`: `IN_PROGRESS`, `BLOCKED`, or `COMPLETE`
- `assessment`: concise progress statement against the objective and acceptance criteria
- `evidence`: non-empty array of concrete evidence
- `next_step`: one highest-impact next step

Work phase optional fields:
- `blocker_reason`: required when `status=BLOCKED`
- `no_change_justification`: required only when the work truly required no scoped code change

Review phase required fields:
- `decision`: `SHIP`, `REVISE`, or `BLOCKED`
- `assessment`: concise review judgment
- `feedback`: actionable review guidance or ship confirmation
- `evidence`: non-empty array of concrete evidence

The task completes when:
- the work phase reports `COMPLETE`
- the review phase decides `SHIP`
- configured optional verification passes
- the progress gate passes, or the no-change claim is justified

The task blocks when:
- the work phase reports `BLOCKED` with `blocker_reason`
- the reviewer agrees that the blocker is real and external
- the runner records `task_blocked`

## Progress Gate

The runner measures scoped progress using Git status porcelain output under the configured `--progress-scope` pathspecs.

This gate is intentionally narrow:
- it ignores changes under the state dir so artifacts do not count as progress
- it only prevents fake no-op completion
- it does not define task success by itself

If no scoped change is detected:
- shipping is still allowed when `no_change_justification` is present and credible
- shipping is rejected when the no-change claim is missing

## Optional Verification

`--validate-cmd` is optional.

Use it when:
- the task has meaningful machine-checkable evidence
- you want the reviewer to see verification results before shipping

Do not treat it as the whole task definition. Verification is evidence, not the objective.

## Timeouts And Retries

Each work or review phase runs under the watchdog:
- idle timeout: JSONL output stops changing for `--idle-timeout-seconds`
- hard timeout: total phase runtime exceeds `--hard-timeout-seconds`

Timeout-killed phases can retry up to `--timeout-retries` times.

## State Files

First-class repo-backed state under `<state-dir>/`:
- `objective.md`
- `acceptance-criteria.md`
- `feedback.md`
- `work-summary.md`
- `review-feedback.md`
- `review-result.txt`
- `RALPH-BLOCKED.md`
- `.ralph-complete`

Operational artifacts under `<state-dir>/`:
- `state.env`
- `events.log`
- `events.jsonl`
- `run-summary.md`
- `iteration-history.md`
- `auto-feedback.md`
- `work-schema.json`
- `review-schema.json`
- `work-last-message.txt`
- `review-last-message.txt`
- `validation/iteration-*/`
- `codex/iteration-<n>-<phase>-attempt-<m>.jsonl`
- `codex/iteration-<n>-<phase>-attempt-<m>.stderr.log`
- `progress/iteration-<n>.txt`

## Stop Reasons

- `task_complete`
- `task_blocked`
- `max_iterations_reached`
- `max_consecutive_failures_reached`
- `max_stagnant_iterations_reached`
- `stop_file_detected`

## Recipes

### Objective-first unattended run

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --objective-file /repo/.codex/ralph-loop/objective.md \
  --acceptance-file /repo/.codex/ralph-loop/acceptance-criteria.md \
  --feedback-file /repo/.codex/ralph-loop/feedback.md \
  --progress-scope "src/" \
  --validate-cmd "npm test" \
  --idle-timeout-seconds 900 \
  --hard-timeout-seconds 7200 \
  --timeout-retries 1 \
  --max-iterations 40 \
  --events-format both \
  --progress-artifact
```

### Resume after interruption

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --resume
```
