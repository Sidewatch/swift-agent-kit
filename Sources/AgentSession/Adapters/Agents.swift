//
//  Agents.swift
//  AgentSession
//
//  The adapter registry and project auto-detection entry point. Add support for
//  an agent by appending its adapter to `all`.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Registry of known agent adapters plus project auto-detection.
///
/// Adding support for a new agent is a one-line change: append its
/// ``AgentAdapter`` to ``all``.
public enum Agents {

    /// Every adapter known to the library. An agent is added only with sanitized transcripts from
    /// REAL runs to test against and its parser checked against the agent's own source — an
    /// adapter written from a published schema alone reports "no session" forever when the
    /// format drifts, and tells no one.
    public static let all: [AgentAdapter] = [
        ClaudeCodeAdapter(),
        CodexAdapter(),
        GeminiAdapter(),
        GrokAdapter(),
    ]

    /// The adapter with this ``AgentAdapter/name``, if the library has one.
    public static func adapter(named name: String) -> AgentAdapter? { all.first { $0.name == name } }

    /// The adapter that reads sessions for a detected agent process (`"codex"`), if any.
    public static func adapter(forProcess process: String?) -> AgentAdapter? {
        guard let process else { return nil }
        return all.first { $0.processNames.contains(process) }
    }

    /// The agent whose session for `root` was active most recently, with that session, or nil
    /// when no known agent has one. Several agents can work in one folder (a terminal each), so
    /// "which one" is the latest to write, not a fixed order.
    public static func active(for root: URL) -> AgentAdapter? {
        active(for: root, in: all)
    }

    /// Test seam: ``active(for:)`` over an explicit adapter list.
    static func active(for root: URL, in adapters: [AgentAdapter]) -> AgentAdapter? {
        adapters.compactMap { adapter in adapter.latestSession(for: root).map { (adapter, $0.modificationDate ?? .distantPast) } }
            .max { $0.1 < $1.1 }?.0
    }

    /// Every file any agent's latest session for `root` edited. Several agents can work in one
    /// folder at once, so "did an agent write this?" asks all of them, not the latest.
    public static func editedFiles(for root: URL) -> Set<String> {
        editedFiles(for: root, in: all)
    }

    /// Test seam: ``editedFiles(for:)`` over an explicit adapter list.
    static func editedFiles(for root: URL, in adapters: [AgentAdapter]) -> Set<String> {
        adapters.reduce(into: Set<String>()) { $0.formUnion($1.summary(for: root)?.editedFiles ?? []) }
    }

    /// The first of `candidates`, in order, that an agent has a session for — with that agent.
    /// Order candidates most specific first: the cwd of a terminal running an agent (an agent
    /// files its session under its OWN cwd at launch), then the opened folder, its repo root,
    /// its parent. `preferring` names the agent to read when it has a session there — the one
    /// running in the terminal the person is using — before falling back to the most recent.
    public static func resolve(candidates: [URL], preferring agent: String? = nil) -> (adapter: AgentAdapter, root: URL)? {
        resolve(candidates: candidates, preferring: agent, in: all)
    }

    /// Test seam for ``resolve(candidates:preferring:)`` over an explicit adapter list.
    static func resolve(candidates: [URL], preferring agent: String? = nil, in adapters: [AgentAdapter]) -> (
        adapter: AgentAdapter, root: URL
    )? {
        for root in candidates {
            if let agent, let preferred = adapters.first(where: { $0.name == agent }), preferred.hasSession(for: root) {
                return (preferred, root)
            }
            if let adapter = active(for: root, in: adapters) { return (adapter, root) }
        }
        return nil
    }
}
