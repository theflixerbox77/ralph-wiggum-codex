#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_FILE="$ROOT_DIR/skills/ralph-prompt-generator/SKILL.md"
DOC_FILE="$ROOT_DIR/docs/ralph-prompt-generator.md"
META_FILE="$ROOT_DIR/skills/ralph-prompt-generator/agents/openai.yaml"
README_FILE="$ROOT_DIR/README.md"
REFERENCE_FILE="$ROOT_DIR/skills/ralph-prompt-generator/references/prompt-improver-workflow-codex.md"
WORKSPACE_README="$ROOT_DIR/docs/prompt-improver-spec/README.md"
ARTIFACTS_GITKEEP="$ROOT_DIR/docs/prompt-improver-spec/artifacts/.gitkeep"
FINAL_PROMPTS_GITKEEP="$ROOT_DIR/docs/prompt-improver-spec/final-prompts/.gitkeep"
AMBIGUOUS_FIXTURE="$ROOT_DIR/tests/fixtures/prompt-generator/ambiguous-source-prompt.xml"
SIMPLE_FIXTURE="$ROOT_DIR/tests/fixtures/prompt-generator/simple-source-prompt.xml"

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

expect_file() {
  local name="$1"
  local file_path="$2"
  if [[ -f "$file_path" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

expect_contains() {
  local name="$1"
  local pattern="$2"
  local file_path="$3"
  if rg -q --fixed-strings "$pattern" "$file_path"; then
    pass "$name"
  else
    fail "$name"
  fi
}

expect_not_contains() {
  local name="$1"
  local pattern="$2"
  local file_path="$3"
  if rg -q --fixed-strings "$pattern" "$file_path"; then
    fail "$name"
  else
    pass "$name"
  fi
}

expect_file "workflow reference exists" "$REFERENCE_FILE"
expect_file "workspace readme exists" "$WORKSPACE_README"
expect_file "artifacts gitkeep exists" "$ARTIFACTS_GITKEEP"
expect_file "final-prompts gitkeep exists" "$FINAL_PROMPTS_GITKEEP"
expect_file "ambiguous prompt fixture exists" "$AMBIGUOUS_FIXTURE"
expect_file "simple prompt fixture exists" "$SIMPLE_FIXTURE"

expect_contains "ambiguous fixture includes user_prompt" "<user_prompt>" "$AMBIGUOUS_FIXTURE"
expect_contains "ambiguous fixture includes examples" "<examples>" "$AMBIGUOUS_FIXTURE"
expect_contains "ambiguous fixture includes feedback" "<feedback>" "$AMBIGUOUS_FIXTURE"
expect_contains "simple fixture includes user_prompt" "<user_prompt>" "$SIMPLE_FIXTURE"
expect_not_contains "simple fixture omits examples" "<examples>" "$SIMPLE_FIXTURE"
expect_not_contains "simple fixture omits feedback" "<feedback>" "$SIMPLE_FIXTURE"

expect_contains "skill accepts user_prompt tag" "<user_prompt>" "$SKILL_FILE"
expect_contains "skill accepts examples tag" "<examples>" "$SKILL_FILE"
expect_contains "skill accepts feedback tag" "<feedback>" "$SKILL_FILE"
expect_contains "skill defines phase a" "Phase A" "$SKILL_FILE"
expect_contains "skill defines phase b" "Phase B" "$SKILL_FILE"
expect_contains "skill defines phase c" "Phase C" "$SKILL_FILE"
expect_contains "skill defines phase d" "Phase D" "$SKILL_FILE"
expect_contains "skill describes review checkpoint after steps 1-2" "Steps 1-2" "$SKILL_FILE"
expect_contains "skill describes review checkpoint after step 4" "Step 4" "$SKILL_FILE"
expect_contains "skill references final prompt path" "docs/prompt-improver-spec/final-prompts/<prompt-name>.md" "$SKILL_FILE"
expect_contains "skill references draft prompt path" "docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md" "$SKILL_FILE"
expect_contains "skill references implementation plan artifact" "docs/prompt-improver-spec/artifacts/implementation_plan.md" "$SKILL_FILE"
expect_contains "skill references task artifact" "docs/prompt-improver-spec/artifacts/task.md" "$SKILL_FILE"
expect_contains "skill references walkthrough artifact" "docs/prompt-improver-spec/artifacts/walkthrough.md" "$SKILL_FILE"
expect_contains "skill requires draft deletion" "Delete the draft file" "$SKILL_FILE"
expect_contains "skill final deliverable includes ralph snippet" "Ralph-ready invocation snippet" "$SKILL_FILE"
expect_not_contains "skill no longer promises one fenced block" "output exactly one fenced markdown code block" "$SKILL_FILE"

expect_contains "workflow reference maps task_boundary" "task_boundary" "$REFERENCE_FILE"
expect_contains "workflow reference maps notify_user" "notify_user" "$REFERENCE_FILE"
expect_contains "workflow reference maps to native Codex review pause" "native Codex review checkpoint" "$REFERENCE_FILE"
expect_contains "workflow reference covers final completion message" "All 6 Steps Complete." "$REFERENCE_FILE"

expect_contains "docs describe staged workflow" "four-phase conversation model" "$DOC_FILE"
expect_contains "docs describe prompt file plus snippet output" "prompt file plus short Ralph invocation snippet" "$DOC_FILE"
expect_not_contains "docs no longer claim single fenced block" "Final output must be exactly one fenced markdown code block" "$DOC_FILE"
expect_contains "readme references saved production-ready prompt file" "production-ready prompt file" "$README_FILE"
expect_contains "metadata advertises staged workflow" "staged prompt-improvement workflow" "$META_FILE"

printf '\nPrompt generator contract tests complete: %s passed, %s failed\n' "$pass_count" "$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
