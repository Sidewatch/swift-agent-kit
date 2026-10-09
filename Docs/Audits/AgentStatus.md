# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift); line-by-line logic review was targeted at the areas changed since
5 Sep 2026, not the whole tree. Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Fixed: CLAUDE.md / AGENTS.md module map listed TerminalSummary, SubagentSummary, AgentActivity — `Models/` holds only `ForegroundInfo`.

## Logic review — 18 Sep 2026, later (every source and test file, line by line)

Fixed, pinned by a test that fails against the old rule:

- **`amplify` was an agent.** `isAgentProcess` matched a process name by bare `hasPrefix` against
  the whitelist, so anything that merely STARTS with an agent's name — `amplify` (AWS), `ampl`,
  `ampere` for "amp"; `copilotd`, `goosefs`, `geminiscope` — made the terminal read "Working" with
  an agent badge. The prefix now has to end at a word boundary (`hasAgentPrefix`: the next
  character is not a letter), which keeps `claude-code`, `codex-cli`, `grok-cli`, `cursor-agent`
  and `claude2`.

Reviewed and sound: `ScreenStateClassifier` (a prompt outranks a working marker; the ask phrases
need a `?` or a trailing `:`; the trimmed/lowercased rows stay index-aligned), `TerminalStatus.derive`'s
precedence (attention → busy → completion), the path tier's exact-component rule, the args tier's
token split, `AgentProcess.commandName`'s runtime/script/`-c`/`-m` handling.

## Program Status Protocol — 9 Oct 2026

Added, each rule pinned by a test that fails against the mutant named:

- `ProgramStatusState` / `ProgramStatusKind` — the OSC 7501 words as raw values, `CaseIterable`.
  `ProgramStatusReportTests` pins each word and the count (mutant: `working` → `"busy"` fails).
- `ProgramStatusReport` — one record (id, state, kind, progress, app, title, message); the empty
  id is the root.
- `ReportedActivity` — the merge. Reports decide while any is held, the screen otherwise
  (mutant: screen consulted first fails `testAReportOutranksTheScreenWhicheverWaySay`);
  `promptStarted()` drops working/blocked and keeps results (mutant: drops nothing fails
  `testAReportOlderThanANewPromptIsDropped`); across ids the most urgent wins, blocked >
  working > error > done > idle, the root among equals, then the newest (mutant: root-first fails
  `testTheMostUrgentRecordDecidesAcrossIds`). The alternative, the root alone, would hide a child
  asking permission.
- `AgentActivity` — working / needsYou(kind) / idle / finished / failed; `runEnded(from:to:)` is
  the live → settled edge (mutant: ignoring the earlier side fails
  `testARunEndsOnlyOnTheEdgeFromLiveToSettled`).
- `TerminalAttention.done` restored — now something produces it: a resident agent's own report
  going from working to idle. `derive` maps it to `.finished` ahead of busy (mutant: the line
  removed fails `testAttentionOutranksTheProcessAndNeedsYouSortsFirst`).
- `ProgramStatusKind.label` — the notification body when a blocked record carries no message;
  three strings added to the catalogue with drafted translations in the eight shipped languages.

Reviewed and sound: the host keeps lifetime for a shell that sends no prompt marks (the app
resets on its agent-leaves edge); the screen never yields a settled verdict, so `.done` is
report-only by construction.

## Security review — 9 Oct 2026

- **`AgentSendPolicy`** (Core/): the one rule for text a host did not type. Sidewatch's "Comment for
  Agent" submitted a message quoting a diff line into `agents.count == 1 ? agents[0] : current`,
  so a review of a file holding `` `touch MARKER` `` ran it in the current shell, bracketed paste
  or not — the trailing Return submits either. The rule: submit only into a terminal whose status
  `isLiveAgent` (`agent`, `waiting`; not `finished`, where the shell may be back, and never a
  shell); the current terminal when it is one, else the single live agent (when the host allows
  redirecting — not for a terminal the person chose), else paste into the current terminal
  unsubmitted. `AgentSendPolicyTests` (four tests). Mutant: `isLiveAgent` counting `finished` —
  4 failures. The host's harness drives the real PTY (`--selftest-send-safety`).

## Known non-issues (do not "fix" these again)

- `ScreenStateClassifier`'s `try!` regexes are literal patterns; a bad pattern would fail at first use, not in the field.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review with the app's terminal subsystem: `TerminalAttention.done` removed (nothing produced it since the hooks layer went), hook wording in `TerminalStatus`/`TerminalAttention` docs replaced by the screen classifier, `commandName` treats `-c`/`-e`/`-p` snippets as the runtime and `-m` as the module. The host-side `KERN_PROCARGS2` bug that starved `commandName` of real argv is fixed in the app.
- 18 Sep 2026 (later) — logic review of the whole package: the `amplify` false positive above, Claude with David.
- 22 Sep 2026 — `BuildDiagnostic` moved in from Sidewatch (`Terminal/BuildDiagnostic.swift`, unchanged rules, made public) with its harness ported to `BuildDiagnosticTests`; `SECURITY.md` added to match the family.
- 24 Sep 2026 — `promptLine`, three Claude Code 2.1.2xx prompt shapes from herdr's manifest (MCP elicitation, dynamic-workflow confirmation, the confirm/cancel footer), `AttentionNotice`; mutants: new phrases dropped, footer rule dropped, visible pane notified — each fails.
- 9 Oct 2026 — Program Status Protocol (OSC 7501): `ProgramStatusState`, `ProgramStatusKind`, `ProgramStatusReport`, `ReportedActivity`, `AgentActivity`, `TerminalAttention.done` restored; six mutants, each fails its test (section above). 38 tests green.
- 9 Oct 2026 — security review: `AgentSendPolicy`, `TerminalStatus.isLiveAgent` (section above); 42 tests green.
