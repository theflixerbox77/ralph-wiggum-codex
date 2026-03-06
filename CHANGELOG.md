# Changelog

This project uses pre-1.0 semantic versioning.

The first tagged release is `v0.8.0`, not `v1.0.0`, because the repo already has meaningful development history but the skill contracts are still evolving.

## v0.8.1 - 2026-03-06

Objective-first Ralph loop release.

### Added

- acceptance-criteria-aware work/review loop fixtures and contract coverage
- dedicated `tests/ralph_loop_contract.sh` coverage for the main skill and docs
- first-class work/review state artifacts including review feedback, review result, and blocked markers

### Changed

- redesigned `ralph-wiggum-codex` around objective + acceptance criteria + mandatory fresh-context review
- made optional verification secondary to the task instead of the product story
- aligned `ralph-prompt-generator` output with `Objective`, `Acceptance Criteria`, `Source of Truth`, `Optional Verification`, and `Blocker Policy`
- removed `--completion-promise` from the main loop contract and documentation
- fixed dry-run stale-lock handling so malformed metadata blocks unless explicitly reclaimed

### Notes

- this is still pre-1.0 software; the public contract is cleaner and more useful, but still evolving
- GitHub Releases remain the primary distribution surface for this repo right now

## v0.8.0 - 2026-03-05

Initial tagged release for the current Codex-native skill package.

### Added

- `ralph-wiggum-codex` as the primary long-running implement -> validate -> refine skill
- `ralph-prompt-generator` as a staged prompt-improver companion skill
- deterministic `codex` binary selection, structured event artifacts, and per-iteration progress artifacts
- prompt-improver workspace and contract tests for the staged generator flow

### Changed

- simplified the loop completion schema so deprecated compatibility fields are optional again
- refocused the prompt-generator away from a flags-first handoff and toward prompt critique, drafting, revision, and final delivery
- updated repo documentation to describe the two-skill model, release process, and current versioning approach

### Notes

- `--completion-promise` remains available for compatibility but is deprecated
- GitHub Releases are the primary distribution surface for this repo right now
