# Swift Agent Kit

Terminal AI coding agents, read from the outside: what a terminal's agent is doing right now, and what its session did — for Claude Code, Codex, Gemini and Grok. Read-only; it never talks to a model.

## Modules

Each module is its own library product: depend on the package, then only on the products you use.

| Module | What it is |
|---|---|
| [`AgentSession`](Docs/Modules/AgentSession.md) | Reads coding agents' session transcripts (Claude Code, Codex, Gemini, Grok) into one timeline, usage and edited-files model. |
| [`AgentStatus`](Docs/Modules/AgentStatus.md) | What a terminal is doing — idle, running something, running an agent, waiting on you, finished — from its foreground process and screen. |

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-agent-kit.git", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "AgentSession", package: "swift-agent-kit"),
    ]),
]
```

## Usage

### AgentSession

```swift
import AgentSession

let root = URL(fileURLWithPath: "/path/to/project")

// Which agent has a session here? The most recently active one; name an agent to prefer it
// (the one running in the terminal the person is using — "codex" from a process name).
let preferred = Agents.adapter(forProcess: "codex")?.name
if let hit = Agents.resolve(candidates: [root], preferring: preferred) {
    let agent = hit.adapter, root = hit.root
    print(agent.name)   // e.g. Claude Code

    // The activity timeline, oldest first (the most recent 2,000 events).
    for event in agent.events(for: root) {
        print("\(event.timestamp)  \(event.title): \(event.detail)")
        // event.kind: .userPrompt / .assistantText / .toolUse / .fileEdit
        // event.filePath: navigable absolute path, when the event touched one
    }

    // Token/cost telemetry — nil when the transcript has no usage records.
    if let usage = agent.usage(for: root) {
        print("context \(usage.contextPercent)%  ·  $\(usage.costUSD)  ·  \(usage.outputTokens) out")
    }

    // The edited-files roll-up.
    if let summary = agent.summary(for: root) {
        print("edited \(summary.editedFiles.count) files")
    }

    // Per turn: what it edited and what it cost.
    let events = agent.events(for: root)
    for turn in TurnBoundary.turns(in: events) {
        let effort = turn.effort(in: events)
        print(turn.prompt, turn.editedFiles(in: events).count, effort.toolCalls, effort.modelLabel ?? "-", effort.costLabel ?? "-")
    }
}
```

### AgentStatus

```swift
import AgentStatus

let fg = ForegroundInfo(isBusy: true, process: "node", processPath: "/usr/local/bin/node",
                        processArgs: "node /usr/local/lib/node_modules/@openai/codex/bin/codex.js")
TerminalStatus.derive(foreground: fg, unseenCompletion: false, attention: nil)   // .agent
AgentProcess.commandName(fromArgs: fg.processArgs)                                // "codex"

ScreenStateClassifier.classify(["Run `npm test`? [y/N]"])                          // .waitingForInput

[TerminalStatus.idle, .agent, .waiting].sorted { $0.priority < $1.priority }       // waiting first

// What the build said, out of the terminal's rows (oldest first): one diagnostic per location, the latest wins.
let rows = screenRows.map(BuildDiagnostic.stripANSI)
for d in BuildDiagnostic.parseAll(rows) {
    print(d.path, d.line, d.column ?? 0, d.severity, d.message)   // "Main.swift", 42, 17, .error, "cannot find 'foo' in scope"
}
```

Each module's full guide is `Docs/Modules/<Module>.md`.

## Notes

The modules were separate packages until 27 September 2026 (`swift-agent-session`, `swift-agent-status`); their commits are kept here, so `git log --follow` traces any file back through them.

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT — see [LICENSE](LICENSE).
