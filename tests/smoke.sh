#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh"
FIXTURE_PATH="$ROOT_DIR/tests/fixtures"

pass_count=0
fail_count=0
last_stub_state_dir=""

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

expect_success() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

expect_failure() {
  local name="$1"
  shift
  if "$@"; then
    fail "$name"
  else
    pass "$name"
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

quietly() {
  "$@" >/dev/null 2>&1
}

make_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q
  git -C "$repo_dir" config user.email "smoke@example.com"
  git -C "$repo_dir" config user.name "Smoke"
  printf 'initial\n' > "$repo_dir/README.md"
  git -C "$repo_dir" add README.md
  git -C "$repo_dir" commit -qm "init"
}

run_loop() {
  local scenario="$1"
  shift
  last_stub_state_dir="$tmp_dir/stub-$RANDOM-$RANDOM"
  CODEX_STUB_SCENARIO="$scenario" \
    CODEX_STUB_STATE_DIR="$last_stub_state_dir" \
    "$SCRIPT" --codex-bin "$FIXTURE_PATH/codex" "$@"
}

schemas_have_expected_fields() {
  local work_schema="$1"
  local review_schema="$2"
  python3 - "$work_schema" "$review_schema" <<'PY'
import json
import sys

work_schema_path, review_schema_path = sys.argv[1:3]

with open(work_schema_path, "r", encoding="utf-8") as fh:
    work_schema = json.load(fh)
with open(review_schema_path, "r", encoding="utf-8") as fh:
    review_schema = json.load(fh)

work_required = set(work_schema.get("required") or [])
work_properties = set((work_schema.get("properties") or {}).keys())
review_required = set(review_schema.get("required") or [])
review_properties = set((review_schema.get("properties") or {}).keys())

if work_required != {"status", "assessment", "evidence", "next_step"}:
    raise SystemExit(1)
if not {"blocker_reason", "no_change_justification"}.issubset(work_properties):
    raise SystemExit(1)
if review_required != {"decision", "assessment", "feedback", "evidence"}:
    raise SystemExit(1)
if "decision" not in review_properties:
    raise SystemExit(1)
PY
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

base_repo="$tmp_dir/base-repo"
make_repo "$base_repo"
objective_file="$tmp_dir/objective.md"
acceptance_file="$tmp_dir/acceptance.md"
printf 'Implement feature X with tests\n' > "$objective_file"
printf '%s\n%s\n' \
  '- The task outcome matches the user request.' \
  '- The final state is ready to ship when the reviewer confirms it.' > "$acceptance_file"

expect_success "script is executable" test -x "$SCRIPT"
expect_success "help works" quietly "$SCRIPT" --help
expect_success "ralph loop contract passes" bash "$ROOT_DIR/tests/ralph_loop_contract.sh"
expect_success "prompt generator contract passes" bash "$ROOT_DIR/tests/prompt_generator_contract.sh"
expect_failure "missing prompt fails" quietly run_loop work_in_progress --cwd "$base_repo" --dry-run
expect_failure "invalid autonomy level fails" quietly run_loop work_in_progress --cwd "$base_repo" --prompt "x" --autonomy-level bad --dry-run
expect_failure "invalid max stagnant iterations fails" quietly run_loop work_in_progress --cwd "$base_repo" --prompt "x" --max-stagnant-iterations nope --dry-run
expect_failure "invalid idle timeout fails" quietly run_loop work_in_progress --cwd "$base_repo" --prompt "x" --idle-timeout-seconds nope --dry-run
expect_failure "invalid codex bin fails preflight" quietly run_loop work_in_progress --cwd "$base_repo" --prompt "x" --codex-bin "$tmp_dir/does-not-exist-codex"
expect_failure "missing acceptance file fails" quietly run_loop work_in_progress --cwd "$base_repo" --prompt "x" --acceptance-file "$tmp_dir/missing-acceptance.md" --dry-run

dry_run_log="$tmp_dir/dry-run.log"
if run_loop work_in_progress --cwd "$base_repo" --prompt "x" --acceptance-file "$acceptance_file" --review-model "gpt-review" --review-profile "reviewer" --max-iterations 2 --idle-timeout-seconds 12 --hard-timeout-seconds 34 --timeout-retries 2 --progress-scope . --dry-run >"$dry_run_log"; then
  pass "dry-run config works"
else
  fail "dry-run config works"
fi
expect_contains "dry-run prints acceptance file" "acceptance_file=$acceptance_file" "$dry_run_log"
expect_contains "dry-run prints review model" "review_model=gpt-review" "$dry_run_log"
expect_contains "dry-run prints review profile" "review_profile=reviewer" "$dry_run_log"
expect_success "objective file dry-run works" quietly run_loop work_in_progress --cwd "$base_repo" --objective-file "$objective_file" --acceptance-file "$acceptance_file" --dry-run
expect_failure "resume without state fails" quietly run_loop work_in_progress --cwd "$base_repo" --resume

repo_complete="$tmp_dir/repo-complete"
state_complete="$repo_complete/.codex/ralph-loop"
make_repo "$repo_complete"
expect_success "worker complete and reviewer ship stop the loop" quietly run_loop review_ship_complete --cwd "$repo_complete" --state-dir "$state_complete" --prompt "ship it" --acceptance-file "$acceptance_file" --max-iterations 2
expect_contains "task complete stop reason recorded" "task_complete" "$state_complete/run-summary.md"
expect_success "complete marker written" test -f "$state_complete/.ralph-complete"
expect_success "work summary written" test -f "$state_complete/work-summary.md"
expect_success "review result written" test -f "$state_complete/review-result.txt"
expect_success "review feedback written" test -f "$state_complete/review-feedback.md"
expect_success "objective state file written" test -f "$state_complete/objective.md"
expect_success "acceptance criteria state file written" test -f "$state_complete/acceptance-criteria.md"
expect_success "work and review schemas written" schemas_have_expected_fields "$state_complete/work-schema.json" "$state_complete/review-schema.json"
expect_contains "review result says ship" "SHIP" "$state_complete/review-result.txt"
expect_contains "work prompt includes acceptance criteria" "Acceptance criteria:" "$last_stub_state_dir/call-1-work-prompt.txt"
expect_contains "work prompt uses optional verification wording" "Optional verification:" "$last_stub_state_dir/call-1-work-prompt.txt"
expect_contains "review prompt header written" "Ralph Review Phase" "$last_stub_state_dir/call-2-review-prompt.txt"

repo_revise="$tmp_dir/repo-revise"
state_revise="$repo_revise/.codex/ralph-loop"
make_repo "$repo_revise"
expect_success "review revise prevents completion" quietly run_loop review_revise_complete --cwd "$repo_revise" --state-dir "$state_revise" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 1
expect_contains "review revise stops at max iterations" "max_iterations_reached" "$state_revise/run-summary.md"
expect_contains "review result says revise" "REVISE" "$state_revise/review-result.txt"
expect_success "complete marker absent after revise" test ! -f "$state_revise/.ralph-complete"

repo_blocked="$tmp_dir/repo-blocked"
state_blocked="$repo_blocked/.codex/ralph-loop"
make_repo "$repo_blocked"
expect_success "confirmed blocker stops the loop" quietly run_loop blocked_confirmed --cwd "$repo_blocked" --state-dir "$state_blocked" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 2
expect_contains "blocked stop reason recorded" "task_blocked" "$state_blocked/run-summary.md"
expect_success "blocked marker written" test -f "$state_blocked/RALPH-BLOCKED.md"
expect_contains "review result says blocked" "BLOCKED" "$state_blocked/review-result.txt"

repo_blocked_revise="$tmp_dir/repo-blocked-revise"
state_blocked_revise="$repo_blocked_revise/.codex/ralph-loop"
make_repo "$repo_blocked_revise"
expect_success "review can reject a worker blocker" quietly run_loop blocked_revised --cwd "$repo_blocked_revise" --state-dir "$state_blocked_revise" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 1
expect_contains "rejected blocker stops at max iterations" "max_iterations_reached" "$state_blocked_revise/run-summary.md"
expect_contains "rejected blocker review result says revise" "REVISE" "$state_blocked_revise/review-result.txt"
expect_success "rejected blocker does not leave blocked marker" test ! -f "$state_blocked_revise/RALPH-BLOCKED.md"

repo_validation_fail="$tmp_dir/repo-validation-fail"
state_validation_fail="$repo_validation_fail/.codex/ralph-loop"
make_repo "$repo_validation_fail"
expect_success "validation failure overrides ship decision" quietly run_loop review_ship_complete --cwd "$repo_validation_fail" --state-dir "$state_validation_fail" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 1 --validate-cmd "test -f validation.ok"
expect_contains "validation failure prevents task complete" "max_iterations_reached" "$state_validation_fail/run-summary.md"
expect_contains "validation failure rewrites review result to revise" "REVISE" "$state_validation_fail/review-result.txt"
expect_success "complete marker absent after validation failure" test ! -f "$state_validation_fail/.ralph-complete"

repo_noop="$tmp_dir/repo-noop"
state_noop="$repo_noop/.codex/ralph-loop"
make_repo "$repo_noop"
expect_success "no-op without justification does not complete" quietly run_loop review_ship_nochange --cwd "$repo_noop" --state-dir "$state_noop" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 1 --progress-scope .
expect_contains "progress gate block logged" "progress_gate_block" "$state_noop/events.log"
expect_contains "no-op rejection stops at max iterations" "max_iterations_reached" "$state_noop/run-summary.md"

repo_noop_ok="$tmp_dir/repo-noop-ok"
state_noop_ok="$repo_noop_ok/.codex/ralph-loop"
make_repo "$repo_noop_ok"
expect_success "no-op with justification can complete" quietly run_loop review_ship_nochange_justified --cwd "$repo_noop_ok" --state-dir "$state_noop_ok" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 2 --progress-scope .
expect_contains "justified no-op run completes" "task_complete" "$state_noop_ok/run-summary.md"

repo_timeout="$tmp_dir/repo-timeout"
state_timeout="$repo_timeout/.codex/ralph-loop"
make_repo "$repo_timeout"
expect_success "timeout retry reaches completion" quietly run_loop timeout_then_ship --cwd "$repo_timeout" --state-dir "$state_timeout" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 3 --idle-timeout-seconds 1 --hard-timeout-seconds 2 --timeout-retries 1
expect_contains "timeout retry event logged" "codex_timeout_retry" "$state_timeout/events.log"
expect_contains "timeout run completes" "task_complete" "$state_timeout/run-summary.md"

repo_timeout_output="$tmp_dir/repo-timeout-output"
state_timeout_output="$repo_timeout_output/.codex/ralph-loop"
timeout_output_log="$tmp_dir/timeout-output.log"
make_repo "$repo_timeout_output"
if run_loop always_timeout --cwd "$repo_timeout_output" --state-dir "$state_timeout_output" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 1 --idle-timeout-seconds 1 --hard-timeout-seconds 2 --timeout-retries 0 >"$timeout_output_log" 2>&1; then
  pass "timeout scenario for output-noise check completes"
else
  fail "timeout scenario for output-noise check completes"
fi
expect_not_contains "timeout scenario omits bash terminated noise" "Terminated: 15" "$timeout_output_log"

repo_events_tsv="$tmp_dir/repo-events-tsv"
state_events_tsv="$repo_events_tsv/.codex/ralph-loop"
make_repo "$repo_events_tsv"
expect_success "events format tsv run completes" quietly run_loop review_ship_complete --cwd "$repo_events_tsv" --state-dir "$state_events_tsv" --prompt "work" --acceptance-file "$acceptance_file" --events-format tsv --max-iterations 1
expect_success "events format tsv writes events.log" test -f "$state_events_tsv/events.log"
expect_success "events format tsv omits events.jsonl" test ! -f "$state_events_tsv/events.jsonl"

repo_events_jsonl="$tmp_dir/repo-events-jsonl"
state_events_jsonl="$repo_events_jsonl/.codex/ralph-loop"
make_repo "$repo_events_jsonl"
expect_success "events format jsonl run completes" quietly run_loop review_ship_complete --cwd "$repo_events_jsonl" --state-dir "$state_events_jsonl" --prompt "work" --acceptance-file "$acceptance_file" --events-format jsonl --max-iterations 1
expect_success "events format jsonl writes events.jsonl" test -f "$state_events_jsonl/events.jsonl"
expect_success "events format jsonl omits events.log" test ! -f "$state_events_jsonl/events.log"

repo_events_both="$tmp_dir/repo-events-both"
state_events_both="$repo_events_both/.codex/ralph-loop"
make_repo "$repo_events_both"
expect_success "events format both run completes" quietly run_loop review_ship_complete --cwd "$repo_events_both" --state-dir "$state_events_both" --prompt "work" --acceptance-file "$acceptance_file" --events-format both --max-iterations 1
expect_success "events format both writes events.log" test -f "$state_events_both/events.log"
expect_success "events format both writes events.jsonl" test -f "$state_events_both/events.jsonl"

repo_progress_artifact="$tmp_dir/repo-progress-artifact"
state_progress_artifact="$repo_progress_artifact/.codex/ralph-loop"
make_repo "$repo_progress_artifact"
expect_success "progress artifact run completes" quietly run_loop review_ship_complete --cwd "$repo_progress_artifact" --state-dir "$state_progress_artifact" --prompt "work" --acceptance-file "$acceptance_file" --max-iterations 1 --progress-artifact
expect_success "progress artifact iteration file exists" test -f "$state_progress_artifact/progress/iteration-1.txt"

repo_lock_ok="$tmp_dir/repo-lock-ok"
state_lock_ok="$repo_lock_ok/.codex/ralph-loop"
make_repo "$repo_lock_ok"
mkdir -p "$state_lock_ok/.lock"
printf '%s\n%s\n%s\n%s\n' \
  'PID=999999' \
  'RUN_ID=prior-run' \
  'STARTED_AT=2026-01-01T00:00:00Z' \
  'CWD=/tmp/old' > "$state_lock_ok/.lock/meta.env"
expect_success "stale lock with dead pid auto-reclaims" quietly run_loop work_in_progress --cwd "$repo_lock_ok" --state-dir "$state_lock_ok" --prompt "x" --acceptance-file "$acceptance_file" --dry-run

repo_lock_bad="$tmp_dir/repo-lock-bad"
state_lock_bad="$repo_lock_bad/.codex/ralph-loop"
make_repo "$repo_lock_bad"
mkdir -p "$state_lock_bad/.lock"
printf 'oops\n' > "$state_lock_bad/.lock/meta.env"
expect_failure "malformed lock metadata blocks without reclaim flag" quietly run_loop work_in_progress --cwd "$repo_lock_bad" --state-dir "$state_lock_bad" --prompt "x" --acceptance-file "$acceptance_file" --dry-run
expect_success "malformed lock metadata can be reclaimed explicitly" quietly run_loop work_in_progress --cwd "$repo_lock_bad" --state-dir "$state_lock_bad" --prompt "x" --acceptance-file "$acceptance_file" --reclaim-stale-lock --dry-run

repo_resume="$tmp_dir/repo-resume"
state_resume="$repo_resume/.codex/ralph-loop"
make_repo "$repo_resume"
expect_success "initial timeout run leaves resumable state" quietly run_loop always_timeout --cwd "$repo_resume" --state-dir "$state_resume" --prompt "recover" --acceptance-file "$acceptance_file" --max-iterations 1 --idle-timeout-seconds 1 --hard-timeout-seconds 2 --timeout-retries 0
expect_success "resume after timeout completes" quietly run_loop review_ship_complete --cwd "$repo_resume" --state-dir "$state_resume" --resume --max-iterations 2 --idle-timeout-seconds 10 --hard-timeout-seconds 30
expect_contains "resume completion stop reason recorded" "task_complete" "$state_resume/run-summary.md"
expect_success "lock directory cleaned up after run" test ! -d "$state_resume/.lock"

printf '\nSmoke tests complete: %s passed, %s failed\n' "$pass_count" "$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
