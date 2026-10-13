# Swift Agent Kit

Terminal AI coding agents, read from the outside: what a terminal's agent is doing right now, and what its session did — for Claude Code, Codex, Gemini and Grok. Read-only; it never talks to a model.

- Modules `AgentSession`, `AgentStatus`, each in `Sources/<Module>` with tests in `Tests/<Module>Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.
- Each module's user-facing documentation is `Docs/Modules/<Module>.md`; its last audit is `Docs/Audits/<Module>.md` — read it before auditing, and extend it rather than redo it.

## AgentSession — `Sources/AgentSession`

### Module map
- `Adapters/` — the engine: adapters: Agents (registry, `resolve(candidates:preferring:under:)` → `Hit` (adapter, root, session), `editedFiles`), ClaudeCodeAdapter, CodexAdapter, GeminiAdapter, GrokAdapter
- `Monitoring/` — the engine: monitoring: BurnDetector (loop detection over a timeline)
- `Models/` — value types — the shape of a thing, nothing else: AgentSummary, AgentUsage, ClaudeCredentials, ClaudeQuota, ClaudeQuota+Display, TimelineEvent, TurnBoundary, TurnEffort (+Display: `modelLabel`, `costLabel`, `shortModel`), UsageReport
- `Protocols/` — protocols the module exposes: AgentAdapter
- `Support/` — pure helpers: ApplyPatch, ClaudeKeychain, ClaudeSessionIndex (the folder encoding), ClaudeSessionLocator (which transcript is a project's: every candidate folder, the launch `cwd` check, subfolder search), CodexSessionIndex, GeminiSessionIndex, GrokSessionIndex (+ its usage sidecars), PathForms (every spelling of a cwd: `/private`, symlinks), SessionChoice (the chosen transcript is held while it is written), LookupMisses (a miss is believed 2 s), DirectoryReader (counted listings), SessionPaths, ClockFormat, FileStat, ISOTimestamp, JSONFile, PersistedOutput, TranscriptText
- `Transcripts/` — the engine: transcripts: TranscriptParsing (one line-at-a-time state per format), TranscriptCache (incremental reads; a line over `lineCap`, 4 MB, is skipped whole and never held), EventBuffer (the bounded timeline), ClaudeTranscriptState, CodexTranscriptState, GeminiTranscriptState, GrokTranscriptState
- `Tests/AgentSessionTests/Fixtures/` — sanitized real transcripts per agent; `NOTICE.md` records where each came from and which source each parser was checked against
- `Usage/` — the engine: usage: ClaudeQuotaCache, ClaudeUsageEndpoint, ModelPricing, UsageAggregator, UsageRecord, UsageTotals

## AgentStatus — `Sources/AgentStatus`

### Module map
- `Core/` — the engine: TerminalStatus (the whitelist + derive; `isLiveAgent`), AgentSendPolicy (where text a host did not type may go: submitted only into a live agent — the current terminal when it runs one, else the single live agent — otherwise pasted unsubmitted), ScreenStateClassifier, ReportedActivity (the program's OSC 7501 records merged with the screen: reports decide while any is held, the most urgent record wins, `promptStarted` / `reset` for lifetime), AgentActivity (the one verdict: working / needsYou(kind) / idle / finished / failed, `runEnded(from:to:)`), AgentProcess (argv naming), BuildDiagnostic (`parse` one `path:line[:col]: severity: message` line, `parseAll` keeping the last per location, `stripANSI`)
- `Enums/` — TerminalAttention (waiting, done), ScreenState, ProgramStatusState and ProgramStatusKind (the protocol's words as raw values, pinned by a test)
- `Models/` — ForegroundInfo, ProgramStatusReport (one OSC 7501 record)

### Rules of this module
- Agent recognition is a WHITELIST: guessing would catch `node` and `python`. Path matching is by exact component, never prefix (a project called `claude-notes` is not an agent).
- `derive` has no defaulted parameters: omitting one used to silently degrade the answer.
- Nothing here knows about colours or views; the host maps `TerminalStatus` to its tint.
- A program that speaks OSC 7501 is believed over the screen; the screen is read only when no report is held. The protocol's words are someone else's vocabulary: `ProgramStatusState` / `ProgramStatusKind` raw values are pinned word for word, and a rename fails a test before it silently stops matching.
- `BuildDiagnostic` reads ONE format and never infers a diagnostic the terminal did not print: a wrong gutter mark is believed, so it is worse than a missing one.
- Text derived from a file or a project (a review comment quoting a diff line, a project's prompt) is SUBMITTED only to a live agent (`agent` or `waiting`, never `finished` or a shell), through `AgentSendPolicy`; a shell would run a quoted line as a command.

## Rules

Read `CONTRIBUTING.md` for the folder layout and the pull-request rules.

@CONTRIBUTING.md
