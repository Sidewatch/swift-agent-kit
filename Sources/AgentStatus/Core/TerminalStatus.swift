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

/// Derived from signals Sidewatch already has locally — the pty's foreground process group and
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
    /// that merely START with "amp" — do not (18 Sep 2026).
    ///
    /// A deliberate whitelist: guessing from the process name alone would catch `node` and
    /// `python`, which run half the tools on a developer's machine, and a terminal wrongly
    /// showing "agent working" is worse than one showing the honest "running".
    public static let agentProcessNames = [
        "claude", "codex", "aider", "goose", "gemini", "copilot", "amp", "opencode", "cursor",
        "hermes", "grok", "crush", "antigravity",
    ]

    /// Agents whose name is an ordinary English stem, matched by equality only at every tier.
    ///
    /// Note what this does and does not buy, because the original comment here was stale: since
    /// the word-boundary rule of 18 Sep 2026, prefix matching ALREADY declines `pip`, `ping`,
    /// `pigz`, `origin` and `droidcam`, because the character after the stem is a letter. What
    /// equality adds is the rest — `pi2`, `ori-2`, `droid.old` — where a non-letter follows and
    /// the prefix rule would say yes. For a two- or three-letter stem that is a real risk and
    /// the agent gains nothing from the looseness, since these tools ship under their bare name.
    ///
    /// Amazon Q's `q` is deliberately NOT here. A single letter is a name other tools use — `q`
    /// is also a well-known CSV/JSON query tool — and this list decides whether a pane says an
    /// agent is running, whether closing it asks first, and whether a notification fires. A
    /// windshield may show nothing; it may not show something untrue. Add it only with a way to
    /// tell the two apart.
    public static let exactAgentProcessNames: Set<String> = ["pi", "ori", "droid"]

    /// Whether the foreground program is an agent, by name OR by executable path.
    ///
    /// The path matters more than the name, which is the opposite of what you would expect.
    /// Claude Code's native installer runs `~/.local/share/claude/versions/2.1.223` — the
    /// executable IS the version number, so `proc_name` reports "2.1.223" and no list of program
    /// names can ever match it. The directory it lives in is the part that identifies it.
    ///
    /// Checking path COMPONENTS rather than a substring, so a project that happens to be called
    /// `claude-notes` does not make every shell in it look like an agent.
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
    /// `codex-cli`, `claude2`). A bare `hasPrefix` made `amplify` (AWS) and `ampl` read as the
    /// agent `amp`, and a terminal running either showed "Working".
    static func hasAgentPrefix(_ name: String, _ agent: String) -> Bool {
        guard name.hasPrefix(agent) else { return false }
        guard let next = name.dropFirst(agent.count).first else { return true }
        return !next.isLetter
    }

    public static func isGenericRuntime(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return genericRuntimes.contains(name)
    }

    /// Whether the foreground program is an agent, by name, executable path, or arguments.
    ///
    /// Three tiers because agents install three ways:
    ///   - `/usr/local/bin/codex`             → the NAME says it
    ///   - `.../claude/versions/2.1.223`      → only the PATH says it (the binary is a version)
    ///   - `node .../@openai/codex/cli.js`    → only the ARGUMENTS say it
    ///
    /// Without all three, whichever way you happened to install decides whether Sidewatch can
    /// see your agent, which is not a distinction a user would ever guess at.
    public static func isAgentProcess(_ name: String?, path: String? = nil, args: String? = nil) -> Bool {
        if let name = name?.lowercased(), !name.isEmpty,
           exactAgentProcessNames.contains(name)
            || agentProcessNames.contains(where: { hasAgentPrefix(name, $0) }) { return true }
        if let args = args?.lowercased(), !args.isEmpty {
            // Split on separators so `@openai/codex/cli.js` yields "codex" as its own token, and a
            // path merely CONTAINING the word does not.
            let tokens = Set(args.split(whereSeparator: { "/\\ \t@".contains($0) }).map(String.init))
            // `exactAgentProcessNames` belongs here too: these are whole tokens already, so
            // there is no prefix to be loose about, and without them an agent installed under a
            // runtime (`node …/pi/cli.js`) was invisible to every tier — the exact gap the three
            // tiers exist to close.
            if (agentProcessNames + agentPackageNames).contains(where: { tokens.contains($0) })
                || exactAgentProcessNames.contains(where: { tokens.contains($0) }) { return true }
        }
        guard let path = path?.lowercased(), !path.isEmpty else { return false }
        // EXACT component match. A prefix rule would fire on any directory merely starting with
        // an agent's name — a project called `claude-notes` would make every shell inside it look
        // like a running agent, which is the false positive the whitelist exists to prevent.
        // Versioned or suffixed BINARIES are already covered by the name check above.
        let components = Set(path.split(separator: "/").map(String.init))
        return agentProcessNames.contains { components.contains($0) }
            || exactAgentProcessNames.contains { components.contains($0) }
    }

    /// The whole rule, in one place.
    ///
    /// A free function rather than a computed property on `TerminalController` so the test can
    /// call the REAL derivation instead of a copy of it. A probe that restates the rule agrees
    /// with itself no matter what the app does, which is how a wrong rule survives a green test.
    ///
    /// Precedence, top down: an unacknowledged attention signal outranks EVERYTHING — a waiting
    /// agent is still "busy" in the process table, so the screen's verdict must outrank busy or
    /// it could never show. Below that, busy outranks the transition-derived completion flag: a
    /// terminal that has started new work is working, whatever it finished a moment ago.
    ///
    /// No parameter has a default. Three of these used to default to nil, and omitting one
    /// silently degraded the answer — forget `attention:` and a waiting agent reports `.agent` —
    /// with nothing for the compiler to catch. See ``ForegroundInfo``.
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
        case .idle:     return "Idle"
        case .agent:    return "Working"
        case .running:  return "Running"
        case .finished: return "Done"
        case .waiting:  return "Needs you"
        }
    }

    /// Sort rank: what needs you first. Finished agents outrank working ones because a finished
    /// agent is BLOCKED on you and a working one is not — the rail's whole job is to surface
    /// which terminal is waiting.
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

/// The pty's foreground process, as ONE value for ``TerminalStatus/derive(foreground:unseenCompletion:attention:)``.
///
