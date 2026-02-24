# Harness Principles Applied In This Skill

This skill applies harness-engineering principles to long-running Codex work.

## 1) Repository Is The System Of Record

- Objective and feedback live in repo-local files (`objective.md`, `feedback.md`).
- Optional `--source-of-truth` artifacts anchor behavior to explicit references.

## 2) Legibility Over Guessing

- Deterministic run artifacts: `state.env`, `events.log`, `run-summary.md`.
- Deterministic runtime selection via `--codex-bin <path-or-name>`.
- Event artifacts are format-selectable with `--events-format <tsv|jsonl|both>` (default `both`).
- `events.log` remains compatible for existing tooling; `events.jsonl` is additive.
- Machine-readable completion schema: `completion-schema.json`.
- Per-attempt codex event logs: `codex/iteration-<n>-attempt-<m>.jsonl`.
- Optional per-iteration progress snapshots via `--progress-artifact` under `.codex/ralph-loop/progress/`.
- Iteration memory (`iteration-history.md`) captures recent outcomes and model output tails.
- Validation logs are written per iteration.

## 3) Fast Feedback Loops

Preferred loop order:

1. Preflight checks (`--preflight-cmd`)
2. Iteration validation (`--validate-cmd`)
3. Adaptive steering via `feedback.md` and `auto-feedback.md`

## 4) Enforce Invariants Without Micromanagement

- Completion is schema-driven (`status=COMPLETE`) with compatibility promise checks when configured.
- Completion is rejected if validation fails.
- Single active loop via lock directory with stale lock auto-reclaim for dead PID metadata.
- Scoped progress gate blocks no-op iterations unless `no_change_justification` is provided.
- Stagnation guard ends repeated no-progress cycles.

## 5) Entropy Control For Long Runs

- Resumable state avoids ad-hoc restarts.
- Objective and feedback reloading allow controlled mid-run adaptation.
- Auto feedback surfaces failure patterns to improve subsequent iterations.
- Watchdog timeouts and retries prevent indefinite hangs from `codex exec`.
