# Ralph Loop Reliability vNext

This document explains the reliability guardrails implemented in
`scripts/ralph-loop-codex.sh`.

## Overview

Each iteration now runs as a fresh-context work/review loop:
1. build the work-phase prompt from `objective.md`, `acceptance-criteria.md`, source of truth, operator feedback, prior review feedback, and recent history
2. run the work phase with `codex exec`
3. run optional verification commands
4. build a fresh-context review prompt from the current repo state, `work-summary.md`, and verification results
5. run the review phase with `codex exec`
6. decide whether to `SHIP`, `REVISE`, or confirm a real block

This keeps the loop monolithic while still giving the review pass fresh context.

## Machine-Readable Contracts

The runner writes:
- `.codex/ralph-loop/work-schema.json`
- `.codex/ralph-loop/review-schema.json`

Work contract:
- `status`: `IN_PROGRESS`, `BLOCKED`, `COMPLETE`
- `assessment`
- `evidence`
- `next_step`
- optional `blocker_reason`
- optional `no_change_justification`

Review contract:
- `decision`: `SHIP`, `REVISE`, `BLOCKED`
- `assessment`
- `feedback`
- `evidence`

The key semantic stop reasons are:
- `task_complete`
- `task_blocked`

## Acceptance Criteria As Ship Gate

The runner is objective-first:
- work quality is judged against the objective plus acceptance criteria
- optional verification is supporting evidence, not the whole task
- the reviewer can only ship the task when the acceptance criteria are satisfied

Shipping still requires:
- work phase reported `COMPLETE`
- review phase decided `SHIP`
- configured verification passed
- progress gate passed, or the no-change claim was justified

## Fresh-Context Review

The reviewer starts from fresh context every iteration and inspects:
- the current repo state
- `work-summary.md`
- verification logs/results
- the objective and acceptance criteria

By default the reviewer uses the same model/profile as the worker, but it is still a distinct fresh-context pass. `--review-model` and `--review-profile` allow explicit overrides.

## Blocked Handling

The worker may report `BLOCKED`, but the loop only stops as `task_blocked` when the reviewer agrees the blocker is genuine and external.

If the reviewer thinks the task is still solvable inside the repo:
- decision becomes `REVISE`
- `review-feedback.md` captures the next direction
- `RALPH-BLOCKED.md` is not left behind

## Progress Gate

The progress gate still computes a scoped git diff before and after the iteration.

Its job is narrow:
- prevent fake “complete” claims with no scoped repo change
- allow justified no-change completion when `no_change_justification` is explicit
- avoid mistaking state-dir artifact writes for progress

It is not the product’s definition of task success.

## Watchdog Timeouts And Retry

Both work and review phases run under the watchdog:
- idle timeout: JSONL output stops changing for `--idle-timeout-seconds`
- hard timeout: phase runtime exceeds `--hard-timeout-seconds`

Timeout-killed phases can retry up to `--timeout-retries` times.

Artifacts:
- `.codex/ralph-loop/codex/iteration-<n>-work-attempt-<m>.jsonl`
- `.codex/ralph-loop/codex/iteration-<n>-review-attempt-<m>.jsonl`

## Stop Reasons

Common stop reasons:
- `task_complete`
- `task_blocked`
- `max_iterations_reached`
- `max_consecutive_failures_reached`
- `max_stagnant_iterations_reached`
- `stop_file_detected`
