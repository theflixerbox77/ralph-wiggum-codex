# Ralph Simplification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce Ralph's user-facing complexity without removing the runner guardrails that make long unattended runs reliable.

**Architecture:** Keep the existing shell runner and smoke-test harness, but simplify the completion contract so normal runs do not require deprecated or irrelevant JSON fields. Then tighten the skill/docs layer so the primary experience is a minimal one-skill flow with current model guidance instead of stale, flag-heavy setup.

**Tech Stack:** Bash, Python (schema assertions inside smoke tests), Codex skills metadata, Markdown docs

---

### Task 1: Lock in the minimal JSON contract with failing smoke tests

**Files:**
- Modify: `tests/fixtures/codex`
- Modify: `tests/smoke.sh`
- Test: `tests/smoke.sh`

**Step 1: Write the failing test**

Add new stub scenarios that emit a minimal completion JSON object with only `status`, `evidence`, and `next_step`, then add smoke expectations that:
- a changed run succeeds with the minimal JSON object
- the generated schema only requires the base fields
- `--completion-promise` still rejects completion when the promise field is omitted

**Step 2: Run test to verify it fails**

Run: `bash tests/smoke.sh`
Expected: FAIL on the new minimal-contract expectations because the schema currently requires `no_change_justification` and `completion_promise`.

**Step 3: Write minimal implementation**

Do not touch docs yet. Update only the runner pieces needed so the new tests can pass.

**Step 4: Run test to verify it passes**

Run: `bash tests/smoke.sh`
Expected: PASS for the new minimal-contract coverage.

### Task 2: Simplify the runner contract without weakening guardrails

**Files:**
- Modify: `skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh:731`
- Test: `tests/smoke.sh`

**Step 1: Update the schema writer**

Make `no_change_justification` and `completion_promise` optional schema properties instead of required fields.

**Step 2: Update the iteration prompt**

Change the prompt contract so:
- `status`, `evidence`, and `next_step` are the only always-required keys
- `no_change_justification` is only requested when no scoped change happened
- `completion_promise` is only requested when compatibility mode is enabled

**Step 3: Preserve enforcement in code**

Keep the existing parser defaults and completion-promise mismatch logic so compatibility mode still works when explicitly enabled.

**Step 4: Re-run smoke tests**

Run: `bash tests/smoke.sh`
Expected: PASS with no regression in timeout, resume, progress-gate, or lock behavior.

### Task 3: Simplify the primary skill surface and refresh stale model guidance

**Files:**
- Modify: `README.md`
- Modify: `skills/ralph-wiggum-codex/SKILL.md`
- Modify: `skills/ralph-wiggum-codex/agents/openai.yaml`
- Modify: `skills/ralph-prompt-generator/SKILL.md`
- Modify: `skills/ralph-prompt-generator/references/openai-codex-prompting-2026.md`

**Step 1: Simplify the main skill positioning**

Reframe the README and main skill around:
- a minimal primary invocation
- the companion generator as optional
- deprecated compatibility flags as advanced/legacy only

**Step 2: Reduce metadata verbosity**

Shorten the main skill `default_prompt` so the Codex app presents the skill in plain language instead of flag-heavy jargon.

**Step 3: Refresh model guidance**

Update the prompt-generator guidance to reflect the current Codex/OpenAI model situation, avoiding stale hardcoded defaults like `gpt-5.3-codex` for Codex sessions.

**Step 4: Verify text changes manually**

Check the modified files in place to confirm the docs are consistent with the runner behavior and do not reintroduce deprecated requirements.

### Task 4: Final verification

**Files:**
- Verify: `tests/smoke.sh`

**Step 1: Run the full smoke suite**

Run: `bash tests/smoke.sh`
Expected: PASS with zero failures.

**Step 2: Review diff for scope**

Run: `git diff -- README.md skills/ralph-wiggum-codex/SKILL.md skills/ralph-wiggum-codex/agents/openai.yaml skills/ralph-wiggum-codex/scripts/ralph-loop-codex.sh skills/ralph-prompt-generator/SKILL.md skills/ralph-prompt-generator/references/openai-codex-prompting-2026.md tests/fixtures/codex tests/smoke.sh`
Expected: Only the simplification changes above; no unrelated refactors.
