# Swift Agent Kit

Terminal AI coding agents, read from the outside: what a terminal's agent is doing right now, and what its session did — for Claude Code, Codex, Gemini and Grok. Read-only; it never talks to a model.

- Modules `AgentSession`, `AgentStatus`, each in `Sources/<Module>` with tests in `Tests/<Module>Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.
- Each module's user-facing documentation is `Docs/Modules/<Module>.md`; its last audit is `Docs/Audits/<Module>.md` — read it before auditing, and extend it rather than redo it.

## AgentSession — `Sources/AgentSession`

### Module map
- `Adapters/` — the engine: adapters: Agents (registry, `resolve(candidates:preferring:under:)` → `Hit` (adapter, root, session), `editedFiles`), ClaudeCodeAdapter, CodexAdapter, GeminiAdapter, GrokAdapter
- `Monitoring/` — the engine: monitoring: BurnDetector (loop detection over a timeline), TranscriptTail (what is new since the last poll: count + a tail fingerprint, the LAST occurrence past the 300-event cap; the first look baselines silently), DockBadgeVotes (one Dock badge from every window's vote: a question outranks a wait, one window clearing leaves another's), DockBounceAllowance (at most one Dock bounce per absence, renewed on return — Terminal's manner), AwayDigest (files edited and tool runs while the person was away; a summary only after 180 s and with something to tell, a cost only from half a cent)
- `Models/` — value types — the shape of a thing, nothing else: AgentSessionLookup (where to look for a live session: candidates, the agent wanted, the project), AgentSummary, AgentUsage, TimelineEvent, TurnBoundary, TurnEffort (+Display: `modelLabel`, `costLabel`, `shortModel`)
- `Protocols/` — protocols the module exposes: AgentAdapter
- `Support/` — pure helpers: AgentSessionLookup+Terminals (`resolve()`, `perTerminal` — one lookup per agent terminal preferring THAT terminal's agent, so two agents in one folder keep their own sessions — `uniqued`, `Agents.sessionKey`), ApplyPatch, ClaudeSessionIndex (the folder encoding), ClaudeSessionLocator (which transcript is a project's: every candidate folder, the launch `cwd` check, subfolder search), CodexSessionIndex, GeminiSessionIndex (subfolder search through the `projects.json` registry), GrokSessionIndex (+ its usage sidecars; subfolder search by reading each bucket's path back), PathForms (every spelling of a cwd: `/private`, symlinks), EditReconciliation (which changed files an agent's edits account for, matched by real path so a project opened through a link or `/tmp` still matches), SessionChoice (the chosen transcript is held while it is written), LookupMisses (a miss is believed 2 s), DirectoryReader (counted listings), SessionPaths, ClockFormat, FileStat, ISOTimestamp, JSONFile, PersistedOutput, TranscriptText
- `Transcripts/` — the engine: transcripts: TranscriptParsing (one line-at-a-time state per format), TranscriptCache (incremental reads; a line over `lineCap`, 4 MB, is skipped whole and never held), EventBuffer (the bounded timeline), ClaudeTranscriptState, CodexTranscriptState, GeminiTranscriptState, GrokTranscriptState
- `Tests/AgentSessionTests/Fixtures/` — sanitized real transcripts per agent; `NOTICE.md` records where each came from and which source each parser was checked against
- `Usage/` — the engine: usage: ModelPricing

## AgentStatus — `Sources/AgentStatus`

### Module map
- `Core/` — the engine: TerminalStatus (the whitelist + derive; `isLiveAgent`), AgentSendPolicy (where text a host did not type may go: submitted only into a live agent — the current terminal when it runs one, else the single live agent — otherwise pasted unsubmitted), AttentionCycle (which terminal "next agent needing you" goes to: every waiting one before any finished one, searched after the current terminal and wrapping), ScreenStateClassifier, ReportedActivity (the program's OSC 7501 records merged with the screen: reports decide while any is held, the most urgent record wins, `promptStarted` / `reset` for lifetime), AgentActivity (the one verdict: working / needsYou(kind) / idle / finished / failed, `runEnded(from:to:)`), AgentProcess (argv naming), BuildDiagnostic (`parse` one `path:line[:col]: severity: message` line, `parseAll` keeping the last per location except that a `note:` never replaces an error or warning, `stripANSI`), BuildDiagnostic+Marks (`marks`: one severity per resolved file and line, the more serious winning; `resolvedPath` against the command's directory), AgentRunEdge (the run's edges stepped per foreground reading: a fresh run, the agent leaving, Done at the prompt — not announced again when the reports already said it), ProgramNotification (OSC 777 `notify;title;body`, the title prefixed with the program), PastePolicy (how many commands an unbracketed multi-line paste would run), TerminalStartFolder (a shell inheriting a folder keeps it inside the open project and starts in the project otherwise; whether an idle shell follows a project that opens; by spelling and by real path)
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
