# Ralph Loop Configuration Reference

This document describes every configuration option for the Ralph loop runner:
`skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh`.

There are two ways to use Ralph:

1. As a Codex skill: `$ralph-wiggum-codex` (recommended).
2. By running the runner script directly (advanced operators).

The runner is intentionally a single script with mechanical guardrails:
- schema-based completion contract
- watchdog timeouts + controlled retries
- scoped no-op detection
- resumable state + lock metadata

## Quick Start (Direct Runner)

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --objective-file /path/to/repo/.codex/ralph-loop/objective.md \
  --feedback-file /path/to/repo/.codex/ralph-loop/feedback.md \
  --progress-scope "src/" \
  --validate-cmd "npm test" \
  --max-iterations 40
```

## Flag Precedence, Defaults, And Resume Semantics

### Precedence

Within a single run (including `--resume`), the runner applies:

1. Explicit CLI flags for this invocation
2. Saved state values loaded from `<state-dir>/state.env` (only when `--resume`)
3. Built-in defaults (documented below)

### Resume (`--resume`)

`--resume` loads the prior run state from `<state-dir>/state.env`. It does not mean "repeat the same prompt forever".
The runner re-reads objective and feedback files each iteration, so your primary operator control surface is:

- `<cwd>/.codex/ralph-loop/objective.md`
- `<cwd>/.codex/ralph-loop/feedback.md`

If you pass a flag while resuming, that flag overrides the saved value for this resumed run.

### Defaults

Key defaults (from the runner):

- `--max-iterations`: `20`
- `--max-consecutive-failures`: `3`
- `--max-stagnant-iterations`: `6`
- `--idle-timeout-seconds`: `900` (0 disables)
- `--hard-timeout-seconds`: `7200` (0 disables)
- `--timeout-retries`: `1`
- `--codex-bin`: `codex`
- `--events-format`: `both`

## Core Options

- `--cwd <dir>`: required working directory.
- `--state-dir <dir>`: state/artifacts directory; default: `<cwd>/.codex/ralph-loop`.
- `--prompt <text>`: objective text for this run (mutually exclusive with `--prompt-file`).
- `--prompt-file <file>`: load objective from file at startup.
- `--objective-file <file>`: objective is reloaded every iteration; best for long runs.
- `--feedback-file <file>`: optional operator steering; read every iteration (defaults to `<state-dir>/feedback.md`).
- `--resume`: resume from existing state in `--state-dir`. Do not combine with `--prompt` or `--prompt-file`.
- `--completion-promise <text>`: deprecated compatibility check; if set, the final-message JSON must include `completion_promise` matching this value.
- `--max-iterations <n>`: stop after `n` iterations. `0` means unbounded (requires `--allow-unbounded`).
- `--allow-unbounded`: required when `--max-iterations 0`.
- `--max-consecutive-failures <n>`: stop after `n` consecutive `codex exec` failures.
- `--max-stagnant-iterations <n>`: stop after repeated identical outputs. `0` disables.
- `--sleep-seconds <n>`: sleep between iterations to reduce thrash.

## Harness And Safety Options

- `--autonomy-level <l0|l1|l2|l3>`: risk profile label used to pick a default sandbox when `--sandbox` is not provided.
  - `l0` defaults to `read-only`
  - `l1|l2|l3` default to `workspace-write`
- `--source-of-truth <path-or-url>` (repeatable): anchors behavior to explicit artifacts. Local paths are validated in preflight.
- `--preflight-cmd <command>` (repeatable): run once before the loop starts.
- `--validate-cmd <command>` (repeatable): run after each iteration; completion is rejected if any validation fails.
- `--progress-scope <pathspec>` (repeatable): Git pathspecs used to measure scoped progress. Defaults to `.`.
- `--stop-file <path>`: sentinel file; if present, the loop stops cleanly.
- `--reclaim-stale-lock`: force reclaim existing lock if metadata is missing/corrupt.

## Codex Execution Options

- `--codex-bin <path-or-name>`: which `codex` binary to execute.
  - Recommended when running in CI, or when a repo provides a fixture/stub `codex`.
  - Preflight resolves it via `command -v`.
- `--sandbox <mode>`: passed to `codex exec` (`read-only`, `workspace-write`, `danger-full-access`).
- `--model <model>`: passed to `codex exec` as a model override.
- `--profile <profile>`: passed to `codex exec` as a profile override.
- `--idle-timeout-seconds <n>`: kill `codex exec` when JSONL output is idle for `n` seconds. `0` disables.
- `--hard-timeout-seconds <n>`: kill `codex exec` when wall time exceeds `n` seconds. `0` disables.
- `--timeout-retries <n>`: retry timeout-killed attempts up to `n` times.
- `--events-format <tsv|jsonl|both>`: run-level event log format.
  - `tsv`: writes `<state-dir>/events.log`
  - `jsonl`: writes `<state-dir>/events.jsonl`
  - `both`: writes both (default)
- `--progress-artifact`: write per-iteration progress artifacts under `<state-dir>/progress/iteration-<n>.txt`.
  - This does not affect progress gating; it is an observability artifact.
- `--full-auto`: passes `--full-auto` to `codex exec`.
- `--dangerous`: passes `--dangerously-bypass-approvals-and-sandbox` to `codex exec`.
- `--codex-arg <arg>` (repeatable): pass arbitrary extra CLI args through to `codex exec`.

## Utility Options

- `--dry-run`: print effective configuration and exit (does not run preflight).
- `-h`, `--help`: print usage.

## Completion Contract (Schema-Based)

The runner requires the final assistant message to be exactly one JSON object matching:
`<state-dir>/completion-schema.json`.

Required fields:
- `status`: `IN_PROGRESS`, `BLOCKED`, or `COMPLETE`
- `evidence`: non-empty array of concrete evidence strings
- `next_step`: one highest-impact next step

Always-present fields:
- `no_change_justification`: use a non-empty explanation when no scoped progress was detected; otherwise use `""`
- `completion_promise`: use configured promise only when `--completion-promise` is set and status is `COMPLETE`; otherwise use `""`

Completion is accepted only when:
- `status` is `COMPLETE`
- validation commands pass
- progress gate passes (or has `no_change_justification`)
- if `--completion-promise` is set: `completion_promise` matches

## Progress Gate (Scoped No-Op Prevention)

The runner measures scoped progress using Git status porcelain output under the configured `--progress-scope` pathspecs:

- It ignores changes under the state dir (`<state-dir>/`) so artifacts do not count as progress.
- If there is no scoped change and `no_change_justification` is empty, completion is rejected for that iteration.

Effective usage:
- Use a narrow `--progress-scope` (for example, `src/`, `packages/foo/`) so "progress" means the loop touched the intended surface.
- If the work is legitimately "no changes needed", require the model to explicitly justify that with `no_change_justification`.

## Timeouts And Retries

Two timeouts exist:

- idle timeout: no bytes written to the per-attempt JSONL stream for `--idle-timeout-seconds`
- hard timeout: total runtime exceeds `--hard-timeout-seconds`

Timeout behavior:
- on timeout, the runner kills the `codex exec` process
- if `--timeout-retries > 0`, it retries timeout-killed attempts only

Effective usage:
- Keep idle timeout non-zero for unattended runs.
- Use retries sparingly (`1` is usually enough); repeated timeouts are typically a prompt/tooling issue, not flakiness.

## Locking, Recovery, And Safe Stop

### Stop cleanly

To stop a run without killing the process:

```bash
touch <state-dir>/STOP
```

### Stale lock recovery

The runner uses `<state-dir>/.lock/` with metadata `<state-dir>/.lock/meta.env`.

Startup behavior:
- if metadata PID is alive: exit (another loop is active)
- if metadata PID is dead: auto-reclaim
- if metadata is missing/corrupt: exit unless `--reclaim-stale-lock` is set

## Artifacts And Observability

Key artifacts under `<state-dir>/`:

- `state.env`: resumable state (also used for defaults when resuming)
- `events.log`: TSV events (when `--events-format tsv|both`)
- `events.jsonl`: JSONL events (when `--events-format jsonl|both`)
- `run-summary.md`: stop reason + configuration snapshot
- `last-message.txt`: final assistant message payload
- `completion-schema.json`: schema contract used by `codex exec --output-schema`
- `iteration-history.md`: recent memory appended each iteration
- `auto-feedback.md`: generated corrective guidance when something goes wrong
- `validation/iteration-*/`: per-iteration validation logs (when validations configured)
- `codex/iteration-<n>-attempt-<m>.jsonl`: per-attempt `codex exec --json` event stream
- `codex/iteration-<n>-attempt-<m>.stderr.log`: per-attempt stderr
- `progress/iteration-<n>.txt`: per-iteration scoped progress snapshot (when `--progress-artifact`)

Effective usage:
- If a run "hangs", check the last attempt JSONL file to confirm whether events stopped (idle) or the process is just slow.
- If a run "completes" but didn’t actually change code, check the progress artifact and `progress_scope_diff` events for scoped change evidence.

## Recommended Recipes

### Long unattended run with strong guardrails

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --objective-file /repo/.codex/ralph-loop/objective.md \
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

### Resume after crash

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --resume
```
