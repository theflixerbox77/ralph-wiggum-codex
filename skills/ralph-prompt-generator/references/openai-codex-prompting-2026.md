# OpenAI + Codex Prompting Notes (2026)

Last verified: March 6, 2026.

This file captures the prompt-engineering and model-selection assumptions used by `ralph-prompt-generator`.

Treat this as a secondary reference. Prompt improvement and constraint preservation come first; model or profile guidance only belongs in the final Ralph wrapper when it materially helps execution.

## Model Selection Defaults

- Codex sessions: prefer the current Codex default model unless the user explicitly wants a pinned model.
  - As of March 6, 2026, the newest model powering Codex and Codex CLI is `gpt-5.4`.
  - Pinning is optional; omit the model line when the current Codex default is sufficient.

- API-oriented runs: prefer `gpt-5-codex` when the user wants a pinned coding model.
  - Use `gpt-5.4` instead when the workflow spans coding plus broader planning/writing tasks.

If the user explicitly requests a different model, preserve it.

## Reasoning Effort

If the final Ralph wrapper includes a `Reasoning effort: <medium|high|xhigh>` recommendation, use this guidance:

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

If you use profiles, the generator can recommend `--profile ralph_high` / `--profile ralph_xhigh` in the final Ralph invocation snippet.

## Source Anchors

- [Codex Models](https://developers.openai.com/codex/models/)
- [Codex Config Reference](https://developers.openai.com/codex/config-reference/)
- [Codex Skills](https://developers.openai.com/codex/skills/)
- [Slash Commands in Codex CLI](https://developers.openai.com/codex/cli/slash-commands/)
- [Prompt Engineering Guide](https://platform.openai.com/docs/guides/prompt-engineering)
- [Reasoning Best Practices](https://platform.openai.com/docs/guides/reasoning-best-practices)
