# Ralph Prompt Generator

`ralph-prompt-generator` is the companion skill that turns a rough prompt into a saved, production-ready prompt for `$ralph-wiggum-codex`.

This repo ships two Codex skills; this page documents the prompt-improver companion, not the execution loop itself.

It now follows a four-phase conversation model instead of emitting a one-shot runner block. Prompt improvement is primary; Ralph-specific execution wrapping is secondary.

## Inputs

Primary source prompt:
- `<user_prompt>`

Optional supporting context:
- `<examples>`
- `<feedback>`

## Workspace

The generator writes repo-backed outputs to:
- `docs/prompt-improver-spec/artifacts/implementation_plan.md`
- `docs/prompt-improver-spec/artifacts/task.md`
- `docs/prompt-improver-spec/artifacts/walkthrough.md`
- `docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md`
- `docs/prompt-improver-spec/final-prompts/<prompt-name>.md`

The draft file exists only during the workflow and is removed after the final prompt is created.

## Workflow

### Phase A

Steps 1-2: planning only.

- Analyze the source prompt.
- Normalize examples.
- Quote unclear language.
- Preserve hard constraints.
- Save planning artifacts.
- Pause at a native Codex review checkpoint after Steps 1-2.

### Phase B

Step 3: initial draft only.

- Reuse the saved planning artifacts.
- Write `docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md`.
- Update the task checklist.
- End with the draft path plus clarifying questions if any remain.

### Phase C

Step 4: critique and revision planning only.

- Read the draft prompt.
- Append the critique and revision plan to `implementation_plan.md`.
- Update the task checklist.
- Pause at a second native Codex review checkpoint after Step 4.

### Phase D

Steps 5-6: revision, final polish, and delivery.

- Save `docs/prompt-improver-spec/final-prompts/<prompt-name>.md`.
- Delete `docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md`.
- Write `walkthrough.md`.
- Finish with the required completion message and a short Ralph-ready invocation snippet.

## Output Shape

The final result is a prompt file plus short Ralph invocation snippet.

That means:
- the prompt itself lives in `docs/prompt-improver-spec/final-prompts/<prompt-name>.md`
- the chat response confirms completion and points Ralph at that saved file
- optional model/flag suggestions only appear when they materially improve the eventual Ralph run

When the prompt is being prepared for `$ralph-wiggum-codex`, the production-ready prompt file should be organized around:
- `Objective`
- `Acceptance Criteria`
- `Source of Truth`
- `Optional Verification`
- `Blocker Policy`

## Example Flow

### Example input

```text
$ralph-prompt-generator
<user_prompt>
Refactor auth middleware and prevent regressions.
</user_prompt>
```

### Phase A checkpoint

- Saves `implementation_plan.md`
- Saves `task.md`
- Pauses for review after Steps 1-2

### Phase B checkpoint

- Saves `docs/prompt-improver-spec/final-prompts/auth-middleware-refactor-draft.md`
- Returns the draft path and any clarifying questions

### Final delivery

- Saves `docs/prompt-improver-spec/final-prompts/auth-middleware-refactor.md`
- Removes the draft file
- Writes `walkthrough.md`
- Returns `All 6 Steps Complete.`
- Returns a prompt file plus short Ralph invocation snippet

## Relationship To Ralph Loop Skill

- `ralph-prompt-generator` improves and finalizes the prompt briefing.
- `ralph-wiggum-codex` executes the autonomous refinement loop.

Recommended sequence:
1. Run `$ralph-prompt-generator`.
2. Review the saved checkpoints when prompted.
3. Run the final prompt with `$ralph-wiggum-codex`.

## References

- `skills/ralph-prompt-generator/SKILL.md`
- `skills/ralph-prompt-generator/references/prompt-improver-principles.md`
- `skills/ralph-prompt-generator/references/prompt-improver-workflow-codex.md`
- `skills/ralph-prompt-generator/references/openai-codex-prompting-2026.md`
- `skills/ralph-prompt-generator/references/ralph-flag-selection-matrix.md`
- `docs/prompt-improver-spec/README.md`
