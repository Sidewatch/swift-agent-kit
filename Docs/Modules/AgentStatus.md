# Swift Agent Status

What a terminal is doing: idle, running something, running a coding agent, waiting on you, or finished — derived from the pty's foreground process (name, executable path, argv), with a screen-scrape fallback for telling a waiting agent from a thinking one. And what the terminal SAID: the compiler and linter diagnostics in its scrollback, parsed so a host can mark the lines the toolchain named.

Extracted from Sidewatch. Recognises Claude Code, Codex, Gemini CLI, OpenCode, Aider, Hermes, Grok and pi.

> **Note:** there are no hooks. This reads the process table, the program's own status reports (OSC 7501, when it sends them) and the screen, and nothing else, so it needs nothing installed and has no config file to go stale.

## Features

- **Status derivation** — `TerminalStatus.derive(foreground:unseenCompletion:attention:)`: one rule, no defaulted parameters, an explicit attention signal outranking the process table
- **Agent recognition** — a deliberate whitelist across the three install shapes: by name (`codex`), by executable path (`…/claude/versions/2.1.223`), by argv (`node …/@openai/codex/cli.js`); exact-only for names too short to prefix-match (`pi`)
- **Command naming from argv** — `AgentProcess.commandName(fromArgs:)`: "codex", not "node"; "claude", not a version number
- **Build diagnostics from the scrollback** — `BuildDiagnostic.parse(_:)` reads ONE shape, `path:line[:col]: error|warning|note: message`, anchored so prose with a colon, a URL, a timestamp or a stack frame cannot match; `parseAll(_:)` keeps the LAST diagnostic per location (a build prints its history); `stripANSI(_:)` first, because compilers colour their output
- **Screen-state fallback** — `ScreenStateClassifier.classify(rows)`: a numbered choice with a cursor, a y/n question, an explicit "Allow …?" → waiting; "esc to interrupt" → working; nil otherwise (the honest answer, most of the time)
- **The program's own account** — `ReportedActivity` holds the terminal's Program Status Protocol (OSC 7501) records (`ProgramStatusReport`: `state` idle/working/done/blocked/error, `kind` permission/question/auth, `progress`, `app`, `title`, `message`) and merges them with the screen into one `AgentActivity`: while any record is held the reports decide and the screen is not consulted; across several ids the most urgent wins (blocked > working > error > done > idle, the root among equals); `promptStarted()` drops working/blocked as a new shell prompt does, `reset()` forgets a program that left. `AgentActivity.runEnded(from:to:)` names the live → settled edge, which is a turn's end for an agent that never leaves the foreground
- **Where text may go** — `AgentSendPolicy.verdict(current:terminals:redirectsToSingleAgent:)`: text a host derived from a file (a review comment quoting a diff line, a selection, a project's prompt) is submitted only into a terminal whose status `isLiveAgent` (`agent` or `waiting`): the current terminal when it runs one, else the single live agent when redirecting is allowed, else the current terminal with the text pasted and left unsubmitted — a shell would run a quoted `` `touch marker` `` as a command
- **Where a shell starts** — `TerminalStartFolder.folder(inheriting:project:)`: a shell that would inherit a folder (a restored tab's saved one, the focused shell's live one) keeps it inside the open project, a subfolder included, and starts in the project otherwise; `moves(to:from:)` says whether an idle shell follows a project that just opened. Inside is decided by spelling and by real path, since a shell reports its resolved folder
- **Value types** — `ForegroundInfo`, `TerminalAttention` (`waiting`, `done`), `ScreenState`, `ProgramStatusState`, `ProgramStatusKind`, `ProgramStatusReport`; all `Sendable`
- **Small** — Foundation plus swift-foundation-extensions; colours and fonts are the host's

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-agent-kit.git", from: "0.1.0")
]
```

## Usage

```swift
import AgentStatus

let fg = ForegroundInfo(isBusy: true, process: "node", processPath: "/usr/local/bin/node",
                        processArgs: "node /usr/local/lib/node_modules/@openai/codex/bin/codex.js")
TerminalStatus.derive(foreground: fg, unseenCompletion: false, attention: nil)   // .agent
AgentProcess.commandName(fromArgs: fg.processArgs)                                // "codex"

ScreenStateClassifier.classify(["Run `npm test`? [y/N]"])                          // .waitingForInput

// A program that speaks the Program Status Protocol (OSC 7501) is believed over the screen.
var reported = ReportedActivity()
reported.update([ProgramStatusReport(state: .working), ProgramStatusReport(id: "build", state: .blocked, kind: .permission)])
reported.activity(screen: .working)                                                // .needsYou(kind: .permission): the blocked child wins
reported.update([ProgramStatusReport(state: .idle)])
AgentActivity.runEnded(from: .working, to: reported.activity(screen: nil))         // true: the turn ended
TerminalStatus.derive(foreground: fg, unseenCompletion: false, attention: .done)   // .finished, busy or not
reported.reset()                                                                   // another program took the terminal
reported.activity(screen: .waitingForInput)                                        // .needsYou(kind: nil) — the screen again

[TerminalStatus.idle, .agent, .waiting].sorted { $0.priority < $1.priority }       // waiting first

// A review comment on its way to a terminal: submitted only into a live agent.
let terminals = [AgentSendPolicy.Candidate(id: shellID, status: .idle), .init(id: claudeID, status: .agent)]
AgentSendPolicy.verdict(current: shellID, terminals: terminals)                     // target claudeID, submits: true
AgentSendPolicy.verdict(current: shellID, terminals: [.init(id: shellID, status: .idle)])  // target shellID, submits: false — paste it, say so

// What the build said, out of the terminal's rows (oldest first): one diagnostic per location, the latest wins.
let rows = screenRows.map(BuildDiagnostic.stripANSI)
for d in BuildDiagnostic.parseAll(rows) {
    print(d.path, d.line, d.column ?? 0, d.severity, d.message)   // "Main.swift", 42, 17, .error, "cannot find 'foo' in scope"
}
```

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT © 2026 ArrayPress Limited

`ScreenStateClassifier.promptLine(_:)` names the line that makes a screen a prompt (the question above a cursor, a y/n, an MCP elicitation, a dialog footer with "enter to confirm · esc to cancel"), and `AttentionNotice` is the rule for notifying about it: on, and only when the app is in the background or the pane is off screen — never for the pane in front of the person.
