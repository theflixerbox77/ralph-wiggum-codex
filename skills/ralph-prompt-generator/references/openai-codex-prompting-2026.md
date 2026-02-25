# OpenAI + Codex Prompting Notes (2026)

Last verified: February 25, 2026.

This file captures the prompt-engineering and model-selection assumptions used by `ralph-prompt-generator`.

## Model Selection Defaults

- Codex sessions: default `gpt-5.3-codex`.
  - Recommended for most coding tasks in Codex surfaces.
  - API access is not generally available yet.

- API-oriented runs: default `gpt-5.2-codex`.
  - Available via API.

If the user explicitly requests a different model, preserve it.

## Reasoning Effort

The generator emits a `Reasoning effort: <medium|high|xhigh>` recommendation.

Guidance:
- `medium`: narrow, low-ambiguity tasks.
- `high`: multi-step engineering work.
- `xhigh`: ambiguous or high-risk work.

Notes:
- In Codex config, `model_reasoning_effort` exists and `xhigh` is model-dependent.
- In API reasoning best practices, OpenAI recommends direct prompts with clear delimiters and success criteria; avoid chain-of-thought prompting language.

## Prompting Rules To Enforce

- Keep prompts simple, direct, and explicit.
- Use strong delimiters (Markdown sections, XML tags) for instructions vs context.
- Define success criteria that are observable.
- Make validations explicit.
- Avoid "think step by step" / chain-of-thought style prompting.
- Start zero-shot; add examples only if they materially improve reliability.

## Where Reasoning Effort Gets Configured

Depending on the surface, reasoning effort may be set via Codex configuration.

Example (illustrative) profile-scoped config:

```toml
# ~/.codex/config.toml

[profiles.ralph_high]
model_reasoning_effort = "high"

[profiles.ralph_xhigh]
model_reasoning_effort = "xhigh"
```

If you use profiles, the generator can recommend `--profile ralph_high` / `--profile ralph_xhigh` in the handoff block.

## Source Anchors

- [Codex Models](https://developers.openai.com/codex/models/)
- [Codex Config Reference](https://developers.openai.com/codex/config-reference/)
- [Codex Skills](https://developers.openai.com/codex/skills/)
- [Slash Commands in Codex CLI](https://developers.openai.com/codex/cli/slash-commands/)
- [Prompt Engineering Guide](https://platform.openai.com/docs/guides/prompt-engineering)
- [Reasoning Best Practices](https://platform.openai.com/docs/guides/reasoning-best-practices)
