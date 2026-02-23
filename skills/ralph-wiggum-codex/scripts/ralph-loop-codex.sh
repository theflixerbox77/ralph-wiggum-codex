#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="ralph-loop-codex.sh"
DEFAULT_MAX_ITERATIONS=20
DEFAULT_MAX_CONSECUTIVE_FAILURES=3
DEFAULT_MAX_STAGNANT_ITERATIONS=6

usage() {
  cat <<'USAGE'
Ralph Loop for Codex

Run iterative Codex execution loops with validation checks, adaptive feedback, and resumable state.

Usage:
  ralph-loop-codex.sh --cwd <dir> --prompt "text" [options]
  ralph-loop-codex.sh --cwd <dir> --prompt-file <file> [options]
  ralph-loop-codex.sh --cwd <dir> --objective-file <file> [options]
  ralph-loop-codex.sh --cwd <dir> --resume [options]

Core options:
  --cwd <dir>                      Repository/workspace to run Codex in (required)
  --prompt <text>                  Task prompt (required unless --prompt-file/--objective-file/--resume)
  --prompt-file <file>             File containing task prompt
  --objective-file <file>          File with objective text; reloaded every iteration
  --feedback-file <file>           Optional operator feedback file read each iteration
  --resume                          Resume from existing state in --state-dir
  --state-dir <dir>                State directory (default: <cwd>/.codex/ralph-loop)
  --completion-promise <text>      Stop only when exact output is <promise>text</promise>
  --max-iterations <n>             Stop after n iterations (default: 20, 0 = unbounded)
  --allow-unbounded                Allow infinite run only when max-iterations=0
  --max-consecutive-failures <n>   Stop after n consecutive codex failures (default: 3)
  --max-stagnant-iterations <n>    Stop after n repeated outputs (default: 6, 0 = disabled)
  --sleep-seconds <n>              Sleep between iterations (default: 0)

Harness and safety options:
  --autonomy-level <l0|l1|l2|l3>   Risk profile label (default: l2)
  --source-of-truth <path-or-url>  File/URL that defines requirements (repeatable)
  --preflight-cmd <command>        Command to run once before loop starts (repeatable)
  --validate-cmd <command>         Command to run after each iteration (repeatable)
  --stop-file <path>               Sentinel file that stops loop if present

Codex execution options:
  --sandbox <mode>                 codex exec sandbox mode (read-only/workspace-write/danger-full-access)
  --model <model>                  Model override for codex exec
  --profile <profile>              Profile override for codex exec
  --full-auto                      Pass --full-auto to codex exec
  --dangerous                      Pass --dangerously-bypass-approvals-and-sandbox to codex exec
  --codex-arg <arg>                Additional argument passed to codex exec (repeatable)

Utility options:
  --dry-run                        Print resolved config and exit
  -h, --help                       Show this help

Examples:
  ralph-loop-codex.sh \
    --cwd /repo \
    --prompt "Implement auth flow with tests" \
    --completion-promise "DONE" \
    --max-iterations 25 \
    --validate-cmd "npm run lint" \
    --validate-cmd "npm run build"

  ralph-loop-codex.sh --cwd /repo --resume

Manual stop:
  touch <state-dir>/STOP
USAGE
}

note() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

encode_b64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

decode_b64() {
  printf '%s' "$1" | base64 --decode 2>/dev/null || printf '%s' "$1" | base64 -D 2>/dev/null
}

trim_ws() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_lines_file() {
  local file_path="$1"
  local -n out_arr="$2"
  out_arr=()
  if [[ -f "$file_path" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && out_arr+=("$line")
    done < "$file_path"
  fi
}

write_lines_file() {
  local file_path="$1"
  shift
  : > "$file_path"
  local item
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    printf '%s\n' "$item" >> "$file_path"
  done
}

run_id=""
cwd=""
state_dir=""
state_file=""
prompt_file_saved=""
history_file=""
auto_feedback_file=""
validate_file=""
preflight_file=""
source_of_truth_file=""
codex_args_file=""
events_file=""
last_message_file=""
summary_file=""
stop_file=""
lock_dir=""

prompt=""
prompt_file=""
objective_file=""
feedback_file=""
completion_promise=""
max_iterations="$DEFAULT_MAX_ITERATIONS"
max_consecutive_failures="$DEFAULT_MAX_CONSECUTIVE_FAILURES"
max_stagnant_iterations="$DEFAULT_MAX_STAGNANT_ITERATIONS"
autonomy_level="l2"
sandbox=""
model=""
profile=""
sleep_seconds=0

resume=0
allow_unbounded=0
full_auto=0
dangerous=0
dry_run=0

provided_max_iterations=0
provided_completion_promise=0
provided_validate=0
provided_preflight=0
provided_source_of_truth=0
provided_codex_arg=0
provided_autonomy=0
provided_sandbox=0
provided_objective_file=0
provided_feedback_file=0
provided_max_stagnant_iterations=0
provided_sleep_seconds=0

validate_cmds=()
preflight_cmds=()
source_of_truth=()
codex_extra_args=()

active=1
iteration=1
consecutive_failures=0
stagnant_iterations=0
last_output_hash=""
started_at=""
last_event_at=""
stop_reason=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)
      cwd="${2:-}"
      shift 2
      ;;
    --state-dir)
      state_dir="${2:-}"
      shift 2
      ;;
    --prompt)
      prompt="${2:-}"
      shift 2
      ;;
    --prompt-file)
      prompt_file="${2:-}"
      shift 2
      ;;
    --objective-file)
      objective_file="${2:-}"
      provided_objective_file=1
      shift 2
      ;;
    --feedback-file)
      feedback_file="${2:-}"
      provided_feedback_file=1
      shift 2
      ;;
    --completion-promise)
      completion_promise="${2:-}"
      provided_completion_promise=1
      shift 2
      ;;
    --max-iterations)
      max_iterations="${2:-}"
      provided_max_iterations=1
      shift 2
      ;;
    --max-consecutive-failures)
      max_consecutive_failures="${2:-}"
      shift 2
      ;;
    --max-stagnant-iterations)
      max_stagnant_iterations="${2:-}"
      provided_max_stagnant_iterations=1
      shift 2
      ;;
    --sleep-seconds)
      sleep_seconds="${2:-}"
      provided_sleep_seconds=1
      shift 2
      ;;
    --autonomy-level)
      autonomy_level="${2:-}"
      provided_autonomy=1
      shift 2
      ;;
    --source-of-truth)
      source_of_truth+=("${2:-}")
      provided_source_of_truth=1
      shift 2
      ;;
    --preflight-cmd)
      preflight_cmds+=("${2:-}")
      provided_preflight=1
      shift 2
      ;;
    --validate-cmd)
      validate_cmds+=("${2:-}")
      provided_validate=1
      shift 2
      ;;
    --sandbox)
      sandbox="${2:-}"
      provided_sandbox=1
      shift 2
      ;;
    --model)
      model="${2:-}"
      shift 2
      ;;
    --profile)
      profile="${2:-}"
      shift 2
      ;;
    --codex-arg)
      codex_extra_args+=("${2:-}")
      provided_codex_arg=1
      shift 2
      ;;
    --stop-file)
      stop_file="${2:-}"
      shift 2
      ;;
    --resume)
      resume=1
      shift
      ;;
    --allow-unbounded)
      allow_unbounded=1
      shift
      ;;
    --full-auto)
      full_auto=1
      shift
      ;;
    --dangerous)
      dangerous=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$cwd" ]] || die "--cwd is required"
[[ -d "$cwd" ]] || die "--cwd does not exist: $cwd"

if [[ -z "$state_dir" ]]; then
  state_dir="$cwd/.codex/ralph-loop"
fi

state_file="$state_dir/state.env"
prompt_file_saved="$state_dir/prompt.txt"
history_file="$state_dir/iteration-history.md"
auto_feedback_file="$state_dir/auto-feedback.md"
validate_file="$state_dir/validate-cmds.txt"
preflight_file="$state_dir/preflight-cmds.txt"
source_of_truth_file="$state_dir/source-of-truth.txt"
codex_args_file="$state_dir/codex-args.txt"
events_file="$state_dir/events.log"
last_message_file="$state_dir/last-message.txt"
summary_file="$state_dir/run-summary.md"

if [[ -z "$stop_file" ]]; then
  stop_file="$state_dir/STOP"
fi

if [[ -z "$feedback_file" ]]; then
  feedback_file="$state_dir/feedback.md"
fi

lock_dir="$state_dir/.lock"

case "$autonomy_level" in
  l0|l1|l2|l3)
    ;;
  *)
    die "--autonomy-level must be one of: l0, l1, l2, l3"
    ;;
esac

if ! [[ "$max_iterations" =~ ^[0-9]+$ ]]; then
  die "--max-iterations must be an integer >= 0"
fi

if ! [[ "$max_consecutive_failures" =~ ^[0-9]+$ ]] || [[ "$max_consecutive_failures" -lt 1 ]]; then
  die "--max-consecutive-failures must be an integer >= 1"
fi

if ! [[ "$max_stagnant_iterations" =~ ^[0-9]+$ ]]; then
  die "--max-stagnant-iterations must be an integer >= 0"
fi

if ! [[ "$sleep_seconds" =~ ^[0-9]+$ ]]; then
  die "--sleep-seconds must be an integer >= 0"
fi

if [[ "$resume" -eq 1 ]]; then
  [[ -f "$state_file" ]] || die "Cannot resume: missing state file at $state_file"
  [[ -f "$prompt_file_saved" ]] || die "Cannot resume: missing prompt file at $prompt_file_saved"
  [[ -z "$prompt" ]] || die "Do not provide --prompt when using --resume"
  [[ -z "$prompt_file" ]] || die "Do not provide --prompt-file when using --resume"

  # shellcheck disable=SC1090
  source "$state_file"

  prompt="$(cat "$prompt_file_saved")"
  completion_promise="$(decode_b64 "${COMPLETION_PROMISE_B64:-}")"

  if [[ "$provided_max_iterations" -eq 0 ]]; then
    max_iterations="${MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
  fi

  if [[ "$provided_completion_promise" -eq 0 ]]; then
    completion_promise="$(decode_b64 "${COMPLETION_PROMISE_B64:-}")"
  fi

  if [[ "$provided_autonomy" -eq 0 ]]; then
    autonomy_level="${AUTONOMY_LEVEL:-l2}"
  fi

  if [[ "$provided_objective_file" -eq 0 ]]; then
    objective_file="${OBJECTIVE_FILE:-}"
  fi

  if [[ "$provided_feedback_file" -eq 0 ]]; then
    feedback_file="${FEEDBACK_FILE:-$feedback_file}"
  fi

  if [[ "$provided_sandbox" -eq 0 ]]; then
    sandbox="${SANDBOX:-}"
  fi

  if [[ "$provided_max_stagnant_iterations" -eq 0 ]]; then
    max_stagnant_iterations="${MAX_STAGNANT_ITERATIONS:-$DEFAULT_MAX_STAGNANT_ITERATIONS}"
  fi

  if [[ "$provided_sleep_seconds" -eq 0 ]]; then
    sleep_seconds="${SLEEP_SECONDS:-0}"
  fi

  if [[ -z "$model" ]]; then
    model="${MODEL:-}"
  fi

  if [[ -z "$profile" ]]; then
    profile="${PROFILE:-}"
  fi

  iteration="${ITERATION:-1}"
  consecutive_failures="${CONSECUTIVE_FAILURES:-0}"
  stagnant_iterations="${STAGNANT_ITERATIONS:-0}"
  last_output_hash="${LAST_OUTPUT_HASH:-}"
  started_at="${STARTED_AT:-$(now_utc)}"
  run_id="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"

  if [[ "$provided_validate" -eq 0 ]]; then
    read_lines_file "$validate_file" validate_cmds
  fi
  if [[ "$provided_preflight" -eq 0 ]]; then
    read_lines_file "$preflight_file" preflight_cmds
  fi
  if [[ "$provided_source_of_truth" -eq 0 ]]; then
    read_lines_file "$source_of_truth_file" source_of_truth
  fi
  if [[ "$provided_codex_arg" -eq 0 ]]; then
    read_lines_file "$codex_args_file" codex_extra_args
  fi

  note "Resuming run: $run_id (starting at iteration $iteration)"
else
  [[ -n "$prompt" || -n "$prompt_file" || -n "$objective_file" ]] || die "Provide --prompt, --prompt-file, or --objective-file"
  [[ -z "$prompt" || -z "$prompt_file" ]] || die "Use only one of --prompt or --prompt-file"

  if [[ -n "$prompt_file" ]]; then
    [[ -f "$prompt_file" ]] || die "--prompt-file does not exist: $prompt_file"
    prompt="$(cat "$prompt_file")"
  fi

  if [[ -n "$objective_file" ]]; then
    [[ -f "$objective_file" ]] || die "--objective-file does not exist: $objective_file"
    prompt="$(cat "$objective_file")"
  fi

  [[ -n "$prompt" ]] || die "Prompt is empty"

  if [[ -z "$sandbox" ]]; then
    case "$autonomy_level" in
      l0) sandbox="read-only" ;;
      l1|l2|l3) sandbox="workspace-write" ;;
    esac
  fi

  if [[ "$max_iterations" -eq 0 && -z "$completion_promise" && "$allow_unbounded" -ne 1 ]]; then
    die "Unbounded loop requires either --completion-promise or --allow-unbounded"
  fi

  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  started_at="$(now_utc)"
  iteration=1
  consecutive_failures=0
  stagnant_iterations=0
  last_output_hash=""
fi

mkdir -p "$state_dir"

if mkdir "$lock_dir" 2>/dev/null; then
  :
else
  die "Another loop is already active (lock exists: $lock_dir)"
fi

cleanup_lock() {
  rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup_lock EXIT

log_event() {
  local event="$1"
  local detail="${2:-}"
  local ts
  ts="$(now_utc)"
  last_event_at="$ts"
  printf '%s\titeration=%s\tevent=%s\tdetail=%s\n' "$ts" "$iteration" "$event" "$detail" >> "$events_file"
}

save_state() {
  local promise_b64
  promise_b64="$(encode_b64 "$completion_promise")"

  cat > "$state_file" <<EOF_STATE
ACTIVE=$active
ITERATION=$iteration
CONSECUTIVE_FAILURES=$consecutive_failures
STAGNANT_ITERATIONS=$stagnant_iterations
MAX_ITERATIONS=$max_iterations
MAX_CONSECUTIVE_FAILURES=$max_consecutive_failures
MAX_STAGNANT_ITERATIONS=$max_stagnant_iterations
AUTONOMY_LEVEL=$autonomy_level
SANDBOX=$(printf '%q' "$sandbox")
MODEL=$(printf '%q' "$model")
PROFILE=$(printf '%q' "$profile")
RUN_ID=$(printf '%q' "$run_id")
STARTED_AT=$(printf '%q' "$started_at")
LAST_EVENT_AT=$(printf '%q' "$last_event_at")
LAST_OUTPUT_HASH=$(printf '%q' "$last_output_hash")
COMPLETION_PROMISE_B64=$(printf '%q' "$promise_b64")
OBJECTIVE_FILE=$(printf '%q' "$objective_file")
FEEDBACK_FILE=$(printf '%q' "$feedback_file")
SLEEP_SECONDS=$sleep_seconds
EOF_STATE
}

write_summary() {
  local reason="$1"

  cat > "$summary_file" <<EOF_SUMMARY
# Ralph Loop Run Summary

- Run ID: $run_id
- Started: $started_at
- Finished: $(now_utc)
- Stop reason: $reason
- Final iteration: $iteration
- Consecutive failures: $consecutive_failures
- Stagnant iterations: $stagnant_iterations
- Working directory: $cwd
- State directory: $state_dir
- Events log: $events_file
- Last message: $last_message_file
- Iteration history: $history_file
- Feedback file: $feedback_file
- Auto feedback file: $auto_feedback_file

## Configuration

- Autonomy level: $autonomy_level
- Sandbox: $sandbox
- Max iterations: $max_iterations
- Completion promise: ${completion_promise:-"(none)"}
- Max consecutive failures: $max_consecutive_failures
- Max stagnant iterations: $max_stagnant_iterations
- Sleep seconds: $sleep_seconds
- Objective file: ${objective_file:-"(none)"}

## Validation commands
$(if [[ ${#validate_cmds[@]} -eq 0 ]]; then echo '- (none)'; else printf -- '- `%s`\n' "${validate_cmds[@]}"; fi)

## Source of truth
$(if [[ ${#source_of_truth[@]} -eq 0 ]]; then echo '- (none)'; else printf -- '- `%s`\n' "${source_of_truth[@]}"; fi)
EOF_SUMMARY
}

build_source_block() {
  if [[ ${#source_of_truth[@]} -eq 0 ]]; then
    printf '%s\n' '- (none declared)'
    return
  fi

  local item
  for item in "${source_of_truth[@]}"; do
    printf -- '- %s\n' "$item"
  done
}

build_validation_block() {
  if [[ ${#validate_cmds[@]} -eq 0 ]]; then
    printf '%s\n' '- (none declared)'
    return
  fi

  local item
  for item in "${validate_cmds[@]}"; do
    printf -- '- %s\n' "$item"
  done
}

hash_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return
  fi
  shasum -a 256 | awk '{print $1}'
}

resolve_objective() {
  local current_objective="$prompt"

  if [[ -n "$objective_file" ]]; then
    if [[ -f "$objective_file" ]]; then
      current_objective="$(cat "$objective_file")"
      current_objective="$(trim_ws "$current_objective")"
      [[ -n "$current_objective" ]] || die "--objective-file is empty: $objective_file"
    else
      warn "Objective file not found during iteration: $objective_file (using last known objective)"
    fi
  fi

  printf '%s' "$current_objective"
}

build_feedback_block() {
  local has_feedback=0

  if [[ -f "$feedback_file" && -s "$feedback_file" ]]; then
    has_feedback=1
    printf 'Operator feedback (%s):\n' "$feedback_file"
    tail -n 80 "$feedback_file"
    printf '\n'
  fi

  if [[ -f "$auto_feedback_file" && -s "$auto_feedback_file" ]]; then
    has_feedback=1
    printf 'Auto feedback (%s):\n' "$auto_feedback_file"
    tail -n 80 "$auto_feedback_file"
    printf '\n'
  fi

  if [[ "$has_feedback" -eq 0 ]]; then
    printf '%s\n' '- (none)'
  fi
}

build_recent_history_block() {
  if [[ -f "$history_file" ]]; then
    tail -n 120 "$history_file"
    return
  fi

  printf '%s\n' '- (no prior iteration memory yet)'
}

append_iteration_history() {
  local codex_status="$1"
  local validation_status="$2"
  local completion_status="$3"

  {
    printf '%s\n' '---'
    printf 'iteration=%s timestamp=%s codex_exit=%s validation=%s completion=%s stagnant=%s\n' \
      "$iteration" "$(now_utc)" "$codex_status" "$validation_status" "$completion_status" "$stagnant_iterations"
    printf 'objective_file=%s feedback_file=%s\n' "${objective_file:-"(none)"}" "$feedback_file"
    printf 'last_message_tail:\n'
    if [[ -f "$last_message_file" ]]; then
      tail -n 60 "$last_message_file"
    else
      printf '%s\n' '(none)'
    fi
    printf '%s\n\n' ''
  } >> "$history_file"
}

refresh_auto_feedback() {
  local codex_status="$1"
  local validation_status="$2"
  local completion_status="$3"

  if [[ "$completion_status" == "yes" ]]; then
    rm -f "$auto_feedback_file"
    return
  fi

  if [[ "$codex_status" != "0" ]]; then
    cat > "$auto_feedback_file" <<EOF_AUTO
Codex execution failed in iteration $iteration (exit=$codex_status).
- Inspect .codex/ralph-loop/events.log for context.
- Resolve tool/runtime failure first.
- Do not repeat the same command path without changes.
EOF_AUTO
    return
  fi

  if [[ "$validation_status" != "pass" ]]; then
    cat > "$auto_feedback_file" <<EOF_AUTO
Validation failed in iteration $iteration.
- Inspect .codex/ralph-loop/validation/iteration-$iteration/ logs.
- Fix failing checks before claiming completion.
- Prefer the smallest concrete change that turns checks green.
EOF_AUTO
    return
  fi

  rm -f "$auto_feedback_file"
}

pause_between_iterations() {
  if [[ "$sleep_seconds" -gt 0 ]]; then
    note "Sleeping $sleep_seconds second(s) before next iteration"
    sleep "$sleep_seconds"
  fi
}

run_cmd_in_cwd() {
  local command_string="$1"
  (
    cd "$cwd"
    bash -lc "$command_string"
  )
}

run_preflight() {
  command -v codex >/dev/null 2>&1 || die "codex CLI not found in PATH"

  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local dirty_count
    dirty_count="$(git -C "$cwd" status --porcelain | wc -l | tr -d ' ')"
    note "Git working tree detected; uncommitted entries: $dirty_count"
    log_event "preflight_git" "dirty_entries=$dirty_count"
  else
    warn "Working directory is not a git repository"
    log_event "preflight_git" "not_a_repo"
  fi

  local source
  for source in "${source_of_truth[@]}"; do
    if [[ "$source" =~ ^https?:// ]]; then
      continue
    fi

    if [[ -e "$source" || -e "$cwd/$source" ]]; then
      continue
    fi

    die "Source-of-truth path not found: $source"
  done

  local idx=0
  local cmd
  for cmd in "${preflight_cmds[@]}"; do
    idx=$((idx + 1))
    note "Preflight [$idx/${#preflight_cmds[@]}]: $cmd"
    if run_cmd_in_cwd "$cmd"; then
      log_event "preflight_ok" "$cmd"
    else
      log_event "preflight_fail" "$cmd"
      die "Preflight command failed: $cmd"
    fi
  done
}

run_validation_loop() {
  local validation_dir="$state_dir/validation/iteration-$iteration"
  mkdir -p "$validation_dir"

  local failed=0
  local idx=0
  local cmd
  for cmd in "${validate_cmds[@]}"; do
    idx=$((idx + 1))
    local log_file="$validation_dir/cmd-$idx.log"
    note "Validation [$idx/${#validate_cmds[@]}]: $cmd"

    if run_cmd_in_cwd "$cmd" >"$log_file" 2>&1; then
      log_event "validation_ok" "cmd=$cmd;log=$log_file"
    else
      failed=1
      warn "Validation failed: $cmd (see $log_file)"
      log_event "validation_fail" "cmd=$cmd;log=$log_file"
    fi
  done

  return "$failed"
}

build_iteration_prompt() {
  local source_block
  source_block="$(build_source_block)"

  local validation_block
  validation_block="$(build_validation_block)"

  local feedback_block
  feedback_block="$(build_feedback_block)"

  local recent_history_block
  recent_history_block="$(build_recent_history_block)"

  local completion_contract
  if [[ -n "$completion_promise" ]]; then
    completion_contract="- If and only if all requirements are satisfied and validations pass, respond with EXACTLY: <promise>$completion_promise</promise>"
  else
    completion_contract="- Do not emit <promise> tags; continue with concrete progress updates"
  fi

  cat <<EOF_PROMPT
Ralph Loop for Codex
Run ID: $run_id
Iteration: $iteration

Source of truth:
$source_block

Objective:
$prompt

Operating invariants:
- Follow source-of-truth artifacts over assumptions.
- Make the smallest effective change that advances objective completion.
- Preserve repository integrity (correctness, maintainability, explicit errors).
- Surface blockers with concrete evidence instead of guesswork.
- Avoid repeating an unchanged failed strategy.

Validation loop:
$validation_block

Recent iteration memory:
$recent_history_block

Feedback updates:
$feedback_block

Output contract:
$completion_contract
- If not complete, include:
  Status: IN_PROGRESS or BLOCKED
  Evidence:
  - command/result pairs from this iteration
  Next:
  - exactly one highest-impact next step
EOF_PROMPT
}

print_effective_config() {
  cat <<EOF_CONFIG
Ralph Loop Effective Configuration

run_id=$run_id
cwd=$cwd
state_dir=$state_dir
autonomy_level=$autonomy_level
sandbox=$sandbox
model=${model:-"(default)"}
profile=${profile:-"(default)"}
max_iterations=$max_iterations
max_consecutive_failures=$max_consecutive_failures
max_stagnant_iterations=$max_stagnant_iterations
sleep_seconds=$sleep_seconds
completion_promise=${completion_promise:-"(none)"}
stop_file=$stop_file
objective_file=${objective_file:-"(none)"}
feedback_file=$feedback_file

source_of_truth_count=${#source_of_truth[@]}
preflight_cmd_count=${#preflight_cmds[@]}
validate_cmd_count=${#validate_cmds[@]}
codex_extra_arg_count=${#codex_extra_args[@]}
EOF_CONFIG
}

write_lines_file "$validate_file" "${validate_cmds[@]-}"
write_lines_file "$preflight_file" "${preflight_cmds[@]-}"
write_lines_file "$source_of_truth_file" "${source_of_truth[@]-}"
write_lines_file "$codex_args_file" "${codex_extra_args[@]-}"
prompt="$(resolve_objective)"
printf '%s\n' "$prompt" > "$prompt_file_saved"

if [[ "$dry_run" -eq 1 ]]; then
  print_effective_config
  note "Dry run complete"
  exit 0
fi

note "Ralph loop started"
note "Run ID: $run_id"
note "State dir: $state_dir"
note "Stop file: $stop_file"
log_event "loop_start" "autonomy=$autonomy_level;sandbox=$sandbox"

run_preflight

active=1
save_state

while true; do
  if [[ -f "$stop_file" ]]; then
    stop_reason="stop_file_detected"
    log_event "stop" "$stop_reason"
    break
  fi

  if [[ "$max_iterations" -gt 0 && "$iteration" -gt "$max_iterations" ]]; then
    stop_reason="max_iterations_reached"
    log_event "stop" "$stop_reason"
    break
  fi

  prompt="$(resolve_objective)"
  printf '%s\n' "$prompt" > "$prompt_file_saved"
  local_prompt="$(build_iteration_prompt)"
  log_event "iteration_start" "iteration=$iteration"

  codex_cmd=(codex exec -C "$cwd" --output-last-message "$last_message_file")

  [[ -n "$sandbox" ]] && codex_cmd+=(--sandbox "$sandbox")
  [[ -n "$model" ]] && codex_cmd+=(--model "$model")
  [[ -n "$profile" ]] && codex_cmd+=(--profile "$profile")
  [[ "$full_auto" -eq 1 ]] && codex_cmd+=(--full-auto)
  [[ "$dangerous" -eq 1 ]] && codex_cmd+=(--dangerously-bypass-approvals-and-sandbox)

  if [[ ${#codex_extra_args[@]} -gt 0 ]]; then
    codex_cmd+=("${codex_extra_args[@]}")
  fi

  codex_cmd+=("$local_prompt")

  set +e
  "${codex_cmd[@]}"
  codex_exit=$?
  set -e

  if [[ "$codex_exit" -ne 0 ]]; then
    validation_status="skipped"
    completion_status="no"
    consecutive_failures=$((consecutive_failures + 1))
    warn "codex exec failed (exit=$codex_exit), consecutive failures=$consecutive_failures"
    log_event "codex_fail" "exit=$codex_exit"
    refresh_auto_feedback "$codex_exit" "$validation_status" "$completion_status"
    append_iteration_history "$codex_exit" "$validation_status" "$completion_status"

    if [[ "$consecutive_failures" -ge "$max_consecutive_failures" ]]; then
      stop_reason="max_consecutive_failures_reached"
      log_event "stop" "$stop_reason"
      break
    fi

    iteration=$((iteration + 1))
    save_state
    pause_between_iterations
    continue
  fi

  consecutive_failures=0
  log_event "codex_ok" "iteration=$iteration"

  validation_ok=1
  if [[ ${#validate_cmds[@]} -gt 0 ]]; then
    if run_validation_loop; then
      validation_ok=1
    else
      validation_ok=0
    fi
  fi
  if [[ "$validation_ok" -eq 1 ]]; then
    validation_status="pass"
  else
    validation_status="fail"
  fi

  completion_detected=0
  completion_status="no"
  normalized_output=""
  if [[ -f "$last_message_file" ]]; then
    raw_output="$(tr -d '\r' < "$last_message_file")"
    normalized_output="$(trim_ws "$raw_output")"
  fi

  if [[ -n "$completion_promise" && -n "$normalized_output" ]]; then
    expected_output="<promise>${completion_promise}</promise>"

    if [[ "$normalized_output" == "$expected_output" ]]; then
      completion_detected=1
      completion_status="yes"
      log_event "promise_detected" "$expected_output"
    fi
  fi

  if [[ -n "$normalized_output" ]]; then
    current_output_hash="$(printf '%s' "$normalized_output" | hash_text)"
    if [[ -n "$last_output_hash" && "$current_output_hash" == "$last_output_hash" ]]; then
      stagnant_iterations=$((stagnant_iterations + 1))
      log_event "stagnant_output" "count=$stagnant_iterations"
    else
      stagnant_iterations=0
    fi
    last_output_hash="$current_output_hash"
  else
    stagnant_iterations=0
    last_output_hash=""
  fi

  refresh_auto_feedback "$codex_exit" "$validation_status" "$completion_status"
  append_iteration_history "$codex_exit" "$validation_status" "$completion_status"

  if [[ "$completion_detected" -eq 1 && "$validation_ok" -eq 1 ]]; then
    stop_reason="completion_promise_detected"
    log_event "stop" "$stop_reason"
    break
  fi

  if [[ "$completion_detected" -eq 1 && "$validation_ok" -eq 0 ]]; then
    warn "Completion promise detected but validation failed; continuing loop"
    log_event "promise_rejected" "validation_failed"
  fi

  if [[ "$max_stagnant_iterations" -gt 0 && "$stagnant_iterations" -ge "$max_stagnant_iterations" ]]; then
    stop_reason="max_stagnant_iterations_reached"
    log_event "stop" "$stop_reason"
    break
  fi

  iteration=$((iteration + 1))
  save_state
  pause_between_iterations
done

active=0
save_state
write_summary "$stop_reason"

note "Ralph loop stopped: $stop_reason"
note "Summary: $summary_file"
note "Events:  $events_file"
