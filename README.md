# Swift Agent Kit

Terminal AI coding agents, read from the outside: what a terminal's agent is doing right now, and what its session did — for Claude Code, Codex, Gemini and Grok. Read-only; it never talks to a model.

## Modules

Each module is its own library product: depend on the package, then only on the products you use.

| Module | What it is |
|---|---|
| [`AgentSession`](Docs/Modules/AgentSession.md) | Reads coding agents' session transcripts (Claude Code, Codex, Gemini, Grok) into one timeline, usage and edited-files model. |
| [`AgentStatus`](Docs/Modules/AgentStatus.md) | What a terminal is doing — idle, running something, running an agent, waiting on you, finished — from its foreground process and screen. |

## Installation

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

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

## History

The modules were separate packages until 27 September 2026 (`swift-agent-session`, `swift-agent-status`); their commits are kept here, so `git log --follow` traces any file back through them.

## Licence

MIT — see [LICENSE](LICENSE).
