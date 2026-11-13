# Fixture provenance

Sanitized transcripts from REAL agent runs, used to test the adapters without the agents
installed. Each parser was also checked against the agent's own source.

## Codex/

From [jazzyalex/agent-sessions](https://github.com/jazzyalex/agent-sessions) at commit
`a93b22b` (`Resources/Fixtures/stage0/agents/codex/` and
`Resources/Fixtures/codex_053_rate_limit.jsonl`), where they are recorded in
`docs/agent-support/agent-support-ledger.yml` as verified captures (Codex CLI up to 0.157.0).
Renamed `rollout-*.jsonl` as Codex names them. That project's `codex_050`–`052` fixtures
were NOT taken: their `turn.completed` record type exists nowhere in Codex's source.

## Gemini/

`session-v040.jsonl` is `Resources/Fixtures/stage0/agents/gemini/jsonl_v040.jsonl` from the same
repository and commit, recorded in its `docs/agent-json-tracking.md` (2026-04-29) as the JSONL
written by a fresh Gemini CLI 0.40.0 session. Parser rules were checked against
google-gemini/gemini-cli at `2fe7c2d` (`packages/core/src/services/chatRecordingService.ts`,
`chatRecordingTypes.ts`, `config/storage.ts`, `config/projectRegistry.ts`, `tools/`).

## Grok/

`session/` and `subagent/` are `Resources/Fixtures/stage0/agents/grok/` (and its `subagent/`) from
the same repository and commit, recorded in `docs/agent-support/agent-support-matrix.yml` as
captures of real Grok Build CLI runs (`~/.grok/sessions/…`, verified to 1.0.24). Parser rules were
checked against xai-org/grok-build at `f0e3be1` (v1.0.41): `xai-grok-sampling-types/src/conversation.rs`,
`xai-grok-config/src/paths.rs`, `xai-grok-shell/src/session/{persistence.rs,usage_file.rs,signals.rs}`,
`xai-grok-agent/src/config.rs` and `xai-grok-tools/src/implementations/`. The capture's
`synthetic_reason: "environment_context"` is not in that source (a newer build's); the parser treats
any reason but `interjection` as Grok's, so it holds either way.

All three folders: MIT License — Copyright (c) 2026 Alexander Malakhov. The full licence text:
<https://github.com/jazzyalex/agent-sessions/blob/main/LICENSE>.

## Claude/

A session of Claude Code 2.1.316 with two sub-agents, taken from a real run and reduced by a script:
the files, their line order, every key, the tool names and the block types are the run's; every
text, prompt, path, id, model name and timestamp is replaced (`[trimmed for fixture]`,
`/tmp/project/Sources/FileN.ext`, numbered ids), and lines that are not messages are kept as one
line per type. Layout as Claude Code writes it: `<session>.jsonl`, and beside it
`<session>/subagents/agent-<id>.jsonl` with `agent-<id>.meta.json`. The session's own transcript
edits File1 to File55; the second sub-agent writes File56 and File57; the first edits nothing.

