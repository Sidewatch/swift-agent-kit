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

Both folders: MIT License — Copyright (c) 2026 Alexander Malakhov. The full licence text:
<https://github.com/jazzyalex/agent-sessions/blob/main/LICENSE>.
