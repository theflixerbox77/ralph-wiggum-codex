#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_FILE="$ROOT_DIR/skills/ralph-wiggum-codex/SKILL.md"
DOC_FILE="$ROOT_DIR/docs/configuration.md"
README_FILE="$ROOT_DIR/README.md"
META_FILE="$ROOT_DIR/skills/ralph-wiggum-codex/agents/openai.yaml"
RUNBOOK_FILE="$ROOT_DIR/skills/ralph-wiggum-codex/references/runbook.md"
RELIABILITY_FILE="$ROOT_DIR/skills/ralph-wiggum-codex/references/reliability-vnext.md"

pass_count=0
fail_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf '[FAIL] %s\n' "$1" >&2
}

contains_fixed() {
  local pattern="$1"
  local file_path="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q --fixed-strings -- "$pattern" "$file_path"
  else
    grep -Fq -- "$pattern" "$file_path"
  fi
}

expect_contains() {
  local name="$1"
  local pattern="$2"
  local file_path="$3"
  if contains_fixed "$pattern" "$file_path"; then
    pass "$name"
  else
    fail "$name"
  fi
}

expect_not_contains() {
  local name="$1"
  local pattern="$2"
  local file_path="$3"
  if contains_fixed "$pattern" "$file_path"; then
    fail "$name"
  else
    pass "$name"
  fi
}

expect_contains "skill references acceptance criteria" "acceptance criteria" "$SKILL_FILE"
expect_contains "skill references work phase" "work phase" "$SKILL_FILE"
expect_contains "skill references review phase" "review phase" "$SKILL_FILE"
expect_contains "skill references review feedback file" "review-feedback.md" "$SKILL_FILE"
expect_contains "skill references work summary file" "work-summary.md" "$SKILL_FILE"
expect_contains "skill references blocked file" "RALPH-BLOCKED.md" "$SKILL_FILE"
expect_contains "skill references completion marker" ".ralph-complete" "$SKILL_FILE"
expect_contains "skill references task complete stop reason" "task_complete" "$SKILL_FILE"
expect_contains "skill references task blocked stop reason" "task_blocked" "$SKILL_FILE"
expect_not_contains "skill no longer centers validation loop wording" "implement -> validate -> refine" "$SKILL_FILE"

expect_contains "readme references acceptance criteria file" "acceptance-criteria.md" "$README_FILE"
expect_contains "readme references mandatory work/review" "mandatory work/review" "$README_FILE"
expect_contains "readme references optional verification" "Optional verification" "$README_FILE"
expect_contains "readme references review result file" "review-result.txt" "$README_FILE"
expect_not_contains "readme no longer says give it at least one validation command" "give it at least one validation command" "$README_FILE"
expect_not_contains "readme no longer documents completion promise" "--completion-promise" "$README_FILE"

expect_contains "config docs include acceptance file flag" "--acceptance-file <file>" "$DOC_FILE"
expect_contains "config docs include review model flag" "--review-model <model>" "$DOC_FILE"
expect_contains "config docs include review profile flag" "--review-profile <profile>" "$DOC_FILE"
expect_contains "config docs include work schema" "work-schema.json" "$DOC_FILE"
expect_contains "config docs include review schema" "review-schema.json" "$DOC_FILE"
expect_not_contains "config docs no longer include completion promise flag" "--completion-promise <text>" "$DOC_FILE"
expect_not_contains "config docs no longer say completion is accepted only when validation passes" "Completion is accepted only when:" "$DOC_FILE"

expect_contains "metadata default prompt is task-first" "task is complete or genuinely blocked" "$META_FILE"
expect_not_contains "metadata no longer says until the validations pass" "until the validations pass" "$META_FILE"

expect_contains "runbook references review phase" "review phase" "$RUNBOOK_FILE"
expect_contains "runbook references acceptance criteria" "acceptance criteria" "$RUNBOOK_FILE"
expect_contains "reliability doc references fresh-context review" "fresh-context review" "$RELIABILITY_FILE"
expect_contains "reliability doc references task blocked" "task_blocked" "$RELIABILITY_FILE"
expect_not_contains "reliability doc no longer references completion promise" "completion_promise" "$RELIABILITY_FILE"

printf '\nRalph loop contract tests complete: %s passed, %s failed\n' "$pass_count" "$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
