# Harness Principles Applied In This Skill

This skill encodes practical harness-engineering ideas for Codex loops.

## 1) Repository Is The System Of Record

- Loop prompts can include `--source-of-truth` files/URLs.
- Operators anchor each run to explicit artifacts instead of memory.

## 2) Legibility Over Guessing

- State, prompt, events, and summary are written to deterministic files.
- Validation commands generate per-iteration logs.

## 3) Enforce Invariants, Don’t Micromanage

- Invariant: completion requires exact promise output.
- Invariant: completion is rejected when validation fails.
- Invariant: only one loop process can hold the lock.

## 4) Fast Feedback Loops

Recommended order:

1. Preflight checks (`--preflight-cmd`)
2. Validation checks (`--validate-cmd`)
3. Operator smoke checks (summary and event logs)

## 5) Entropy Control

- `state.env` keeps runs resumable instead of ad-hoc restarts.
- `events.log` preserves execution history for post-run cleanup and tuning.
- `STOP` sentinel provides controlled interruption rather than force-kill.
