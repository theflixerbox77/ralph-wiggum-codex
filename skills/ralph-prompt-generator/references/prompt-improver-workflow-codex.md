# Prompt Improver Workflow for Codex

This reference maps the requested 6-step prompt-improver workflow onto native Codex behavior.

## Inputs

The source prompt is provided in:
- `<user_prompt>`

Optional supporting context:
- `<examples>`
- `<feedback>`

## Native Codex review mapping

- `task_boundary` is translated into a stage heading and explicit task status inside the response.
- `notify_user` with `BlockedOnUser: true` becomes a native Codex review checkpoint where the assistant stops and asks the user to review the saved outputs before continuing.

Use the phrase `native Codex review checkpoint` when pausing so the stop is obvious.

## Repo-backed workspace

Artifacts live under:
- `docs/prompt-improver-spec/artifacts/implementation_plan.md`
- `docs/prompt-improver-spec/artifacts/task.md`
- `docs/prompt-improver-spec/artifacts/walkthrough.md`

Draft and final prompts live under:
- `docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md`
- `docs/prompt-improver-spec/final-prompts/<prompt-name>.md`

The draft file must be deleted after the final prompt is created.

## Phase A — Planning only

Scope:
- Step 1: Example identification
- Step 2: Planning analysis

Behavior:
- Create the prompt-improver workspace if it does not exist.
- Determine `<prompt-name>` using a descriptive kebab-case filename.
- Write `implementation_plan.md` with example normalization, planning analysis, quoted issues, ambiguities, and the constraint-preservation checklist.
- Write `task.md` with a checklist for Steps 1-6.
- End at a native Codex review checkpoint for Steps 1-2.

## Phase B — Initial draft only

Scope:
- Step 3: Initial draft

Behavior:
- Read the saved planning artifacts instead of redoing them.
- Write the draft prompt to `docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md`.
- Update `task.md` to show Steps 1-3 complete.
- If ambiguities remain, include a `Clarifying Questions` section.
- If no ambiguities remain, say so explicitly and proceed without that section.
- End with the phase-completion message for Steps 1-3 and pause.

## Phase C — Critique and revision planning only

Scope:
- Step 4: Critique and revision plan

Behavior:
- Read the draft prompt from `docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md`.
- Append the critique, quoted problem text, and revision plan to `implementation_plan.md`.
- Update `task.md` for Step 4.
- End at a second native Codex review checkpoint after Step 4.

## Phase D — Revision, final polish, and delivery

Scope:
- Step 5: Writing revision
- Step 6: Final polish

Behavior:
- Read and reuse all prior artifacts.
- Save the final prompt to `docs/prompt-improver-spec/final-prompts/<prompt-name>.md`.
- Delete the draft file at `docs/prompt-improver-spec/final-prompts/<prompt-name>-draft.md`.
- Write `walkthrough.md` with the original summary, key improvements, before/after comparisons, how to use the prompt, and the final path.
- Update `task.md` to show all steps complete.

Final response:
- Include the final completion message ending with `All 6 Steps Complete.`
- Include a short Ralph-ready invocation snippet after the completion message.
- The Ralph-ready invocation snippet should reference the saved production-ready prompt file instead of restating the whole prompt inline.

## Ralph-specific tailoring stays secondary

The prompt-improver's primary job is to improve the prompt itself.

Only add Ralph-specific execution wrapping at the end:
- how to use the saved prompt with `$ralph-wiggum-codex`
- optional validation or progress-scope guidance if it materially helps
- optional flags only when they materially improve the run

Do not turn the workflow back into a flags-first handoff generator.
