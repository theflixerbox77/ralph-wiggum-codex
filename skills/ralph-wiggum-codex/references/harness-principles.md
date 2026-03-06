# Harness Principles Applied In This Skill

This skill applies Ralph-loop harness principles to long-running Codex work.

## 1) Repository Files Are The System Of Record

- Objective, acceptance criteria, and feedback live in repo-local files.
- Work/review handoff persists through files, not chat accumulation.
- Optional `--source-of-truth` artifacts anchor the loop to explicit requirements.

## 2) Fresh Context Beats Accumulated Noise

- Every work phase starts fresh.
- Every review phase starts fresh.
- `iteration-history.md` is a compact memory aid, not the primary source of truth.

## 3) Acceptance Criteria Drive Completion

- The task is shipped against the objective plus acceptance criteria.
- Optional verification is supporting evidence.
- The reviewer decides `SHIP`, `REVISE`, or `BLOCKED`.

## 4) Reliability Guardrails Stay Mechanical

- File-backed state and resume support keep long runs recoverable.
- Machine-readable schemas keep phase outputs legible.
- Scoped progress gates prevent fake no-op completion.
- Watchdog timeouts and retries prevent hung phases from stalling the loop forever.

## 5) Blocked Handling Must Be Explicit

- A worker blocker claim is not enough by itself.
- The reviewer confirms whether the blocker is real and external.
- Confirmed blockers stop as `task_blocked` with `RALPH-BLOCKED.md`.
