#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="ralph-loop-codex.sh"
DEFAULT_MAX_ITERATIONS=20
DEFAULT_MAX_CONSECUTIVE_FAILURES=3
DEFAULT_MAX_STAGNANT_ITERATIONS=6
DEFAULT_IDLE_TIMEOUT_SECONDS=900
DEFAULT_HARD_TIMEOUT_SECONDS=7200
DEFAULT_TIMEOUT_RETRIES=1

usage() {
  cat <<'USAGE'
Ralph Objective-First Loop for Codex

Run an objective-first Ralph loop with fresh-context work/review phases, file-backed state,
optional verification commands, and resumable progress.

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
  --acceptance-file <file>         File with acceptance criteria; reloaded every iteration
  --feedback-file <file>           Optional operator feedback file read each iteration
  --resume                         Resume from existing state in --state-dir
  --state-dir <dir>                State directory (default: <cwd>/.codex/ralph-loop)
  --max-iterations <n>             Stop after n iterations (default: 20, 0 = unbounded)
  --allow-unbounded                Allow infinite run only when max-iterations=0
  --max-consecutive-failures <n>   Stop after n consecutive codex phase failures (default: 3)
  --max-stagnant-iterations <n>    Stop after n repeated work/review outputs (default: 6, 0 = disabled)
  --sleep-seconds <n>              Sleep between iterations (default: 0)

Harness and safety options:
  --autonomy-level <l0|l1|l2|l3>   Risk profile label (default: l2)
  --source-of-truth <path-or-url>  File/URL that defines requirements (repeatable)
  --preflight-cmd <command>        Command to run once before loop starts (repeatable)
  --validate-cmd <command>         Optional verification command run after each work phase (repeatable)
  --progress-scope <pathspec>      Git pathspec used to measure scoped progress (repeatable, default: .)
  --stop-file <path>               Sentinel file that stops loop if present
  --reclaim-stale-lock             Force reclaim existing lock even if metadata is missing/corrupt

Codex execution options:
  --codex-bin <path-or-name>       Codex CLI binary to execute (default: codex)
  --sandbox <mode>                 worker codex exec sandbox mode (read-only/workspace-write/danger-full-access)
  --model <model>                  worker model override for codex exec
  --profile <profile>              worker profile override for codex exec
  --review-model <model>           reviewer model override (defaults to worker model)
  --review-profile <profile>       reviewer profile override (defaults to worker profile)
  --idle-timeout-seconds <n>       Kill codex exec when JSON stream is idle for n seconds (default: 900, 0=disabled)
  --hard-timeout-seconds <n>       Kill codex exec when total runtime exceeds n seconds (default: 7200, 0=disabled)
  --timeout-retries <n>            Retry timeout-killed codex exec attempts n times (default: 1)
  --events-format <tsv|jsonl|both> Event log format (default: both)
  --progress-artifact              Write per-iteration scoped progress artifacts under <state-dir>/progress/
  --full-auto                      Pass --full-auto to worker and reviewer codex exec
  --dangerous                      Pass --dangerously-bypass-approvals-and-sandbox to worker codex exec
  --codex-arg <arg>                Additional argument passed to worker and reviewer codex exec (repeatable)

Utility options:
  --dry-run                        Print resolved config and exit
  -h, --help                       Show this help

Examples:
  ralph-loop-codex.sh \
    --cwd /repo \
    --prompt "Implement auth flow" \
    --acceptance-file /repo/.codex/ralph-loop/acceptance-criteria.md \
    --validate-cmd "npm test" \
    --max-iterations 25

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

trim_ws() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_lines_file() {
  local file_path="$1"
  local out_var="$2"
  eval "$out_var=()"
  if [[ -f "$file_path" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local quoted_line
      printf -v quoted_line '%q' "$line"
      eval "$out_var+=($quoted_line)"
    done < "$file_path"
  fi
}

write_lines_file_from_array() {
  local file_path="$1"
  local array_name="$2"
  : > "$file_path"
  local array_len=0
  eval "array_len=\${#$array_name[@]}"
  if [[ "$array_len" -eq 0 ]]; then
    return
  fi
  local idx=0
  local item=""
  for ((idx=0; idx<array_len; idx++)); do
    eval "item=\${$array_name[$idx]}"
    [[ -n "$item" ]] || continue
    printf '%s\n' "$item" >> "$file_path"
  done
}

hash_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return
  fi
  shasum -a 256 | awk '{print $1}'
}

run_cmd_in_cwd() {
  local command_string="$1"
  (
    cd "$cwd"
    bash -lc "$command_string"
  )
}

run_cmd_in_cwd_ro() {
  local command_string="$1"
  (
    cd "$cwd"
    bash -lc "$command_string"
  )
}

write_text_file() {
  local file_path="$1"
  local content="$2"
  printf '%s\n' "$content" > "$file_path"
}

read_text_file_or_empty() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    cat "$file_path"
  fi
}

tail_or_placeholder() {
  local file_path="$1"
  local lines="${2:-80}"
  local placeholder="${3:-- (none)}"
  if [[ -f "$file_path" && -s "$file_path" ]]; then
    tail -n "$lines" "$file_path"
  else
    printf '%s\n' "$placeholder"
  fi
}

run_id=""
cwd=""
state_dir=""
state_file=""
history_file=""
auto_feedback_file=""
validate_file=""
preflight_file=""
source_of_truth_file=""
progress_scope_file=""
codex_args_file=""
events_file=""
events_jsonl_file=""
summary_file=""
stop_file=""
lock_dir=""
lock_meta_file=""
codex_log_dir=""
progress_artifact_dir=""
state_dir_rel=""

objective_state_file=""
acceptance_state_file=""
feedback_state_file=""
work_summary_file=""
review_feedback_file=""
review_result_file=""
blocked_file=""
complete_marker_file=""
work_schema_file=""
review_schema_file=""
work_last_message_file=""
review_last_message_file=""

prompt=""
prompt_file=""
objective_file=""
acceptance_file=""
feedback_file=""
max_iterations="$DEFAULT_MAX_ITERATIONS"
max_consecutive_failures="$DEFAULT_MAX_CONSECUTIVE_FAILURES"
max_stagnant_iterations="$DEFAULT_MAX_STAGNANT_ITERATIONS"
autonomy_level="l2"
sandbox=""
codex_bin="codex"
resolved_codex_bin=""
model=""
profile=""
review_model=""
review_profile=""
sleep_seconds=0
idle_timeout_seconds="$DEFAULT_IDLE_TIMEOUT_SECONDS"
hard_timeout_seconds="$DEFAULT_HARD_TIMEOUT_SECONDS"
timeout_retries="$DEFAULT_TIMEOUT_RETRIES"
events_format="both"
progress_artifact=0

resume=0
allow_unbounded=0
full_auto=0
dangerous=0
dry_run=0
reclaim_stale_lock=0

provided_max_iterations=0
provided_validate=0
provided_preflight=0
provided_source_of_truth=0
provided_progress_scope=0
provided_codex_arg=0
provided_autonomy=0
provided_sandbox=0
provided_objective_file=0
provided_acceptance_file=0
provided_feedback_file=0
provided_max_stagnant_iterations=0
provided_sleep_seconds=0
provided_idle_timeout_seconds=0
provided_hard_timeout_seconds=0
provided_timeout_retries=0
provided_codex_bin=0
provided_events_format=0
provided_progress_artifact=0
provided_review_model=0
provided_review_profile=0

validate_cmds=()
preflight_cmds=()
source_of_truth=()
progress_scopes=()
codex_extra_args=()

active=1
iteration=1
consecutive_failures=0
stagnant_iterations=0
last_output_hash=""
started_at=""
last_event_at=""
stop_reason=""
is_git_repo=0
attempt_timeout_reason=""

current_objective=""
current_acceptance=""
current_validation_status="not_run"
current_validation_summary="- (not run)"
current_progress_status="pass"
current_no_change_justification=""
current_changed_paths=""
current_changed_path_count=0
current_changed_path_preview="(none)"

work_status_value=""
work_assessment_value=""
work_evidence_value=""
work_next_step_value=""
work_blocker_reason_value=""
review_decision_value=""
review_assessment_value=""
review_feedback_value=""
review_evidence_value=""

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
    --acceptance-file)
      acceptance_file="${2:-}"
      provided_acceptance_file=1
      shift 2
      ;;
    --feedback-file)
      feedback_file="${2:-}"
      provided_feedback_file=1
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
    --idle-timeout-seconds)
      idle_timeout_seconds="${2:-}"
      provided_idle_timeout_seconds=1
      shift 2
      ;;
    --hard-timeout-seconds)
      hard_timeout_seconds="${2:-}"
      provided_hard_timeout_seconds=1
      shift 2
      ;;
    --timeout-retries)
      timeout_retries="${2:-}"
      provided_timeout_retries=1
      shift 2
      ;;
    --events-format)
      events_format="${2:-}"
      provided_events_format=1
      shift 2
      ;;
    --progress-artifact)
      progress_artifact=1
      provided_progress_artifact=1
      shift
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
    --progress-scope)
      progress_scopes+=("${2:-}")
      provided_progress_scope=1
      shift 2
      ;;
    --sandbox)
      sandbox="${2:-}"
      provided_sandbox=1
      shift 2
      ;;
    --codex-bin)
      codex_bin="${2:-}"
      provided_codex_bin=1
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
    --review-model)
      review_model="${2:-}"
      provided_review_model=1
      shift 2
      ;;
    --review-profile)
      review_profile="${2:-}"
      provided_review_profile=1
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
    --reclaim-stale-lock)
      reclaim_stale_lock=1
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

if [[ "$state_dir" == "$cwd" ]]; then
  state_dir_rel="."
elif [[ "$state_dir" == "$cwd/"* ]]; then
  state_dir_rel="${state_dir#$cwd/}"
fi

state_file="$state_dir/state.env"
history_file="$state_dir/iteration-history.md"
auto_feedback_file="$state_dir/auto-feedback.md"
validate_file="$state_dir/validate-cmds.txt"
preflight_file="$state_dir/preflight-cmds.txt"
source_of_truth_file="$state_dir/source-of-truth.txt"
progress_scope_file="$state_dir/progress-scopes.txt"
codex_args_file="$state_dir/codex-args.txt"
events_file="$state_dir/events.log"
events_jsonl_file="$state_dir/events.jsonl"
summary_file="$state_dir/run-summary.md"
codex_log_dir="$state_dir/codex"
progress_artifact_dir="$state_dir/progress"

objective_state_file="$state_dir/objective.md"
acceptance_state_file="$state_dir/acceptance-criteria.md"
feedback_state_file="$state_dir/feedback.md"
work_summary_file="$state_dir/work-summary.md"
review_feedback_file="$state_dir/review-feedback.md"
review_result_file="$state_dir/review-result.txt"
blocked_file="$state_dir/RALPH-BLOCKED.md"
complete_marker_file="$state_dir/.ralph-complete"
work_schema_file="$state_dir/work-schema.json"
review_schema_file="$state_dir/review-schema.json"
work_last_message_file="$state_dir/work-last-message.txt"
review_last_message_file="$state_dir/review-last-message.txt"

if [[ -z "$stop_file" ]]; then
  stop_file="$state_dir/STOP"
fi

if [[ -z "$feedback_file" ]]; then
  feedback_file="$feedback_state_file"
fi

lock_dir="$state_dir/.lock"
lock_meta_file="$lock_dir/meta.env"

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

if ! [[ "$idle_timeout_seconds" =~ ^[0-9]+$ ]]; then
  die "--idle-timeout-seconds must be an integer >= 0"
fi

if ! [[ "$hard_timeout_seconds" =~ ^[0-9]+$ ]]; then
  die "--hard-timeout-seconds must be an integer >= 0"
fi

if ! [[ "$timeout_retries" =~ ^[0-9]+$ ]]; then
  die "--timeout-retries must be an integer >= 0"
fi

case "$events_format" in
  tsv|jsonl|both)
    ;;
  *)
    die "--events-format must be one of: tsv, jsonl, both"
    ;;
esac

if ! [[ "$progress_artifact" =~ ^[01]$ ]]; then
  die "--progress-artifact internal state must be 0 or 1"
fi

log_event() {
  local event="$1"
  local detail="${2:-}"
  local ts
  ts="$(now_utc)"
  last_event_at="$ts"

  if [[ "$events_format" == "tsv" || "$events_format" == "both" ]]; then
    printf '%s\titeration=%s\tevent=%s\tdetail=%s\n' "$ts" "$iteration" "$event" "$detail" >> "$events_file"
  fi

  if [[ "$events_format" == "jsonl" || "$events_format" == "both" ]]; then
    python3 - "$ts" "$iteration" "$event" "$detail" <<'PY' >> "$events_jsonl_file"
import json
import sys

ts, iteration, event, detail = sys.argv[1:5]
print(json.dumps({
    "timestamp": ts,
    "iteration": int(iteration),
    "event": event,
    "detail": detail,
}, ensure_ascii=True))
PY
  fi
}

lock_pid_from_meta() {
  local meta_file="$1"
  [[ -f "$meta_file" ]] || return 1
  local pid_line
  pid_line="$(grep '^PID=' "$meta_file" | tail -n 1 || true)"
  [[ -n "$pid_line" ]] || return 1
  local pid="${pid_line#PID=}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$pid"
}

is_pid_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

reclaim_existing_lock_if_stale() {
  [[ -d "$lock_dir" ]] || return 0
  local lock_pid=""
  if lock_pid="$(lock_pid_from_meta "$lock_meta_file")"; then
    if is_pid_alive "$lock_pid"; then
      die "Another loop is already active (lock exists: $lock_dir, pid=$lock_pid)"
    fi
    warn "Reclaiming stale lock (dead pid=$lock_pid): $lock_dir"
    rm -rf "$lock_dir"
    return 0
  fi

  if [[ "$reclaim_stale_lock" -eq 1 ]]; then
    warn "Reclaiming lock with invalid metadata (--reclaim-stale-lock): $lock_dir"
    rm -rf "$lock_dir"
    return 0
  fi

  die "Lock exists with invalid metadata ($lock_meta_file). Use --reclaim-stale-lock to force reclaim."
}

status_line_to_path() {
  local line="$1"
  local path="${line:3}"
  path="${path#\"}"
  path="${path%\"}"
  if [[ "$path" == *" -> "* ]]; then
    path="${path##* -> }"
    path="${path#\"}"
    path="${path%\"}"
  fi
  printf '%s' "$path"
}

scoped_status_output() {
  if [[ "$is_git_repo" -ne 1 ]]; then
    printf '%s' ""
    return 0
  fi

  local status_output=""
  if ! status_output="$(git -C "$cwd" status --porcelain -- "${progress_scopes[@]}")"; then
    die "Failed to compute progress scope status for: ${progress_scopes[*]}"
  fi

  if [[ -n "$state_dir_rel" && "$state_dir_rel" != "." ]]; then
    local filtered_lines=()
    local line=""
    local path=""
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      path="$(status_line_to_path "$line")"
      if [[ "$path" == "$state_dir_rel" || "$path" == "$state_dir_rel/"* ]]; then
        continue
      fi
      filtered_lines+=("$line")
    done <<< "$status_output"
    if [[ ${#filtered_lines[@]} -eq 0 ]]; then
      status_output=""
    else
      status_output="$(printf '%s\n' "${filtered_lines[@]}")"
    fi
  fi

  printf '%s' "$status_output"
}

status_output_hash() {
  local status_output="$1"
  printf '%s' "$status_output" | hash_text
}

count_nonempty_lines() {
  local text="$1"
  local count=0
  local line=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    count=$((count + 1))
  done <<< "$text"
  printf '%s' "$count"
}

summarize_changed_paths() {
  local changed_paths="$1"
  local max_items="${2:-5}"
  local out=()
  local line=""
  local count=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    out+=("$line")
    count=$((count + 1))
    if [[ "$count" -ge "$max_items" ]]; then
      break
    fi
  done <<< "$changed_paths"

  if [[ ${#out[@]} -eq 0 ]]; then
    printf '%s' "(none)"
    return
  fi

  local joined
  joined="$(printf '%s,' "${out[@]}")"
  joined="${joined%,}"
  printf '%s' "$joined"
}

compute_changed_paths_from_status_outputs() {
  local pre_output="$1"
  local post_output="$2"
  local pre_file=""
  local post_file=""
  pre_file="$(mktemp)"
  post_file="$(mktemp)"
  printf '%s' "$pre_output" > "$pre_file"
  printf '%s' "$post_output" > "$post_file"

  python3 - "$pre_file" "$post_file" <<'PY'
import sys

pre_file, post_file = sys.argv[1], sys.argv[2]

def path_from_line(line: str) -> str:
    path = line[3:].strip().strip('"')
    if " -> " in path:
        path = path.split(" -> ", 1)[1].strip().strip('"')
    return path

def status_map(path: str) -> dict:
    out = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line:
                continue
            key = path_from_line(line)
            if not key:
                continue
            out[key] = line[:2]
    return out

pre = status_map(pre_file)
post = status_map(post_file)
changed = sorted({p for p in set(pre) | set(post) if pre.get(p) != post.get(p)})
for item in changed:
    print(item)
PY

  rm -f "$pre_file" "$post_file"
}

write_progress_artifact() {
  local pre_output="$1"
  local post_output="$2"
  local changed_paths="$3"
  [[ "$progress_artifact" -eq 1 ]] || return 0
  mkdir -p "$progress_artifact_dir"
  local artifact_file="$progress_artifact_dir/iteration-${iteration}.txt"
  {
    printf 'iteration=%s\n' "$iteration"
    printf 'timestamp=%s\n' "$(now_utc)"
    printf 'changed_path_count=%s\n' "$(count_nonempty_lines "$changed_paths")"
    printf 'changed_paths_preview=%s\n\n' "$(summarize_changed_paths "$changed_paths" 8)"
    printf 'pre_status_porcelain:\n%s\n\n' "${pre_output:-"(empty)"}"
    printf 'post_status_porcelain:\n%s\n\n' "${post_output:-"(empty)"}"
    printf 'changed_paths:\n%s\n' "${changed_paths:-"(none)"}"
  } > "$artifact_file"
}

write_work_schema() {
  cat > "$work_schema_file" <<'EOF_SCHEMA'
{
  "type": "object",
  "properties": {
    "status": {
      "type": "string",
      "enum": ["IN_PROGRESS", "BLOCKED", "COMPLETE"]
    },
    "assessment": {
      "type": "string",
      "minLength": 1
    },
    "evidence": {
      "type": "array",
      "items": { "type": "string" },
      "minItems": 1
    },
    "next_step": {
      "type": "string",
      "minLength": 1
    },
    "blocker_reason": {
      "type": ["string", "null"]
    },
    "no_change_justification": {
      "type": ["string", "null"]
    }
  },
  "required": ["status", "assessment", "evidence", "next_step"],
  "additionalProperties": false
}
EOF_SCHEMA
}

write_review_schema() {
  cat > "$review_schema_file" <<'EOF_SCHEMA'
{
  "type": "object",
  "properties": {
    "decision": {
      "type": "string",
      "enum": ["SHIP", "REVISE", "BLOCKED"]
    },
    "assessment": {
      "type": "string",
      "minLength": 1
    },
    "feedback": {
      "type": "string",
      "minLength": 1
    },
    "evidence": {
      "type": "array",
      "items": { "type": "string" },
      "minItems": 1
    }
  },
  "required": ["decision", "assessment", "feedback", "evidence"],
  "additionalProperties": false
}
EOF_SCHEMA
}

save_state() {
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
REVIEW_MODEL=$(printf '%q' "$review_model")
REVIEW_PROFILE=$(printf '%q' "$review_profile")
RUN_ID=$(printf '%q' "$run_id")
STARTED_AT=$(printf '%q' "$started_at")
LAST_EVENT_AT=$(printf '%q' "$last_event_at")
LAST_OUTPUT_HASH=$(printf '%q' "$last_output_hash")
OBJECTIVE_FILE=$(printf '%q' "$objective_file")
ACCEPTANCE_FILE=$(printf '%q' "$acceptance_file")
FEEDBACK_FILE=$(printf '%q' "$feedback_file")
SLEEP_SECONDS=$sleep_seconds
IDLE_TIMEOUT_SECONDS=$idle_timeout_seconds
HARD_TIMEOUT_SECONDS=$hard_timeout_seconds
TIMEOUT_RETRIES=$timeout_retries
CODEX_BIN=$(printf '%q' "$codex_bin")
EVENTS_FORMAT=$(printf '%q' "$events_format")
PROGRESS_ARTIFACT=$progress_artifact
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
- Events JSONL: $events_jsonl_file
- Iteration history: $history_file
- Objective file: $objective_state_file
- Acceptance criteria file: $acceptance_state_file
- Feedback file: $feedback_file
- Work summary file: $work_summary_file
- Review feedback file: $review_feedback_file
- Review result file: $review_result_file
- Blocked file: $blocked_file
- Completion marker: $complete_marker_file

## Configuration

- Autonomy level: $autonomy_level
- Worker sandbox: $sandbox
- Reviewer sandbox: read-only
- Max iterations: $max_iterations
- Max consecutive failures: $max_consecutive_failures
- Max stagnant iterations: $max_stagnant_iterations
- Sleep seconds: $sleep_seconds
- Idle timeout seconds: $idle_timeout_seconds
- Hard timeout seconds: $hard_timeout_seconds
- Timeout retries: $timeout_retries
- Codex binary: $codex_bin
- Worker model: ${model:-"(default)"}
- Worker profile: ${profile:-"(default)"}
- Reviewer model: ${review_model:-"(worker default)"}
- Reviewer profile: ${review_profile:-"(worker default)"}
- Events format: $events_format
- Progress artifacts enabled: $progress_artifact

## Optional verification commands
$(if [[ ${#validate_cmds[@]} -eq 0 ]]; then echo '- (none)'; else printf -- '- `%s`\n' "${validate_cmds[@]}"; fi)

## Source of truth
$(if [[ ${#source_of_truth[@]} -eq 0 ]]; then echo '- (none)'; else printf -- '- `%s`\n' "${source_of_truth[@]}"; fi)

## Progress scopes
$(if [[ ${#progress_scopes[@]} -eq 0 ]]; then echo '- (none)'; else printf -- '- `%s`\n' "${progress_scopes[@]}"; fi)
EOF_SUMMARY
}

ensure_default_acceptance_file() {
  if [[ -n "$acceptance_file" ]]; then
    [[ -f "$acceptance_file" ]] || die "--acceptance-file does not exist: $acceptance_file"
    return
  fi

  acceptance_file="$acceptance_state_file"
  if [[ ! -f "$acceptance_state_file" || ! -s "$acceptance_state_file" ]]; then
    local fallback="No explicit acceptance criteria were provided. Treat the objective, source of truth, and reviewer assessment as the ship gate."
    write_text_file "$acceptance_state_file" "$fallback"
  fi
}

sync_feedback_snapshot() {
  local operator_feedback=""
  if [[ -f "$feedback_file" ]]; then
    operator_feedback="$(cat "$feedback_file")"
  fi
  if [[ "$feedback_file" != "$feedback_state_file" ]]; then
    write_text_file "$feedback_state_file" "$operator_feedback"
  fi
}

resolve_objective() {
  local current="$prompt"

  if [[ -n "$objective_file" ]]; then
    if [[ -f "$objective_file" ]]; then
      current="$(cat "$objective_file")"
    else
      warn "Objective file not found during iteration: $objective_file (using last known objective)"
      current="$(read_text_file_or_empty "$objective_state_file")"
    fi
  elif [[ -f "$objective_state_file" ]]; then
    current="$(cat "$objective_state_file")"
  fi

  current="$(trim_ws "$current")"
  [[ -n "$current" ]] || die "Objective is empty"
  current_objective="$current"
  write_text_file "$objective_state_file" "$current_objective"
}

resolve_acceptance() {
  local current=""

  if [[ -n "$acceptance_file" && -f "$acceptance_file" ]]; then
    current="$(cat "$acceptance_file")"
  elif [[ -f "$acceptance_state_file" ]]; then
    current="$(cat "$acceptance_state_file")"
  fi

  current="$(trim_ws "$current")"
  [[ -n "$current" ]] || die "Acceptance criteria are empty"
  current_acceptance="$current"
  if [[ "$acceptance_file" != "$acceptance_state_file" ]]; then
    write_text_file "$acceptance_state_file" "$current_acceptance"
  fi
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

build_verification_block() {
  if [[ ${#validate_cmds[@]} -eq 0 ]]; then
    printf '%s\n' '- (none configured)'
    return
  fi
  local item
  for item in "${validate_cmds[@]}"; do
    printf -- '- %s\n' "$item"
  done
}

build_progress_scope_block() {
  if [[ ${#progress_scopes[@]} -eq 0 ]]; then
    printf '%s\n' '- (none declared)'
    return
  fi
  local item
  for item in "${progress_scopes[@]}"; do
    printf -- '- %s\n' "$item"
  done
}

build_recent_history_block() {
  if [[ -f "$history_file" ]]; then
    tail -n 120 "$history_file"
    return
  fi
  printf '%s\n' '- (no prior iteration history yet)'
}

build_prior_review_feedback_block() {
  if [[ -f "$review_feedback_file" && -s "$review_feedback_file" ]]; then
    tail -n 80 "$review_feedback_file"
    return
  fi
  printf '%s\n' '- (none)'
}

build_operator_feedback_block() {
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

write_work_summary() {
  {
    printf '# Work Summary\n\n'
    printf -- '- Iteration: %s\n' "$iteration"
    printf -- '- Status: %s\n' "$work_status_value"
    printf -- '- Assessment: %s\n' "$work_assessment_value"
    printf -- '- Next step: %s\n' "$work_next_step_value"
    if [[ -n "$work_blocker_reason_value" ]]; then
      printf -- '- Blocker reason: %s\n' "$work_blocker_reason_value"
    fi
    if [[ -n "$current_no_change_justification" ]]; then
      printf -- '- No-change justification: %s\n' "$current_no_change_justification"
    fi
    printf '\n## Evidence\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      printf -- '- %s\n' "$line"
    done <<< "$work_evidence_value"
  } > "$work_summary_file"
}

write_review_state() {
  local decision="$1"
  local assessment="$2"
  local feedback="$3"
  local evidence="$4"
  printf '%s\n' "$decision" > "$review_result_file"
  {
    printf '# Review Feedback\n\n'
    printf -- '- Iteration: %s\n' "$iteration"
    printf -- '- Decision: %s\n' "$decision"
    printf -- '- Assessment: %s\n' "$assessment"
    printf '\n## Feedback\n%s\n' "$feedback"
    printf '\n## Evidence\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      printf -- '- %s\n' "$line"
    done <<< "$evidence"
  } > "$review_feedback_file"
}

write_blocked_marker() {
  {
    printf '# Ralph Blocked\n\n'
    printf -- '- Iteration: %s\n' "$iteration"
    printf -- '- Work assessment: %s\n' "$work_assessment_value"
    printf -- '- Blocker reason: %s\n' "$work_blocker_reason_value"
    printf -- '- Review assessment: %s\n' "$review_assessment_value"
    printf '\n## What was attempted\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      printf -- '- %s\n' "$line"
    done <<< "$work_evidence_value"
    printf '\n## Reviewer feedback\n%s\n' "$review_feedback_value"
    printf '\n## Next step\n%s\n' "$work_next_step_value"
  } > "$blocked_file"
}

write_complete_marker() {
  {
    printf 'task_complete\n'
    printf 'iteration=%s\n' "$iteration"
    printf 'timestamp=%s\n' "$(now_utc)"
    printf 'assessment=%s\n' "$review_assessment_value"
  } > "$complete_marker_file"
}

clear_markers() {
  rm -f "$blocked_file" "$complete_marker_file"
}

append_iteration_history() {
  local work_phase_status="$1"
  local work_parse_status="$2"
  local review_phase_status="$3"
  local review_parse_status="$4"
  local validation_status="$5"
  local progress_status="$6"
  local effective_review="$7"
  {
    printf '%s\n' '---'
    printf 'iteration=%s timestamp=%s work_phase=%s work_parse=%s review_phase=%s review_parse=%s validation=%s progress=%s effective_review=%s stagnant=%s\n' \
      "$iteration" "$(now_utc)" "$work_phase_status" "$work_parse_status" "$review_phase_status" "$review_parse_status" "$validation_status" "$progress_status" "$effective_review" "$stagnant_iterations"
    printf 'objective_file=%s acceptance_file=%s feedback_file=%s\n' "${objective_file:-"(state)"}" "${acceptance_file:-"(state)"}" "$feedback_file"
    printf 'work_status=%s review_decision=%s changed_paths=%s\n' "${work_status_value:-"(none)"}" "${review_decision_value:-"(none)"}" "${current_changed_path_preview:-"(none)"}"
    printf 'work_last_message_tail:\n'
    tail_or_placeholder "$work_last_message_file" 40 '(none)'
    printf '\nreview_last_message_tail:\n'
    tail_or_placeholder "$review_last_message_file" 40 '(none)'
    printf '%s\n\n' ''
  } >> "$history_file"
}

refresh_auto_feedback() {
  local mode="$1"
  local detail="${2:-}"

  case "$mode" in
    clear)
      rm -f "$auto_feedback_file"
      ;;
    runtime_work)
      cat > "$auto_feedback_file" <<EOF_AUTO
Work phase failed in iteration $iteration.
- Inspect .codex/ralph-loop/events.log and .codex/ralph-loop/codex/ for details.
- Fix the tool/runtime failure before retrying.
- Do not repeat the same failing path without a new idea.
EOF_AUTO
      ;;
    runtime_review)
      cat > "$auto_feedback_file" <<EOF_AUTO
Review phase failed in iteration $iteration.
- Inspect .codex/ralph-loop/events.log and .codex/ralph-loop/codex/ for review-phase details.
- Restore a fresh review pass before trusting completion.
EOF_AUTO
      ;;
    invalid_work_output)
      cat > "$auto_feedback_file" <<EOF_AUTO
Work phase output did not match the expected JSON contract in iteration $iteration.
- Expected schema file: .codex/ralph-loop/work-schema.json
- Include status, assessment, evidence, and next_step.
- If blocked, include blocker_reason.
- Keep all output inside one JSON object.
EOF_AUTO
      ;;
    invalid_review_output)
      cat > "$auto_feedback_file" <<EOF_AUTO
Review phase output did not match the expected JSON contract in iteration $iteration.
- Expected schema file: .codex/ralph-loop/review-schema.json
- Include decision, assessment, feedback, and evidence.
- Keep all output inside one JSON object.
EOF_AUTO
      ;;
    review_revise)
      cat > "$auto_feedback_file" <<EOF_AUTO
The fresh-context reviewer requested another iteration.

$detail
EOF_AUTO
      ;;
    validation_fail)
      cat > "$auto_feedback_file" <<EOF_AUTO
Optional verification failed in iteration $iteration.
- Inspect .codex/ralph-loop/validation/iteration-$iteration/ logs.
- Resolve the failing verification before shipping.
- Use the review feedback to guide the next attempt.
EOF_AUTO
      ;;
    unjustified_no_change)
      cat > "$auto_feedback_file" <<EOF_AUTO
No scoped progress was detected in iteration $iteration.
- Edit files under the configured progress scopes, or
- provide no_change_justification only if the task truly requires no code changes.
EOF_AUTO
      ;;
    blocker_rejected)
      cat > "$auto_feedback_file" <<EOF_AUTO
The reviewer rejected the blocker claim in iteration $iteration.

$detail
EOF_AUTO
      ;;
    *)
      rm -f "$auto_feedback_file"
      ;;
  esac
}

normalize_json_for_hash() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    printf '%s' ""
    return
  fi
  tr -d '\r' < "$file_path" | tr '\n' ' ' | awk '{$1=$1;print}'
}

parse_work_message_json() {
  local message_file="$1"
  local parse_output=""
  work_status_value=""
  work_assessment_value=""
  work_evidence_value=""
  work_next_step_value=""
  work_blocker_reason_value=""
  current_no_change_justification=""

  [[ -f "$message_file" ]] || return 1

  if ! parse_output="$(
    python3 - "$message_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        payload = fh.read().strip()
    if not payload:
        raise ValueError("empty final message")
    data = json.loads(payload)
    status = data.get("status")
    assessment = data.get("assessment")
    evidence = data.get("evidence")
    next_step = data.get("next_step")
    blocker_reason = data.get("blocker_reason", "")
    no_change = data.get("no_change_justification", "")
    if status not in {"IN_PROGRESS", "BLOCKED", "COMPLETE"}:
        raise ValueError("status must be IN_PROGRESS|BLOCKED|COMPLETE")
    if not isinstance(assessment, str) or not assessment.strip():
        raise ValueError("assessment must be a non-empty string")
    if not isinstance(evidence, list) or not evidence:
        raise ValueError("evidence must be a non-empty array")
    if any((not isinstance(item, str) or not item.strip()) for item in evidence):
        raise ValueError("each evidence item must be a non-empty string")
    if not isinstance(next_step, str) or not next_step.strip():
        raise ValueError("next_step must be a non-empty string")
    if blocker_reason is None:
        blocker_reason = ""
    if no_change is None:
        no_change = ""
    if not isinstance(blocker_reason, str):
        raise ValueError("blocker_reason must be a string when present")
    if not isinstance(no_change, str):
        raise ValueError("no_change_justification must be a string when present")
    if status == "BLOCKED" and not blocker_reason.strip():
        raise ValueError("blocker_reason must be present when status is BLOCKED")
    pieces = [
        status.replace("|", " ").strip(),
        assessment.replace("|", " ").strip(),
        "\n".join(item.replace("|", " ").strip() for item in evidence),
        next_step.replace("|", " ").strip(),
        blocker_reason.replace("|", " ").strip(),
        no_change.replace("|", " ").strip(),
    ]
    print("|".join(pieces))
except Exception as exc:
    print(f"ERROR:{exc}")
    sys.exit(1)
PY
  )"; then
    return 1
  fi

  IFS='|' read -r work_status_value work_assessment_value work_evidence_value work_next_step_value work_blocker_reason_value current_no_change_justification <<< "$parse_output"
  return 0
}

parse_review_message_json() {
  local message_file="$1"
  local parse_output=""
  review_decision_value=""
  review_assessment_value=""
  review_feedback_value=""
  review_evidence_value=""

  [[ -f "$message_file" ]] || return 1

  if ! parse_output="$(
    python3 - "$message_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        payload = fh.read().strip()
    if not payload:
        raise ValueError("empty final message")
    data = json.loads(payload)
    decision = data.get("decision")
    assessment = data.get("assessment")
    feedback = data.get("feedback")
    evidence = data.get("evidence")
    if decision not in {"SHIP", "REVISE", "BLOCKED"}:
        raise ValueError("decision must be SHIP|REVISE|BLOCKED")
    if not isinstance(assessment, str) or not assessment.strip():
        raise ValueError("assessment must be a non-empty string")
    if not isinstance(feedback, str) or not feedback.strip():
        raise ValueError("feedback must be a non-empty string")
    if not isinstance(evidence, list) or not evidence:
        raise ValueError("evidence must be a non-empty array")
    if any((not isinstance(item, str) or not item.strip()) for item in evidence):
        raise ValueError("each evidence item must be a non-empty string")
    pieces = [
        decision.replace("|", " ").strip(),
        assessment.replace("|", " ").strip(),
        feedback.replace("|", " ").strip(),
        "\n".join(item.replace("|", " ").strip() for item in evidence),
    ]
    print("|".join(pieces))
except Exception as exc:
    print(f"ERROR:{exc}")
    sys.exit(1)
PY
  )"; then
    return 1
  fi

  IFS='|' read -r review_decision_value review_assessment_value review_feedback_value review_evidence_value <<< "$parse_output"
  return 0
}

build_work_phase_prompt() {
  local source_block="$1"
  local verification_block="$2"
  local progress_scope_block="$3"
  local recent_history_block="$4"
  local prior_review_feedback="$5"
  local operator_feedback_block="$6"
  cat <<EOF_PROMPT
Ralph Work Phase for Codex
Run ID: $run_id
Iteration: $iteration

You are the worker in a Ralph loop. Start with fresh context. All continuity lives in repo files.

Objective:
$current_objective

Acceptance criteria:
$current_acceptance

Source of truth:
$source_block

Prior review feedback:
$prior_review_feedback

Operator and auto feedback:
$operator_feedback_block

Recent iteration history:
$recent_history_block

Optional verification:
$verification_block

Progress scopes (anti-no-op guard):
$progress_scope_block

Operating invariants:
- Advance the user's task, not just the checks.
- Use acceptance criteria as the completion bar.
- Surface real blockers with concrete evidence.
- Do not declare BLOCKED without blocker_reason.
- Do not declare COMPLETE unless the objective and acceptance criteria are satisfied.
- Make the smallest effective change that improves the task outcome.

Output contract:
- Respond with EXACTLY one JSON object matching work-schema.json.
- Required fields:
  status: IN_PROGRESS | BLOCKED | COMPLETE
  assessment: concise assessment of progress against the objective and acceptance criteria
  evidence: non-empty array of concrete command/result or repo evidence from this iteration
  next_step: exactly one highest-impact next step
- Optional fields:
  blocker_reason: REQUIRED when status is BLOCKED
  no_change_justification: include only when no scoped files changed and the task truly required no code changes
- Do not include any text outside the JSON object.
EOF_PROMPT
}

build_validation_summary() {
  local validation_dir="$state_dir/validation/iteration-$iteration"
  if [[ ${#validate_cmds[@]} -eq 0 ]]; then
    current_validation_status="not_configured"
    current_validation_summary="- (no optional verification commands configured)"
    return
  fi

  if [[ "$current_validation_status" == "pass" ]]; then
    current_validation_summary="Status: pass
Logs: $validation_dir"
  else
    current_validation_summary="Status: fail
Logs: $validation_dir"
  fi
}

build_review_phase_prompt() {
  local source_block="$1"
  local verification_block="$2"
  local progress_scope_block="$3"
  local work_summary_block="$4"
  local validation_summary_block="$5"
  cat <<EOF_PROMPT
Ralph Review Phase for Codex
Run ID: $run_id
Iteration: $iteration

You are the reviewer in a Ralph loop. Start with fresh context. Review the repo state and the work summary fairly and strictly.

Objective:
$current_objective

Acceptance criteria:
$current_acceptance

Source of truth:
$source_block

Work summary:
$work_summary_block

Optional verification results:
$validation_summary_block

Progress scopes (anti-no-op guard):
$progress_scope_block

Review criteria:
- Decide whether the task is ready to ship against the objective and acceptance criteria.
- Use optional verification as evidence when configured, not as the whole task.
- If the worker claims BLOCKED, confirm whether the blocker is genuine and external.
- If the task is still solvable inside the repo, return REVISE with concrete feedback.
- Do not nitpick style when the task is genuinely complete.

Output contract:
- Respond with EXACTLY one JSON object matching review-schema.json.
- Required fields:
  decision: SHIP | REVISE | BLOCKED
  assessment: concise assessment of task state
  feedback: actionable review guidance or final ship confirmation
  evidence: non-empty array of concrete evidence
- Do not include any text outside the JSON object.
EOF_PROMPT
}

run_phase_exec_with_watchdog() {
  local phase_name="$1"
  local local_prompt="$2"
  local attempt="$3"
  local output_file="$4"
  local schema_file="$5"
  local phase_model="$6"
  local phase_profile="$7"
  local phase_sandbox="$8"

  local attempt_jsonl="$codex_log_dir/iteration-${iteration}-${phase_name}-attempt-${attempt}.jsonl"
  local attempt_stderr="$codex_log_dir/iteration-${iteration}-${phase_name}-attempt-${attempt}.stderr.log"
  local codex_cmd=()

  codex_cmd=("$resolved_codex_bin" exec -C "$cwd" --output-last-message "$output_file" --output-schema "$schema_file" --json)
  [[ -n "$phase_sandbox" ]] && codex_cmd+=(--sandbox "$phase_sandbox")
  [[ -n "$phase_model" ]] && codex_cmd+=(--model "$phase_model")
  [[ -n "$phase_profile" ]] && codex_cmd+=(--profile "$phase_profile")
  [[ "$full_auto" -eq 1 ]] && codex_cmd+=(--full-auto)
  if [[ "$phase_name" == "work" && "$dangerous" -eq 1 ]]; then
    codex_cmd+=(--dangerously-bypass-approvals-and-sandbox)
  fi
  if [[ ${#codex_extra_args[@]} -gt 0 ]]; then
    codex_cmd+=("${codex_extra_args[@]}")
  fi
  codex_cmd+=("$local_prompt")

  : > "$attempt_jsonl"
  : > "$attempt_stderr"
  log_event "codex_attempt_start" "phase=$phase_name;attempt=$attempt;jsonl=$attempt_jsonl"

  "${codex_cmd[@]}" >"$attempt_jsonl" 2>"$attempt_stderr" &
  local codex_pid=$!
  local start_ts
  start_ts="$(date +%s)"
  local last_activity_ts="$start_ts"
  local last_size=-1
  local now_ts=0

  attempt_timeout_reason=""
  while kill -0 "$codex_pid" 2>/dev/null; do
    sleep 1
    local current_size=0
    current_size="$(wc -c < "$attempt_jsonl" 2>/dev/null || echo 0)"
    if [[ "$current_size" -ne "$last_size" ]]; then
      last_size="$current_size"
      last_activity_ts="$(date +%s)"
    fi

    now_ts="$(date +%s)"
    if [[ "$hard_timeout_seconds" -gt 0 ]] && [[ $((now_ts - start_ts)) -ge "$hard_timeout_seconds" ]]; then
      attempt_timeout_reason="hard_timeout"
      break
    fi
    if [[ "$idle_timeout_seconds" -gt 0 ]] && [[ $((now_ts - last_activity_ts)) -ge "$idle_timeout_seconds" ]]; then
      attempt_timeout_reason="idle_timeout"
      break
    fi
  done

  if [[ -n "$attempt_timeout_reason" ]]; then
    warn "codex exec timed out (phase=$phase_name, reason=$attempt_timeout_reason, attempt=$attempt)"
    log_event "codex_timeout" "phase=$phase_name;attempt=$attempt;reason=$attempt_timeout_reason;jsonl=$attempt_jsonl"
    kill -TERM -- -"$codex_pid" 2>/dev/null || kill -TERM "$codex_pid" 2>/dev/null || true
    (
      sleep 1
      kill -0 "$codex_pid" 2>/dev/null || exit 0
      kill -KILL -- -"$codex_pid" 2>/dev/null || kill -KILL "$codex_pid" 2>/dev/null || true
    ) &
    local killer_pid=$!
    wait "$codex_pid" 2>/dev/null || true
    kill "$killer_pid" 2>/dev/null || true
    wait "$killer_pid" 2>/dev/null || true
    return 124
  fi

  local cmd_status=0
  set +e
  wait "$codex_pid"
  cmd_status=$?
  set -e
  log_event "codex_attempt_end" "phase=$phase_name;attempt=$attempt;exit=$cmd_status;jsonl=$attempt_jsonl"
  return "$cmd_status"
}

run_phase_with_retries() {
  local phase_name="$1"
  local local_prompt="$2"
  local output_file="$3"
  local schema_file="$4"
  local phase_model="$5"
  local phase_profile="$6"
  local phase_sandbox="$7"

  local phase_exit=0
  local attempt=1
  local max_attempts=$((timeout_retries + 1))
  while true; do
    if run_phase_exec_with_watchdog "$phase_name" "$local_prompt" "$attempt" "$output_file" "$schema_file" "$phase_model" "$phase_profile" "$phase_sandbox"; then
      phase_exit=0
      break
    else
      phase_exit=$?
    fi

    if [[ "$phase_exit" -eq 124 && "$attempt" -lt "$max_attempts" ]]; then
      log_event "codex_timeout_retry" "phase=$phase_name;attempt=$attempt;reason=${attempt_timeout_reason:-timeout}"
      attempt=$((attempt + 1))
      continue
    fi
    break
  done
  return "$phase_exit"
}

run_preflight() {
  if ! resolved_codex_bin="$(command -v "$codex_bin" 2>/dev/null)"; then
    die "codex binary not found: $codex_bin"
  fi
  command -v python3 >/dev/null 2>&1 || die "python3 is required to parse schema output"
  note "Using codex binary: $resolved_codex_bin"
  log_event "preflight_codex_bin" "codex_bin=$codex_bin;resolved=$resolved_codex_bin"

  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    is_git_repo=1
    local dirty_count
    dirty_count="$(git -C "$cwd" status --porcelain | wc -l | tr -d ' ')"
    if ! git -C "$cwd" status --porcelain -- "${progress_scopes[@]}" >/dev/null 2>&1; then
      die "Invalid --progress-scope pathspec list: ${progress_scopes[*]}"
    fi
    note "Git working tree detected; uncommitted entries: $dirty_count"
    log_event "preflight_git" "dirty_entries=$dirty_count"
  else
    is_git_repo=0
    warn "Working directory is not a git repository"
    log_event "preflight_git" "not_a_repo"
  fi

  if [[ ${#source_of_truth[@]} -gt 0 ]]; then
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
  fi

  if [[ ${#preflight_cmds[@]} -gt 0 ]]; then
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
  fi
}

run_validation_loop() {
  local validation_dir="$state_dir/validation/iteration-$iteration"
  mkdir -p "$validation_dir"
  local failed=0
  local idx=0
  local cmd=""
  if [[ ${#validate_cmds[@]} -eq 0 ]]; then
    current_validation_status="not_configured"
    current_validation_summary="- (no optional verification commands configured)"
    return 0
  fi

  for cmd in "${validate_cmds[@]}"; do
    idx=$((idx + 1))
    local log_file="$validation_dir/cmd-$idx.log"
    note "Optional verification [$idx/${#validate_cmds[@]}]: $cmd"
    if run_cmd_in_cwd "$cmd" >"$log_file" 2>&1; then
      log_event "validation_ok" "cmd=$cmd;log=$log_file"
    else
      failed=1
      warn "Optional verification failed: $cmd (see $log_file)"
      log_event "validation_fail" "cmd=$cmd;log=$log_file"
    fi
  done

  if [[ "$failed" -eq 0 ]]; then
    current_validation_status="pass"
  else
    current_validation_status="fail"
  fi
  build_validation_summary
  return "$failed"
}

pause_between_iterations() {
  if [[ "$sleep_seconds" -gt 0 ]]; then
    note "Sleeping $sleep_seconds second(s) before next iteration"
    sleep "$sleep_seconds"
  fi
}

if [[ "$resume" -eq 1 ]]; then
  [[ -f "$state_file" ]] || die "Cannot resume: missing state file at $state_file"
  [[ -f "$objective_state_file" ]] || die "Cannot resume: missing objective file at $objective_state_file"
  [[ -z "$prompt" ]] || die "Do not provide --prompt when using --resume"
  [[ -z "$prompt_file" ]] || die "Do not provide --prompt-file when using --resume"

  # shellcheck disable=SC1090
  source "$state_file"

  if [[ "$provided_max_iterations" -eq 0 ]]; then
    max_iterations="${MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
  fi
  if [[ "$provided_autonomy" -eq 0 ]]; then
    autonomy_level="${AUTONOMY_LEVEL:-l2}"
  fi
  if [[ "$provided_objective_file" -eq 0 ]]; then
    objective_file="${OBJECTIVE_FILE:-}"
  fi
  if [[ "$provided_acceptance_file" -eq 0 ]]; then
    acceptance_file="${ACCEPTANCE_FILE:-}"
  fi
  if [[ "$provided_feedback_file" -eq 0 ]]; then
    feedback_file="${FEEDBACK_FILE:-$feedback_file}"
  fi
  if [[ "$provided_sandbox" -eq 0 ]]; then
    sandbox="${SANDBOX:-}"
  fi
  if [[ -z "$model" ]]; then
    model="${MODEL:-}"
  fi
  if [[ -z "$profile" ]]; then
    profile="${PROFILE:-}"
  fi
  if [[ "$provided_review_model" -eq 0 ]]; then
    review_model="${REVIEW_MODEL:-}"
  fi
  if [[ "$provided_review_profile" -eq 0 ]]; then
    review_profile="${REVIEW_PROFILE:-}"
  fi
  if [[ "$provided_max_stagnant_iterations" -eq 0 ]]; then
    max_stagnant_iterations="${MAX_STAGNANT_ITERATIONS:-$DEFAULT_MAX_STAGNANT_ITERATIONS}"
  fi
  if [[ "$provided_sleep_seconds" -eq 0 ]]; then
    sleep_seconds="${SLEEP_SECONDS:-0}"
  fi
  if [[ "$provided_idle_timeout_seconds" -eq 0 ]]; then
    idle_timeout_seconds="${IDLE_TIMEOUT_SECONDS:-$DEFAULT_IDLE_TIMEOUT_SECONDS}"
  fi
  if [[ "$provided_hard_timeout_seconds" -eq 0 ]]; then
    hard_timeout_seconds="${HARD_TIMEOUT_SECONDS:-$DEFAULT_HARD_TIMEOUT_SECONDS}"
  fi
  if [[ "$provided_timeout_retries" -eq 0 ]]; then
    timeout_retries="${TIMEOUT_RETRIES:-$DEFAULT_TIMEOUT_RETRIES}"
  fi
  if [[ "$provided_codex_bin" -eq 0 ]]; then
    codex_bin="${CODEX_BIN:-codex}"
  fi
  if [[ "$provided_events_format" -eq 0 ]]; then
    events_format="${EVENTS_FORMAT:-both}"
  fi
  if [[ "$provided_progress_artifact" -eq 0 ]]; then
    progress_artifact="${PROGRESS_ARTIFACT:-0}"
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
  if [[ "$provided_progress_scope" -eq 0 ]]; then
    read_lines_file "$progress_scope_file" progress_scopes
  fi
  if [[ "$provided_codex_arg" -eq 0 ]]; then
    read_lines_file "$codex_args_file" codex_extra_args
  fi
  if [[ ${#progress_scopes[@]} -eq 0 ]]; then
    progress_scopes=(".")
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

  prompt="$(trim_ws "$prompt")"
  [[ -n "$prompt" ]] || die "Prompt is empty"

  if [[ -z "$sandbox" ]]; then
    case "$autonomy_level" in
      l0) sandbox="read-only" ;;
      l1|l2|l3) sandbox="workspace-write" ;;
    esac
  fi

  if [[ "$max_iterations" -eq 0 && "$allow_unbounded" -ne 1 ]]; then
    die "Unbounded loop requires --allow-unbounded"
  fi

  if [[ ${#progress_scopes[@]} -eq 0 ]]; then
    progress_scopes=(".")
  fi

  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  started_at="$(now_utc)"
  iteration=1
  consecutive_failures=0
  stagnant_iterations=0
  last_output_hash=""
fi

ensure_default_acceptance_file
if [[ -n "$objective_file" ]]; then
  [[ -f "$objective_file" ]] || die "--objective-file does not exist: $objective_file"
fi
if [[ -n "$acceptance_file" ]]; then
  [[ -f "$acceptance_file" ]] || die "--acceptance-file does not exist: $acceptance_file"
fi

if [[ -z "$review_model" ]]; then
  review_model="$model"
fi
if [[ -z "$review_profile" ]]; then
  review_profile="$profile"
fi

mkdir -p "$state_dir"
mkdir -p "$codex_log_dir"
if [[ "$progress_artifact" -eq 1 ]]; then
  mkdir -p "$progress_artifact_dir"
fi

write_lines_file_from_array "$validate_file" "validate_cmds"
write_lines_file_from_array "$preflight_file" "preflight_cmds"
write_lines_file_from_array "$source_of_truth_file" "source_of_truth"
write_lines_file_from_array "$progress_scope_file" "progress_scopes"
write_lines_file_from_array "$codex_args_file" "codex_extra_args"

resolve_objective
resolve_acceptance
sync_feedback_snapshot

print_effective_config() {
  cat <<EOF_CONFIG
Ralph Loop Effective Configuration

run_id=$run_id
cwd=$cwd
state_dir=$state_dir
autonomy_level=$autonomy_level
sandbox=$sandbox
review_sandbox=read-only
codex_bin=$codex_bin
model=${model:-"(default)"}
profile=${profile:-"(default)"}
review_model=${review_model:-"(worker default)"}
review_profile=${review_profile:-"(worker default)"}
max_iterations=$max_iterations
max_consecutive_failures=$max_consecutive_failures
max_stagnant_iterations=$max_stagnant_iterations
sleep_seconds=$sleep_seconds
idle_timeout_seconds=$idle_timeout_seconds
hard_timeout_seconds=$hard_timeout_seconds
timeout_retries=$timeout_retries
events_format=$events_format
progress_artifact=$progress_artifact
stop_file=$stop_file
objective_file=${objective_file:-$objective_state_file}
acceptance_file=${acceptance_file:-$acceptance_state_file}
feedback_file=$feedback_file
work_schema_file=$work_schema_file
review_schema_file=$review_schema_file

source_of_truth_count=${#source_of_truth[@]}
progress_scope_count=${#progress_scopes[@]}
preflight_cmd_count=${#preflight_cmds[@]}
validate_cmd_count=${#validate_cmds[@]}
codex_extra_arg_count=${#codex_extra_args[@]}
EOF_CONFIG
}

reclaim_existing_lock_if_stale

if [[ "$dry_run" -eq 1 ]]; then
  print_effective_config
  note "Dry run complete"
  exit 0
fi

if mkdir "$lock_dir" 2>/dev/null; then
  cat > "$lock_meta_file" <<EOF_LOCK
PID=$$
RUN_ID=$(printf '%q' "$run_id")
STARTED_AT=$(printf '%q' "$started_at")
CWD=$(printf '%q' "$cwd")
EOF_LOCK
else
  die "Another loop is already active (lock exists: $lock_dir)"
fi

cleanup_lock() {
  rm -rf "$lock_dir" 2>/dev/null || true
}
trap cleanup_lock EXIT

note "Ralph loop started"
note "Run ID: $run_id"
note "State dir: $state_dir"
note "Stop file: $stop_file"
log_event "loop_start" "autonomy=$autonomy_level;sandbox=$sandbox;codex_bin=$codex_bin;events_format=$events_format"

run_preflight
write_work_schema
write_review_schema
clear_markers
rm -f "$auto_feedback_file"

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

  resolve_objective
  resolve_acceptance
  sync_feedback_snapshot
  log_event "iteration_start" "iteration=$iteration"

  pre_scope_status="$(scoped_status_output)"
  pre_scope_hash="$(status_output_hash "$pre_scope_status")"

  source_block="$(build_source_block)"
  verification_block="$(build_verification_block)"
  progress_scope_block="$(build_progress_scope_block)"
  recent_history_block="$(build_recent_history_block)"
  prior_review_feedback_block="$(build_prior_review_feedback_block)"
  operator_feedback_block="$(build_operator_feedback_block)"

  work_prompt="$(build_work_phase_prompt "$source_block" "$verification_block" "$progress_scope_block" "$recent_history_block" "$prior_review_feedback_block" "$operator_feedback_block")"
  : > "$work_last_message_file"
  work_phase_exec_status="ok"
  work_parse_status="not_parsed"
  review_phase_exec_status="skipped"
  review_parse_status="skipped"
  effective_review_decision="REVISE"

  if run_phase_with_retries "work" "$work_prompt" "$work_last_message_file" "$work_schema_file" "$model" "$profile" "$sandbox"; then
    log_event "work_phase_ok" "iteration=$iteration"
    consecutive_failures=0
  else
    work_exit=$?
    work_phase_exec_status="fail"
    consecutive_failures=$((consecutive_failures + 1))
    warn "work phase failed (exit=$work_exit), consecutive failures=$consecutive_failures"
    log_event "work_phase_fail" "exit=$work_exit;reason=${attempt_timeout_reason:-none}"
    refresh_auto_feedback "runtime_work"
    append_iteration_history "fail" "skipped" "skipped" "skipped" "skipped" "skipped" "REVISE"
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

  if parse_work_message_json "$work_last_message_file"; then
    work_parse_status="ok"
    write_work_summary
  else
    work_parse_status="invalid_json_contract"
    log_event "work_schema_parse_fail" "file=$work_last_message_file"
    refresh_auto_feedback "invalid_work_output"
    append_iteration_history "ok" "$work_parse_status" "skipped" "skipped" "skipped" "skipped" "REVISE"
    iteration=$((iteration + 1))
    save_state
    pause_between_iterations
    continue
  fi

  current_validation_status="pass"
  if run_validation_loop; then
    :
  else
    :
  fi

  review_work_summary_block="$(tail_or_placeholder "$work_summary_file" 120 '- (missing work summary)')"
  review_prompt="$(build_review_phase_prompt "$source_block" "$verification_block" "$progress_scope_block" "$review_work_summary_block" "$current_validation_summary")"
  : > "$review_last_message_file"

  if run_phase_with_retries "review" "$review_prompt" "$review_last_message_file" "$review_schema_file" "$review_model" "$review_profile" "read-only"; then
    review_phase_exec_status="ok"
    log_event "review_phase_ok" "iteration=$iteration"
    consecutive_failures=0
  else
    review_exit=$?
    review_phase_exec_status="fail"
    consecutive_failures=$((consecutive_failures + 1))
    warn "review phase failed (exit=$review_exit), consecutive failures=$consecutive_failures"
    log_event "review_phase_fail" "exit=$review_exit;reason=${attempt_timeout_reason:-none}"
    refresh_auto_feedback "runtime_review"
    append_iteration_history "ok" "$work_parse_status" "fail" "skipped" "$current_validation_status" "skipped" "REVISE"
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

  if parse_review_message_json "$review_last_message_file"; then
    review_parse_status="ok"
  else
    review_parse_status="invalid_json_contract"
    log_event "review_schema_parse_fail" "file=$review_last_message_file"
    refresh_auto_feedback "invalid_review_output"
    append_iteration_history "ok" "$work_parse_status" "ok" "$review_parse_status" "$current_validation_status" "skipped" "REVISE"
    iteration=$((iteration + 1))
    save_state
    pause_between_iterations
    continue
  fi

  post_scope_status="$(scoped_status_output)"
  post_scope_hash="$(status_output_hash "$post_scope_status")"
  current_changed_paths=""
  current_changed_path_count=0
  current_changed_path_preview="(none)"
  current_progress_status="pass"

  if [[ "$is_git_repo" -eq 1 ]]; then
    current_changed_paths="$(compute_changed_paths_from_status_outputs "$pre_scope_status" "$post_scope_status")"
    current_changed_path_count="$(count_nonempty_lines "$current_changed_paths")"
    current_changed_path_preview="$(summarize_changed_paths "$current_changed_paths" 5)"
    write_progress_artifact "$pre_scope_status" "$post_scope_status" "$current_changed_paths"
    log_event "progress_scope_diff" "iteration=$iteration;changed_path_count=$current_changed_path_count;changed_paths=$current_changed_path_preview"
    if [[ "$pre_scope_hash" != "$post_scope_hash" || "$current_changed_path_count" -gt 0 ]]; then
      current_progress_status="pass"
    elif [[ -n "$current_no_change_justification" ]]; then
      current_progress_status="no_change_justified"
      log_event "progress_gate_justified" "iteration=$iteration;changed_path_count=$current_changed_path_count;changed_paths=$current_changed_path_preview"
    else
      current_progress_status="no_change_unjustified"
      log_event "progress_gate_block" "iteration=$iteration;changed_path_count=$current_changed_path_count;changed_paths=$current_changed_path_preview"
    fi
  else
    current_progress_status="not_git_repo"
  fi

  effective_review_decision="$review_decision_value"
  effective_review_feedback="$review_feedback_value"
  effective_review_assessment="$review_assessment_value"
  effective_review_evidence="$review_evidence_value"

  if [[ "$effective_review_decision" == "SHIP" && "$work_status_value" != "COMPLETE" ]]; then
    effective_review_decision="REVISE"
    effective_review_assessment="The worker has not yet satisfied the acceptance criteria."
    effective_review_feedback="Do not ship yet. Continue the task until the work phase can honestly report COMPLETE."
    effective_review_evidence="worker status was $work_status_value"
  fi

  if [[ "$effective_review_decision" == "SHIP" && "$current_validation_status" == "fail" ]]; then
    effective_review_decision="REVISE"
    effective_review_assessment="Optional verification still fails, so the task is not ready to ship."
    effective_review_feedback="Resolve the failing optional verification before shipping."
    effective_review_evidence="optional verification failed"
    log_event "review_rejected" "reason=validation_failed"
  fi

  if [[ "$effective_review_decision" == "SHIP" && "$current_progress_status" == "no_change_unjustified" ]]; then
    effective_review_decision="REVISE"
    effective_review_assessment="No scoped progress was detected and the no-change claim was not justified."
    effective_review_feedback="Either make the required scoped change or provide a concrete no_change_justification."
    effective_review_evidence="no scoped progress detected"
    log_event "review_rejected" "reason=unjustified_no_change"
  fi

  if [[ "$effective_review_decision" == "BLOCKED" && "$work_status_value" != "BLOCKED" ]]; then
    effective_review_decision="REVISE"
    effective_review_assessment="The blocker decision is not credible because the worker did not report BLOCKED."
    effective_review_feedback="Continue working and only use BLOCKED for genuine blockers with evidence."
    effective_review_evidence="worker did not provide a blocker"
  fi

  review_assessment_value="$effective_review_assessment"
  review_feedback_value="$effective_review_feedback"
  review_evidence_value="$effective_review_evidence"
  review_decision_value="$effective_review_decision"
  write_review_state "$review_decision_value" "$review_assessment_value" "$review_feedback_value" "$review_evidence_value"

  if [[ "$review_decision_value" == "SHIP" ]]; then
    write_complete_marker
    rm -f "$blocked_file"
    refresh_auto_feedback "clear"
    stop_reason="task_complete"
    log_event "stop" "$stop_reason"
  elif [[ "$review_decision_value" == "BLOCKED" ]]; then
    write_blocked_marker
    rm -f "$complete_marker_file"
    refresh_auto_feedback "clear"
    stop_reason="task_blocked"
    log_event "stop" "$stop_reason"
  elif [[ "$work_status_value" == "BLOCKED" ]]; then
    rm -f "$blocked_file"
    refresh_auto_feedback "blocker_rejected" "$review_feedback_value"
  elif [[ "$current_validation_status" == "fail" ]]; then
    rm -f "$complete_marker_file"
    refresh_auto_feedback "validation_fail"
  elif [[ "$current_progress_status" == "no_change_unjustified" ]]; then
    rm -f "$complete_marker_file"
    refresh_auto_feedback "unjustified_no_change"
  else
    rm -f "$complete_marker_file" "$blocked_file"
    refresh_auto_feedback "review_revise" "$review_feedback_value"
  fi

  work_hash_part="$(normalize_json_for_hash "$work_last_message_file")"
  review_hash_part="$(normalize_json_for_hash "$review_last_message_file")"
  current_output_hash="$(printf '%s' "$work_hash_part|$review_hash_part|$review_decision_value|$current_progress_status|$current_validation_status" | hash_text)"
  if [[ -n "$last_output_hash" && "$current_output_hash" == "$last_output_hash" ]]; then
    stagnant_iterations=$((stagnant_iterations + 1))
    log_event "stagnant_output" "count=$stagnant_iterations"
  else
    stagnant_iterations=0
  fi
  last_output_hash="$current_output_hash"

  append_iteration_history "$work_phase_exec_status" "$work_parse_status" "$review_phase_exec_status" "$review_parse_status" "$current_validation_status" "$current_progress_status" "$review_decision_value"

  if [[ -n "$stop_reason" ]]; then
    break
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
