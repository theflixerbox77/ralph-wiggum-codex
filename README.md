# Ralph Wiggum Codex Skills

Objective-first Ralph-style autonomous loops for Codex, packaged as installable skills.

`ralph-wiggum-codex` is a Codex skill for long-running task completion that keeps the user request and acceptance criteria at the center, runs a mandatory work/review loop, and uses optional verification as evidence instead of as the whole task.

## Repo Contents

This repo ships two Codex skills, not two plugins:

- `ralph-wiggum-codex`: the objective-first execution loop
- `ralph-prompt-generator`: the staged prompt-improver companion that saves planning, draft, and final prompt files before handing off to Ralph

## What This Is

This repo is not a Claude plugin port that relies on `.claude-plugin` hooks. It is a Codex-native skill package with:
- `SKILL.md` instructions for each skill
- optional `agents/openai.yaml` metadata and invocation policy for each skill
- a single monolithic loop runner script that powers `ralph-wiggum-codex`

## Core Capabilities

- Mandatory work/review loop with fresh context each phase
- Objective and acceptance-criteria reloading from repo-backed files
- Optional verification commands used as evidence, not as the product definition of success
- Explicit blocked handling with `RALPH-BLOCKED.md`
- Review-driven shipping via `review-result.txt`
- Iteration memory (`iteration-history.md`) fed into future work phases
- Scoped progress gating (`--progress-scope`) to block fake no-op completion
- Deterministic Codex runtime selection (`--codex-bin <path-or-name>`)
- Configurable event artifact formats (`--events-format <tsv|jsonl|both>`, default `both`)
- Optional per-iteration progress artifacts (`--progress-artifact`)
- Watchdog timeouts with controlled retries (`--idle-timeout-seconds`, `--hard-timeout-seconds`, `--timeout-retries`)
- Resume support and stale-lock recovery with metadata (`--reclaim-stale-lock`)

## Optional Prompt Generator

This repo also includes `ralph-prompt-generator`, a companion skill that turns rough prompts into a staged prompt-improvement workflow for `$ralph-wiggum-codex`.

Use the companion when:
- The objective is ambiguous or underspecified.
- Acceptance criteria need to be derived and tightened before starting the loop.
- You want critique, revision, and explicit review checkpoints before execution.
- You want a saved production-ready prompt file rather than an inline flags-first handoff.

Example input:

```text
$ralph-prompt-generator
<user_prompt>
Refactor auth middleware and prevent regressions.
</user_prompt>
```

Workflow shape:

- Phase A: planning only, save `docs/prompt-improver-spec/artifacts/implementation_plan.md` and `docs/prompt-improver-spec/artifacts/task.md`, then pause for review after Steps 1-2
- Phase B: draft only, save `docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md`
- Phase C: critique and revision planning only, append to `implementation_plan.md`, then pause again after Step 4
- Phase D: save `docs/prompt-improver-spec/final-prompts/<prompt-name>.md`, delete the draft, write `docs/prompt-improver-spec/artifacts/walkthrough.md`, and return a short Ralph invocation snippet that points at the saved prompt file

Relationship to `ralph-wiggum-codex`:
- `ralph-prompt-generator` improves the prompt itself and saves the review artifacts.
- `ralph-wiggum-codex` executes the autonomous work/review loop.

## Install

### Option 1: Install the loop skill

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo MattMagg/ralph-wiggum-codex \
  --path skills/ralph-wiggum-codex
```

### Option 2: Install the prompt-improver companion

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo MattMagg/ralph-wiggum-codex \
  --path skills/ralph-prompt-generator
```

### Option 3: Manual install one or both skills

```bash
mkdir -p ~/.codex/skills
cp -R skills/ralph-wiggum-codex ~/.codex/skills/
cp -R skills/ralph-prompt-generator ~/.codex/skills/
```

Restart Codex after install.

## Use It As A Skill

Call the skill directly:

```text
$ralph-wiggum-codex
Run this in /path/to/repo.
Objective: implement X cleanly.
Acceptance criteria:
- the user-visible behavior works
- the change is ready to ship
Optional verification:
- npm run test
```

The skill should materialize and maintain these first-class state files under `.codex/ralph-loop/`:
- `objective.md`
- `acceptance-criteria.md`
- `feedback.md`
- `work-summary.md`
- `review-feedback.md`
- `review-result.txt`
- `RALPH-BLOCKED.md`
- `.ralph-complete`

## Advanced: Run The Engine Script Directly

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --objective-file /path/to/repo/.codex/ralph-loop/objective.md \
  --acceptance-file /path/to/repo/.codex/ralph-loop/acceptance-criteria.md \
  --feedback-file /path/to/repo/.codex/ralph-loop/feedback.md \
  --max-iterations 40 \
  --max-stagnant-iterations 6 \
  --progress-scope "src/" \
  --idle-timeout-seconds 900 \
  --hard-timeout-seconds 7200 \
  --timeout-retries 1 \
  --validate-cmd "npm run lint" \
  --validate-cmd "npm run test"
```

The direct runner is still supported, but the primary UX is the Codex app skill.

## Work/Review Contracts

Each iteration runs:
1. a work phase
2. optional verification
3. a fresh-context review phase

Work schema (`work-schema.json`):
- `status`: `IN_PROGRESS`, `BLOCKED`, `COMPLETE`
- `assessment`: concise statement of progress against the objective and acceptance criteria
- `evidence`: non-empty array of concrete evidence
- `next_step`: one highest-impact next step
- `blocker_reason` (optional, required when `status=BLOCKED`)
- `no_change_justification` (optional)

Review schema (`review-schema.json`):
- `decision`: `SHIP`, `REVISE`, `BLOCKED`
- `assessment`: concise review judgment
- `feedback`: actionable reviewer guidance or ship confirmation
- `evidence`: non-empty array of concrete evidence

The task is complete only when:
- the work phase reports `COMPLETE`
- the review phase decides `SHIP`
- configured optional verification passes
- the progress gate passes, or the no-change claim is explicitly justified

## Run Artifacts

- `.codex/ralph-loop/state.env`
- `.codex/ralph-loop/objective.md`
- `.codex/ralph-loop/acceptance-criteria.md`
- `.codex/ralph-loop/feedback.md`
- `.codex/ralph-loop/work-summary.md`
- `.codex/ralph-loop/review-feedback.md`
- `.codex/ralph-loop/review-result.txt`
- `.codex/ralph-loop/RALPH-BLOCKED.md`
- `.codex/ralph-loop/.ralph-complete`
- `.codex/ralph-loop/work-schema.json`
- `.codex/ralph-loop/review-schema.json`
- `.codex/ralph-loop/iteration-history.md`
- `.codex/ralph-loop/auto-feedback.md`
- `.codex/ralph-loop/run-summary.md`
- `.codex/ralph-loop/progress/` (when `--progress-artifact` is enabled)
- `.codex/ralph-loop/validation/`
- `.codex/ralph-loop/codex/iteration-<n>-<phase>-attempt-<m>.jsonl`
- `.codex/ralph-loop/.lock/meta.env` (while active)

## Repo Structure

```text
skills/ralph-prompt-generator/
  SKILL.md
  agents/openai.yaml
  references/
skills/ralph-wiggum-codex/
  SKILL.md
  agents/openai.yaml
  scripts/ralph-loop-codex.sh
  references/
docs/
  configuration.md
  prompt-improver-spec/
  ralph-prompt-generator.md
tests/
  smoke.sh
  ralph_loop_contract.sh
  prompt_generator_contract.sh
```

## CI

This repo runs:
- Bash syntax check for the loop runner
- Smoke tests in `tests/smoke.sh`

## Docs

- `docs/configuration.md`: runner configuration and objective-first operating model
- `docs/ralph-prompt-generator.md`: staged prompt-improver workflow, checkpoints, and final prompt delivery pattern
- `docs/prompt-improver-spec/README.md`: workspace layout for prompt-improver artifacts, drafts, and final prompts
- `docs/releases.md`: release order, versioning policy, and why this repo uses GitHub Releases instead of GitHub Packages

## Releases

Use GitHub Releases for this repo.

Recommended versioning:
- stay on pre-1.0 semver for now
- use minor bumps for meaningful skill or workflow milestones
- use patch bumps for fixes and docs-only release prep

Recommended first tag: `v0.8.0`

Rationale:
- the repo already has substantial development history
- the public skill contracts are still evolving
- `v1.0.0` would imply a stronger stability promise than the repo currently makes

GitHub Packages is not currently applicable because this repo does not publish a package artifact such as an npm package, Python package, container image, or GitHub Action.

## Search Keywords

Codex skill, autonomous coding loop, objective-first agent loop, work review loop, long-running coding workflow, Ralph loop Codex, coding harness.

## License

MIT
