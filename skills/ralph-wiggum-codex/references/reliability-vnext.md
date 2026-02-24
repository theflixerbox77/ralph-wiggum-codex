# Ralph Loop Reliability vNext

This document explains the reliability guardrails implemented in the loop runner:
`scripts/ralph-loop-codex.sh`.

It is written for operators who want to understand why the loop stops, how it detects progress, and how to recover from hangs or stale state.

## Overview

Each iteration runs:

1. Build an iteration prompt that includes: objective, validation commands, recent iteration memory, and operator feedback.
2. Run `codex exec` with:
   - deterministic runtime binary/path from `--codex-bin <path-or-name>`
   - machine-readable event stream (`--json`) written to a per-attempt JSONL file
   - final message written to `.codex/ralph-loop/last-message.txt`
   - a JSON Schema contract (`--output-schema`) written to `.codex/ralph-loop/completion-schema.json`
3. Run validation commands (if configured).
4. Evaluate completion + progress gates.

Run-level event artifacts are controlled by `--events-format <tsv|jsonl|both>` (default `both`):
- `tsv` writes `.codex/ralph-loop/events.log`
- `jsonl` writes `.codex/ralph-loop/events.jsonl`
- `both` writes both artifacts

`events.log` remains compatible for existing consumers.

## Completion Contract (Schema-Based)

The runner requires the final assistant message to be exactly one JSON object matching `.codex/ralph-loop/completion-schema.json`.

Required fields:
- `status`: `IN_PROGRESS`, `BLOCKED`, or `COMPLETE`
- `evidence`: non-empty array of concrete evidence strings (prefer command/result pairs)
- `next_step`: one highest-impact next step

Optional fields:
- `no_change_justification`: required when no scoped progress is detected
- `completion_promise`: compatibility field used only when `--completion-promise` is configured

The runner accepts completion only when:
- `status` is `COMPLETE`
- validations pass
- the progress gate passes (or includes `no_change_justification`)
- if `--completion-promise` is set: `completion_promise` equals the configured value

## Compatibility: `--completion-promise` (Deprecated)

`--completion-promise` is supported as a compatibility check but deprecated.

Behavior:
- the runner logs a deprecation warning/event when it is set
- the completion check is performed against the `completion_promise` JSON field, not `<promise>...</promise>`

## Progress Gate (Scoped Diff / No-Op Prevention)

Problem this solves:
- validations can be green while the iteration makes no meaningful edits

The runner computes a scoped `git status --porcelain` hash before and after each `codex exec` call.

Configuration:
- `--progress-scope <pathspec>` can be repeated
- default is `.` (entire repo)

The gate passes when:
- any scoped files changed, or
- `no_change_justification` is provided in the schema output

The gate blocks completion when:
- there is no scoped change and `no_change_justification` is empty

Note:
- files under the runner state dir (`.codex/ralph-loop/`) are ignored for progress detection so that writing artifacts does not count as progress.

Optional observability:
- `--progress-artifact` writes per-iteration progress artifacts under `.codex/ralph-loop/progress/` without affecting scoped progress gating.

## Watchdog Timeouts + Retry

Problem this solves:
- hung or idle `codex exec` processes requiring manual intervention

Per iteration, `codex exec` runs under a watchdog that can kill the process when:
- idle timeout: JSONL output has not changed for `--idle-timeout-seconds`
- hard timeout: total runtime exceeds `--hard-timeout-seconds`

Defaults:
- `--idle-timeout-seconds 900`
- `--hard-timeout-seconds 7200`
- `--timeout-retries 1` (retries only timeout-killed attempts)

Artifacts:
- `.codex/ralph-loop/codex/iteration-<n>-attempt-<m>.jsonl`
- `.codex/ralph-loop/codex/iteration-<n>-attempt-<m>.stderr.log`

## Locking + Stale Lock Recovery

The runner enforces a single active loop using a lock directory:
- `.codex/ralph-loop/.lock/`

Metadata written to `.lock/meta.env` includes:
- `PID`, `RUN_ID`, `STARTED_AT`, and `CWD`

Startup behavior:
- if lock exists and metadata PID is alive: the runner exits (another loop is active)
- if lock exists and metadata PID is dead: the runner auto-reclaims the lock
- if lock exists but metadata is missing/corrupt: the runner exits unless `--reclaim-stale-lock` is set

## Stop Reasons

The runner writes stop reasons to `.codex/ralph-loop/run-summary.md` and logs events to `.codex/ralph-loop/events.log`.

Common stop reasons:
- `schema_completion_detected`
- `max_iterations_reached`
- `max_consecutive_failures_reached`
- `max_stagnant_iterations_reached`
- `stop_file_detected`

## Example Invocation With New Runner Options

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --codex-bin codex \
  --objective-file /repo/.codex/ralph-loop/objective.md \
  --feedback-file /repo/.codex/ralph-loop/feedback.md \
  --events-format both \
  --progress-artifact \
  --max-iterations 40 \
  --validate-cmd "npm run test"
```

## Operational Tips

- If the loop is making no progress: add concrete guidance to `.codex/ralph-loop/feedback.md` and resume.
- If the lock is stuck: prefer `--reclaim-stale-lock` over deleting directories by hand (keeps behavior explicit and logged).
- If you need to reduce thrashing: use `--sleep-seconds`.
