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

## Known non-issues (do not "fix" these again)

- `ScreenStateClassifier`'s `try!` regexes are literal patterns; a bad pattern would fail at first use, not in the field.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review with the app's terminal subsystem: `TerminalAttention.done` removed (nothing produced it since the hooks layer went), hook wording in `TerminalStatus`/`TerminalAttention` docs replaced by the screen classifier, `commandName` treats `-c`/`-e`/`-p` snippets as the runtime and `-m` as the module. The host-side `KERN_PROCARGS2` bug that starved `commandName` of real argv is fixed in the app.
- 18 Sep 2026 (later) — logic review of the whole package: the `amplify` false positive above, Claude with David.
- 22 Sep 2026 — `BuildDiagnostic` moved in from Sidewatch (`Terminal/BuildDiagnostic.swift`, unchanged rules, made public) with its harness ported to `BuildDiagnosticTests`; `SECURITY.md` added to match the family.
- 24 Sep 2026 — `promptLine`, three Claude Code 2.1.2xx prompt shapes from herdr's manifest (MCP elicitation, dynamic-workflow confirmation, the confirm/cancel footer), `AttentionNotice`; mutants: new phrases dropped, footer rule dropped, visible pane notified — each fails.
