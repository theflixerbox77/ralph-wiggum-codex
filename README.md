# Ralph Wiggum Codex Skill

Ralph-style autonomous iteration for Codex with harness-grade safety controls.

`ralph-wiggum-codex` is an installable Codex skill that runs repeatable `codex exec` loops with explicit completion contracts, validation gates, resumable state, and drift-resistant operational guardrails.

## Why This Exists

Claude Code plugins use `.claude-plugin` hooks that Codex does not support. This project adapts the Ralph loop concept to Codex natively via an external orchestration script.

## Features

- Iterative Codex loop execution against a stable objective
- Exact completion promise matching (`<promise>...</promise>`)
- Preflight checks before expensive runs (`--preflight-cmd`)
- Validation loop after each iteration (`--validate-cmd`)
- Resumable state (`--resume`)
- Failure budget (`--max-consecutive-failures`)
- Operator stop sentinel (`STOP` file)
- Locking to avoid concurrent loop collisions
- Harness-inspired source-of-truth anchoring (`--source-of-truth`)

## Install (Codex Skill Installer)

Run:

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo MattMagg/ralph-wiggum-codex \
  --path skills/ralph-wiggum-codex
```

Then restart Codex.

## Manual Install

```bash
mkdir -p ~/.codex/skills
cp -R skills/ralph-wiggum-codex ~/.codex/skills/
```

Then restart Codex.

## Quick Start

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --prompt "Implement feature X with tests" \
  --source-of-truth docs/spec.md \
  --completion-promise "DONE" \
  --max-iterations 20 \
  --validate-cmd "npm run lint" \
  --validate-cmd "npm run build"
```

## Resume

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /path/to/repo \
  --resume
```

## Stop a Running Loop

```bash
touch /path/to/repo/.codex/ralph-loop/STOP
```

## Key Output Files

- `.codex/ralph-loop/state.env`
- `.codex/ralph-loop/events.log`
- `.codex/ralph-loop/last-message.txt`
- `.codex/ralph-loop/run-summary.md`
- `.codex/ralph-loop/validation/` logs

## Operational Guidance

- Always use finite `--max-iterations` for unattended runs.
- Treat `--source-of-truth` as required for non-trivial tasks.
- Treat `--validate-cmd` as required for production-bound changes.
- Avoid `--dangerous` unless running in a fully trusted environment.

## Search Keywords

Codex skill, autonomous coding loop, iterative coding agent, coding agent harness, AI coding automation, Ralph loop for Codex, agentic development workflow.

## Skill Path

Skill lives at:

`skills/ralph-wiggum-codex`

## License

MIT
