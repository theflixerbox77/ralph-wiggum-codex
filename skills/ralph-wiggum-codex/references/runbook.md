# Runbook

## Preflight Checklist

- Confirm objective and completion promise are specific.
- Confirm at least one validation command is present.
- Confirm max iterations is finite for unattended runs.
- Confirm source-of-truth artifacts are current.

## Typical Run

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --prompt-file docs/tasks/task.md \
  --source-of-truth docs/tasks/task.md \
  --source-of-truth docs/architecture.md \
  --completion-promise "DONE" \
  --max-iterations 25 \
  --preflight-cmd "npm ci --prefer-offline" \
  --validate-cmd "npm run lint" \
  --validate-cmd "npm run build"
```

## Resume

```bash
~/.codex/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh \
  --cwd /repo \
  --resume
```

## Manual Stop

```bash
touch /repo/.codex/ralph-loop/STOP
```

## Failure Triage

- Inspect `.codex/ralph-loop/events.log` for stop reason and failure pattern.
- Inspect validation logs under `.codex/ralph-loop/validation/`.
- If failures are environmental, fix environment and `--resume`.
- If failures are prompt-related, update source-of-truth artifacts and restart.

## Safety Notes

- `--dangerous` removes Codex sandbox protections; use only for explicitly trusted environments.
- If using `--max-iterations 0`, supply either `--completion-promise` or `--allow-unbounded` intentionally.
