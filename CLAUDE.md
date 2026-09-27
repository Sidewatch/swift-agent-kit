# Swift Agent Kit

Terminal AI coding agents, read from the outside: what a terminal's agent is doing right now, and what its session did — for Claude Code, Codex, Gemini and Grok. Read-only; it never talks to a model.

- Modules `AgentSession`, `AgentStatus`, each in `Sources/<Module>` with tests in `Tests/<Module>Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.
- Each module's user-facing documentation is `Docs/Modules/<Module>.md`; its last audit is `Docs/Audits/<Module>.md` — read it before auditing, and extend it rather than redo it.

## AgentSession — `Sources/AgentSession`

### Module map
- `Adapters/` — the engine: adapters: Agents (registry, `resolve(candidates:preferring:)`, `editedFiles`), ClaudeCodeAdapter, CodexAdapter, GeminiAdapter, GrokAdapter
- `Monitoring/` — the engine: monitoring: BurnDetector (loop detection over a timeline)
- `Models/` — value types — the shape of a thing, nothing else: AgentSummary, AgentUsage, ClaudeCredentials, ClaudeQuota, ClaudeQuota+Display, TimelineEvent, TurnBoundary, TurnEffort (+Display: `modelLabel`, `costLabel`, `shortModel`), UsageReport
- `Protocols/` — protocols the module exposes: AgentAdapter
- `Support/` — pure helpers: ApplyPatch, ClaudeKeychain, ClaudeSessionIndex, CodexSessionIndex, GeminiSessionIndex, GrokSessionIndex (+ its usage sidecars), SessionPaths, ClockFormat, Files, FileStat, ISOTimestamp, JSONFile, PersistedOutput, TranscriptText
- `Transcripts/` — the engine: transcripts: TranscriptParsing (one line-at-a-time state per format), TranscriptCache (incremental reads), EventBuffer (the bounded timeline), ClaudeTranscriptState, CodexTranscriptState, GeminiTranscriptState, GrokTranscriptState
- `Tests/AgentSessionTests/Fixtures/` — sanitized real transcripts per agent; `NOTICE.md` records where each came from and which source each parser was checked against
- `Usage/` — the engine: usage: ClaudeQuotaCache, ClaudeUsageEndpoint, ModelPricing, UsageAggregator, UsageRecord, UsageTotals

## AgentStatus — `Sources/AgentStatus`

### Module map
- `Core/` — the engine: TerminalStatus (the whitelist + derive), ScreenStateClassifier, AgentProcess (argv naming), BuildDiagnostic (`parse` one `path:line[:col]: severity: message` line, `parseAll` keeping the last per location, `stripANSI`)
- `Enums/` — TerminalAttention, ScreenState
- `Models/` — ForegroundInfo

### Rules of this module
- Agent recognition is a WHITELIST: guessing would catch `node` and `python`. Path matching is by exact component, never prefix (a project called `claude-notes` is not an agent).
- `derive` has no defaulted parameters: omitting one used to silently degrade the answer.
- Nothing here knows about colours or views; the host maps `TerminalStatus` to its tint.
- `BuildDiagnostic` reads ONE format and never infers a diagnostic the terminal did not print: a wrong gutter mark is believed, so it is worse than a missing one.

## Rules

@CONTRIBUTING.md
