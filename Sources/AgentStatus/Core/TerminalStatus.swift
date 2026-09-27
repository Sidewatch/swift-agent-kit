//
//  TerminalStatus.swift
//  AgentStatus
//
//  Derived from signals Sidewatch already has locally — the pty's foreground process group and
//  its name — rather than from anything the agent tells us.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What a terminal is doing, derived from signals the host already has locally — the pty's foreground process group and
/// its name — rather than from anything the agent tells us. That is the point: it works for any
/// agent CLI, and for a plain shell running a build, without integration on the other side.
public enum TerminalStatus: Equatable, Sendable {

    /// Sitting at the prompt with nothing running.
    case idle
    /// A recognised agent CLI is in the foreground.
    case agent
    /// Some other program is in the foreground — a build, a test run, an editor.
    case running
    /// The agent is blocked on you — a permission prompt, or a question.
    ///
    /// The one state that cannot be inferred from the process table: an agent waiting for input
    /// looks exactly like an agent thinking, because both have the same foreground process. It
    /// comes from the SCREEN — ``ScreenStateClassifier`` reading the bottom rows the agent drew
    /// (a numbered choice, a y/n, a known ask phrase) — handed in as ``TerminalAttention/waiting``.
    /// Nothing is installed for it, so no path or tool name can go stale.
    case waiting
    /// An agent finished here and nobody has looked at this terminal since.
    ///
    /// Derived from the terminal's own transition: an agent held the foreground, then the shell
    /// was back at the prompt while the user was elsewhere. The host latches the edge and reports
    /// it once the prompt returns, so an agent handing off to a build tool is still one run. The
    /// limit: Claude Code stays resident between turns, so this fires when the agent EXITS, not
    /// when a turn ends — turn ends are the transcript's business, not the process table's.
    case finished

    /// Process names treated as agents. Matched case-insensitively against the pty's foreground
    /// process name, and by prefix up to a word boundary so versioned or suffixed binaries
    /// (`claude-code`, `codex-cli`, `claude2`) still count while `amplify` and `ampl` — programs
    /// that merely START with "amp" — do not.
    ///
    /// A deliberate whitelist: guessing from the process name alone would catch `node` and
    /// `python`, which run half the tools on a developer's machine, and a terminal wrongly
    /// showing "agent working" is worse than one showing the honest "running".
    public static let agentProcessNames = [
        "claude", "codex", "aider", "goose", "gemini", "copilot", "amp", "opencode", "cursor",
        "hermes", "grok", "crush", "antigravity",
    ]

    /// Agents whose name is an ordinary English stem, matched by equality only at every tier.
    /// The word-boundary prefix rule already declines `pip` or `origin`; equality also declines
    /// `pi2`, `ori-2`, `droid.old`, which a short stem cannot afford and these tools never need.
    /// Amazon Q's `q` is deliberately absent: `q` is also a CSV/JSON query tool, and this list
    /// decides whether a pane claims an agent, asks before closing, and notifies. Add it only
    /// with a way to tell the two apart.
    public static let exactAgentProcessNames: Set<String> = ["pi", "ori", "droid"]

    /// Runtimes that tell you nothing on their own. An agent installed from npm or pip runs as
    /// one of these, so its identity is only in its ARGUMENTS — and reading those is worth it
    /// only here, never for a process that already named itself.
    public static let genericRuntimes: Set<String> = [
        "node", "node22", "node20", "bun", "deno", "python", "python3", "ruby", "perl", "sh", "env",
    ]

    /// Published package/binary names for the same agents, for the ARGUMENTS tier.
    ///
    /// Listed explicitly rather than derived by splitting on hyphens. Deriving would match any
    /// token merely starting with an agent's name, so a project called `claude-notes` would read
    /// as a running agent — the precise false positive the whitelist exists to prevent. The npm
    /// package really is `@anthropic-ai/claude-code`, so "claude" alone never appears as a token.
    public static let agentPackageNames = [
        "claude-code", "codex-cli", "aider-chat", "gemini-cli", "amp-cli", "opencode-ai", "goose-ai",
    ]

    /// `name` is `agent`, or `agent` followed by something that is not a letter (`claude-code`,
    /// `codex-cli`, `claude2`). Must not be a bare `hasPrefix`: `amplify` (AWS) and `ampl` would
    /// read as the agent `amp`.
    static func hasAgentPrefix(_ name: String, _ agent: String) -> Bool {
        guard name.hasPrefix(agent) else { return false }
        guard let next = name.dropFirst(agent.count).first else { return true }
        return !next.isLetter
    }

    /// Whether `name` is one of ``genericRuntimes``, so only its arguments can identify it.
    public static func isGenericRuntime(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return genericRuntimes.contains(name)
    }

    /// Whether the foreground program is an agent, by name, executable path, or arguments —
    /// three tiers because agents install three ways:
    ///   - `/usr/local/bin/codex`             → the NAME says it
    ///   - `.../claude/versions/2.1.223`      → only the PATH says it (the binary is a version)
    ///   - `node .../@openai/codex/cli.js`    → only the ARGUMENTS say it
    public static func isAgentProcess(_ name: String?, path: String? = nil, args: String? = nil) -> Bool {
        agentName(name, path: path, args: args) != nil
    }

    /// WHICH agent the foreground program is — its canonical name from ``agentProcessNames`` /
    /// ``exactAgentProcessNames`` (`"codex"`, `"claude"`, `"pi"`) — by the same three tiers as
    /// ``isAgentProcess(_:path:args:)``; nil when it is not one. A package name maps to its
    /// agent (`@openai/codex-cli` → `codex`).
    public static func agentName(_ name: String?, path: String? = nil, args: String? = nil) -> String? {
        if let name = name?.lowercased(), !name.isEmpty {
            if exactAgentProcessNames.contains(name) { return name }
            if let agent = agentProcessNames.first(where: { hasAgentPrefix(name, $0) }) { return agent }
        }
        if let args = args?.lowercased(), !args.isEmpty {
            // Split on separators so `@openai/codex/cli.js` yields "codex" as its own token, and a
            // path merely CONTAINING the word does not. Whole tokens, so the exact names belong
            // here too — without them an agent installed under a runtime (`node …/pi/cli.js`) is
            // invisible to every tier.
            let tokens = Set(args.split(whereSeparator: { "/\\ \t@".contains($0) }).map(String.init))
            if let agent = agentProcessNames.first(where: tokens.contains) { return agent }
            if let package = agentPackageNames.first(where: tokens.contains) { return packageAgents[package] }
            if let agent = exactAgentProcessNames.sorted().first(where: tokens.contains) { return agent }
        }
        guard let path = path?.lowercased(), !path.isEmpty else { return nil }
        // EXACT component match. A prefix rule would fire on any directory merely starting with
        // an agent's name — a project called `claude-notes` would make every shell inside it look
        // like a running agent, which is the false positive the whitelist exists to prevent.
        // Versioned or suffixed BINARIES are already covered by the name check above.
        let components = Set(path.split(separator: "/").map(String.init))
        return agentProcessNames.first(where: components.contains) ?? exactAgentProcessNames.sorted().first(where: components.contains)
    }

    /// Which agent each of ``agentPackageNames`` installs.
    static let packageAgents: [String: String] = [
        "claude-code": "claude", "codex-cli": "codex", "aider-chat": "aider", "gemini-cli": "gemini",
        "amp-cli": "amp", "opencode-ai": "opencode", "goose-ai": "goose",
    ]

    /// The whole rule, in one place, so a test calls the REAL derivation rather than a copy.
    /// Precedence: an unacknowledged attention signal outranks everything (a waiting agent is
    /// still busy in the process table); then busy outranks the completion flag, since a
    /// terminal that has started new work is working. No parameter has a default: omitting one
    /// would silently degrade the answer with nothing for the compiler to catch.
    public static func derive(foreground fg: ForegroundInfo, unseenCompletion: Bool,
                       attention: TerminalAttention?) -> TerminalStatus {
        if attention == .waiting { return .waiting }
        if fg.isBusy { return isAgentProcess(fg.process, path: fg.processPath, args: fg.processArgs) ? .agent : .running }
        return unseenCompletion ? .finished : .idle
    }

    /// A state the user may need to act on — the only states that earn a badge on the tab.
    /// A working agent announces itself in its own title; a badge beside it said the same
    /// thing twice.
    public var isActionable: Bool { self == .waiting || self == .finished }

    /// Whether an agent is (or was) the foreground process — the terminals whose cwd is where
    /// that agent's transcript lives.
    public var impliesAgent: Bool { self == .agent || self == .waiting || self == .finished }

    /// SF Symbol for the status dot.
    public var symbolName: String {
        switch self {
        case .idle:     return "circle"
        case .agent:    return "circle.fill"
        case .running:  return "circle.dotted"
        case .finished: return "checkmark.circle.fill"
        case .waiting:  return "exclamationmark.circle.fill"
        }
    }

    /// Short label shown beside the terminal's name.
    public var label: String {
        switch self {
        case .idle:     return String(localized: "Idle", bundle: .module, comment: "Terminal status label: nothing is running")
        case .agent:    return String(localized: "Working", bundle: .module, comment: "Terminal status label: an agent is working")
        case .running:  return String(localized: "Running", bundle: .module, comment: "Terminal status label: a command is running")
        case .finished: return String(localized: "Done", bundle: .module, comment: "Terminal status label: the agent has finished")
        case .waiting:  return String(localized: "Needs you", bundle: .module, comment: "Terminal status label: the agent is waiting for the person's answer")
        }
    }

    /// Sort rank: what needs you first. Finished agents outrank working ones because a finished
    /// agent is BLOCKED on you and a working one is not.
    public var priority: Int {
        switch self {
        // Waiting outranks finished: both want you, but a waiting agent is STALLED — nothing
        // moves until you answer — while a finished one has at least delivered its work.
        case .waiting:  return 0
        case .finished: return 1
        case .agent:    return 2
        case .running:  return 3
        case .idle:     return 4
        }
    }
}
