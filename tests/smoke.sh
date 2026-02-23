#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh"

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

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo_dir="$tmp_dir/repo"
mkdir -p "$repo_dir"

expect_success "script is executable" test -x "$SCRIPT"
expect_success "help works" bash -lc "'$SCRIPT' --help >/dev/null"
expect_failure "missing prompt fails" bash -lc "'$SCRIPT' --cwd '$repo_dir' --dry-run >/dev/null 2>&1"
expect_failure "invalid autonomy level fails" bash -lc "'$SCRIPT' --cwd '$repo_dir' --prompt 'x' --autonomy-level bad --dry-run >/dev/null 2>&1"
expect_success "dry-run config works" bash -lc "'$SCRIPT' --cwd '$repo_dir' --prompt 'x' --completion-promise 'DONE' --max-iterations 2 --dry-run >/dev/null"
expect_failure "resume without state fails" bash -lc "'$SCRIPT' --cwd '$repo_dir' --resume >/dev/null 2>&1"

printf '\nSmoke tests complete: %s passed, %s failed\n' "$pass_count" "$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
