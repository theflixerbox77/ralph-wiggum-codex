# Ralph Flag Selection Matrix

This reference is for synthesizing `ralph-loop-codex.sh` settings used by `$ralph-wiggum-codex`.

## Runner Defaults (For Context)

Key defaults from the runner (unless overridden):
- `--max-iterations`: 20
- `--max-consecutive-failures`: 3
- `--max-stagnant-iterations`: 6
- `--idle-timeout-seconds`: 900
- `--hard-timeout-seconds`: 7200
- `--timeout-retries`: 1
- `--autonomy-level`: l2
- `--events-format`: both
- `--progress-scope`: `.`

## Always-On Recommendations

Unless the user explicitly overrides:
- `--events-format both`
- `--progress-artifact`

## Profiles

Choose the smallest profile that fits the task.

| Profile | Typical signals | Autonomy | Model | Reasoning | Iterations | Failures | Stagnant | Idle | Hard | Retries |
|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| `quick-fix` | single-file bugfix, low risk, clear validation | `l1` | `gpt-5.3-codex` | `medium` | 12 | 2 | 3 | 600 | 3600 | 0 |
| `standard-feature` | one module/service, moderate change | `l2` | `gpt-5.3-codex` | `high` | 24 | 3 | 4 | 900 | 5400 | 1 |
| `complex-change` | multi-step change, multiple modules, refactor risk | `l2` | `gpt-5.3-codex` | `high` | 40 | 3 | 6 | 900 | 7200 | 1 |
| `high-risk` | migration, cross-system change, incident-level sensitivity | `l1` (start) | `gpt-5.3-codex` (Codex) or `gpt-5.2-codex` (API) | `xhigh` | 60 | 3 | 8 | 1200 | 10800 | 2 |

Notes:
- `Reasoning` is a recommendation for the session/config; it is not a runner flag.
- For `high-risk`, start conservative and widen autonomy only if needed.

## `--autonomy-level` Guidance

- `l0`: prefer for read-only analysis and planning.
- `l1`: prefer when safety matters and changes should be minimal and reviewable.
- `l2`: default for most engineering work.
- `l3`: use only when explicitly requested and risk tolerance is high.

The runner maps default sandbox from autonomy when `--sandbox` is not set:
- `l0` -> `read-only`
- `l1|l2|l3` -> `workspace-write`

Avoid `--sandbox danger-full-access` unless the user explicitly requests it.

## `--progress-scope` Selection

- Choose the narrowest scope that still allows success.
- Prefer module paths implied by the goal (for example `src/auth/`).
- Add test paths only when tests are expected to change (`tests/`, `__tests__/`).
- Avoid `.` unless the task truly spans the full repo.

## `--validate-cmd` Selection

Use the fastest meaningful checks first; append deeper checks second.

Typical ordering:
1. Lint/type checks (`npm run lint`, `npm run typecheck`)
2. Targeted tests (`npm test -- foo.spec.ts`)
3. Full suite only when required (`npm run test`)

If validations are unknown, do not guess. Either infer from repo context and ask for confirmation, or ask directly.

## Optional Flags Worth Considering

Use sparingly; only include when they materially improve reliability:

- `--source-of-truth <path-or-url>`:
  - include 1-3 anchors when requirements are defined by a spec/ticket/doc.
  - keep anchors concrete; avoid broad links.

- `--preflight-cmd <command>`:
  - use to fail fast before iterating (install deps, generate code, etc.).
  - prefer non-destructive commands; do not add long preflights by default.

- `--sleep-seconds <n>`:
  - use when the loop thrashes or validations are expensive.

- `--model` / `--profile`:
  - use `--model` to pin a specific model.
  - use `--profile` when the user relies on profile-scoped config (for example `model_reasoning_effort`).

- `--codex-arg <arg>`:
  - only if you know the underlying `codex exec` flag is supported.
