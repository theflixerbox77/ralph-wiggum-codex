# Ralph Wiggum Codex Skills

Ralph-style long-running autonomous refinement for Codex, packaged as installable skills.

`ralph-wiggum-codex` is a Codex skill for iterative coding loops that continuously refine work until validation passes and completion criteria are met.

Primary use: point Ralph at a repo, give it a concrete objective, and give it at least one validation command. Everything else is optional guardrail tuning.

## Repo Contents

This repo ships two Codex skills, not two plugins:

- `ralph-wiggum-codex`: the long-running implement -> validate -> refine loop
- `ralph-prompt-generator`: the staged prompt-improver companion that saves planning, draft, and final prompt files before handing off to Ralph

## What This Is

This repo is not a Claude plugin port that relies on `.claude-plugin` hooks. It is a Codex-native skill package with:
- `SKILL.md` instructions for each skill
- optional `agents/openai.yaml` metadata and invocation policy for each skill
- a deterministic loop runner script used by `ralph-wiggum-codex` for reliable long runs

## Core Capabilities

- Multi-iteration implement -> validate -> refine loops
- Deterministic completion via `codex exec --output-schema`
- Dynamic objective reloading (`--objective-file`)
- Live steering feedback reloading (`--feedback-file`)
- Auto corrective feedback generation on failures
- Iteration memory (`iteration-history.md`) fed back into future iterations
- Stagnation detection (`--max-stagnant-iterations`)
- Scoped progress gating (`--progress-scope`) to block no-op iterations
- Deterministic Codex runtime selection (`--codex-bin <path-or-name>`)
- Configurable event artifact formats (`--events-format <tsv|jsonl|both>`, default `both`)
- Optional per-iteration progress artifacts (`--progress-artifact`)
- Watchdog timeouts with controlled retries (`--idle-timeout-seconds`, `--hard-timeout-seconds`, `--timeout-retries`)
- Resume support and stale-lock recovery with metadata (`--reclaim-stale-lock`)

## Optional Prompt Generator

This repo also includes `ralph-prompt-generator`, a companion skill that turns rough prompts into a staged prompt-improvement workflow for `$ralph-wiggum-codex`.

Use the companion when:
- The objective is ambiguous or underspecified.
- You want critique, revision, and explicit review checkpoints before starting a long run.
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
- `ralph-wiggum-codex` runs the autonomous refinement loop.

## Install

### Option 1: Install the loop skill (recommended)

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo MattMagg/ralph-wiggum-codex \
  --path skills/ralph-wiggum-codex
```

Restart Codex after install.

### Option 2: Install the prompt-improver companion

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo MattMagg/ralph-wiggum-codex \
  --path skills/ralph-prompt-generator
```

Restart Codex after install.

### Option 3: Manual install one or both skills

```bash
mkdir -p ~/.codex/skills
cp -R skills/ralph-wiggum-codex ~/.codex/skills/
cp -R skills/ralph-prompt-generator ~/.codex/skills/
```

Restart Codex after install.

## Use It As A Skill (Primary)

Call the skill directly:

```text
$ralph-wiggum-codex
Run this in /path/to/repo.
Objective: implement X with tests.
Validation:
- npm run test
```

The skill will set up and run the loop under `.codex/ralph-loop/`.

## Advanced: Run The Engine Script Directly

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --codex-bin codex \
  --objective-file /path/to/repo/.codex/ralph-loop/objective.md \
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

`--completion-promise` is still supported for compatibility but deprecated. Most users should leave it unset.

Resume:

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --resume
```

Stop:

```bash
touch /path/to/repo/.codex/ralph-loop/STOP
```

## Final Message JSON Contract

Each iteration asks Codex to emit exactly one JSON object conforming to `.codex/ralph-loop/completion-schema.json`.

Required fields:
- `status`: `IN_PROGRESS`, `BLOCKED`, or `COMPLETE`
- `evidence`: non-empty array of concrete command/result evidence
- `next_step`: one highest-impact next step

Optional fields:
- `no_change_justification`: include when no scoped files changed and the iteration is legitimately a no-op
- `completion_promise`: include only when `--completion-promise` is set

## Run Artifacts

- `.codex/ralph-loop/state.env`
- `.codex/ralph-loop/events.log`
- `.codex/ralph-loop/events.jsonl` (when `--events-format jsonl|both`; default `both`)
- `.codex/ralph-loop/completion-schema.json`
- `.codex/ralph-loop/iteration-history.md`
- `.codex/ralph-loop/feedback.md`
- `.codex/ralph-loop/auto-feedback.md`
- `.codex/ralph-loop/last-message.txt`
- `.codex/ralph-loop/run-summary.md`
- `.codex/ralph-loop/progress/` (when `--progress-artifact` is enabled)
- `.codex/ralph-loop/validation/`
- `.codex/ralph-loop/codex/iteration-<n>-attempt-<m>.jsonl`
- `.codex/ralph-loop/.lock/meta.env` (while active)

`events.log` remains the compatible/default-friendly artifact for existing tooling; `events.jsonl` is additive.

## Repo Structure

```text
skills/ralph-prompt-generator/
  SKILL.md
  agents/openai.yaml
  references/
    prompt-improver-principles.md
    prompt-improver-workflow-codex.md
    openai-codex-prompting-2026.md
    ralph-flag-selection-matrix.md
skills/ralph-wiggum-codex/
  SKILL.md
  agents/openai.yaml
  scripts/ralph-loop-codex.sh
  references/
    harness-principles.md
    runbook.md
    reliability-vnext.md
docs/
  configuration.md
  prompt-improver-spec/
    README.md
    artifacts/
    final-prompts/
  ralph-prompt-generator.md
```

## CI

This repo runs:
- Bash syntax check for the loop runner
- Smoke tests in `tests/smoke.sh`

## Docs

- `docs/configuration.md`: complete flag reference and effective usage patterns for the runner.
- `docs/ralph-prompt-generator.md`: staged prompt-improver workflow, checkpoints, and final prompt delivery pattern.
- `docs/prompt-improver-spec/README.md`: workspace layout for prompt-improver artifacts, drafts, and final prompts.
- `docs/releases.md`: release order, versioning policy, and why this repo uses GitHub Releases instead of GitHub Packages.

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

Codex skill, autonomous coding loop, iterative coding agent, long-running coding workflow, agentic refinement loop, Ralph loop Codex, coding harness.

## License

MIT
