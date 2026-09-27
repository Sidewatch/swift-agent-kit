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

MIT License — Copyright (c) 2026 Alexander Malakhov. The full licence text:
<https://github.com/jazzyalex/agent-sessions/blob/main/LICENSE>.
