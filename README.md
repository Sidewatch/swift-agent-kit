# Swift Agent Session

A tiny, dependency-free reader for terminal AI coding-agent session transcripts. It maps an agent's on-disk session onto one agent-agnostic model — an activity timeline, token/cost telemetry, and an edited-files/to-dos roll-up — so review surfaces stay identical across agents. Read-only: it never talks to a model, keeps no account, and sends no telemetry.

## Features

- 🧭 **Agent-agnostic model** — `TimelineEvent`, `AgentUsage`, `AgentSummary`
- 🔌 **Adapter protocol** — implement `AgentAdapter` once per agent
- 📐 **Turn boundaries** — `TurnBoundary` splits the flat timeline into agent turns (one user prompt to just before the next), with a content-derived stable id so a checkpoint can be pinned to a turn
- 🤖 **Claude Code adapter** — `ClaudeCodeAdapter` parses `~/.claude/projects/…/*.jsonl` transcripts. **The only adapter shipped**, deliberately: an adapter tested only against fixtures written by hand from a tool's published schema reports "no session" forever without telling anyone when the format drifts. Add one only with fixtures captured from a REAL run.
- 🕘 **Activity timeline** — prompts, assistant prose, tool calls, and file edits, with local-clock `HH:MM` timestamps
- 💰 **Telemetry** — context fill % (`AgentUsage.contextPercent`), output tokens, and estimated USD cost, deduplicated per API response
- ✅ **Edited files** — the files a session wrote (Edit / Write / MultiEdit / NotebookEdit).
- 🔎 **Auto-detection** — `Agents.active(for:)` picks the agent that owns a project
- 🧪 **Fully tested** — synthetic-transcript tests including malformed, truncated, and garbage input
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- macOS 14+ (Foundation only; other Apple platforms at SwiftPM's default minimums)
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-agent-session.git", from: "0.1.0")
]
```

## Usage

```swift
import AgentSession

let root = URL(fileURLWithPath: "/path/to/project")

// Which agent has a session here? First match in Agents.all wins.
if let agent = Agents.active(for: root) {
    print(agent.name)   // e.g. Claude Code

    // The activity timeline, oldest first (most recent 300 events).
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

### Adding an agent

```swift
// Implement the protocol against the agent's native transcript format…
struct MyAgentAdapter: AgentAdapter {
    var name: String { "My Agent" }
    func hasSession(for root: URL) -> Bool { /* … */ }
    func events(for root: URL) -> [TimelineEvent] { /* … */ }
    func usage(for root: URL) -> AgentUsage? { /* … */ }
    func summary(for root: URL) -> AgentSummary? { /* … */ }
}
// …and append it to Agents.all — every consumer stays agent-agnostic.
```

## Notes

- All calls are **synchronous** file reads over the newest transcript. When sessions may be large, dispatch them off the main queue.
- Only the **latest session** (most recently modified `.jsonl`) per project is read.
- Costs are **estimates** at Anthropic's published API list prices per model generation (`ModelPricing` cites the page): Fable 5.1 and 5, Opus 4.5 and later against 4.1 and earlier, Sonnet 5 against 4.x, Haiku 4.5 against 3.5, at the 5-minute cache-write tier with no discounts. A subscription plan is not billed per token, so the figure is what the same tokens would cost at list. Repeated JSONL lines for the same API response are counted once.
- `ClaudeKeychain` reads Claude Code's OAuth item through Apple's `security` tool first — the item's partition list is `apple-tool:`, so that read is silent and fresh on every call, where a Security-framework read from a GitHub-signed app prompts for the login password and "Always Allow" is forgotten at the next token refresh — and falls back to the framework.
- `ClaudeQuota` reads both shapes of `/api/oauth/usage`: the `limits` array (where a per-model weekly cap such as Fable's lives, with the top-level `seven_day_<model>` keys null) and the older top-level windows. `spend` (or the older `extra_usage`) becomes `ClaudeQuota.Spend`, money in the account's own currency, and `seven_day_breakdown` becomes `weekShares`.
- The parser is defensive: malformed, truncated, or garbage lines are skipped, never fatal.

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT
