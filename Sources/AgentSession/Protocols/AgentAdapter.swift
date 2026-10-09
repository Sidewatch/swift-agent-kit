//
//  AgentAdapter.swift
//  AgentSession
//
//  The read-only bridge between a CLI coding agent's on-disk session transcript
//  and the agent-agnostic model. Implement one per agent.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A CLI coding agent whose on-disk session transcript can be read (read-only).
///
/// Implement one adapter per agent to map its native session format onto the
/// shared ``TimelineEvent`` / ``AgentUsage`` / ``AgentSummary`` model; every
/// other consumer then stays agent-agnostic.
///
/// - Note: Adapters read transcripts synchronously from disk — call off the main
///   thread when sessions may be large.
public protocol AgentAdapter: Sendable {

    /// A human-readable name for the agent, e.g. `"Claude Code"`.
    var name: String { get }

    /// The agent's process names as terminal detection reports them (`TerminalStatus.agentName`
    /// in AgentStatus: `"claude"`, `"codex"`), so a terminal running the agent reads its
    /// sessions.
    var processNames: Set<String> { get }

    /// The agent's live session for `root` — a transcript file, or a folder for an agent that
    /// stores a session as one — or nil when it has none. Its modification date is how the most
    /// recently active of several agents is chosen. The answer is stable across polls: with two
    /// sessions in one folder, the one being written is kept until it goes quiet, so a host can
    /// key per-session state by this path.
    func latestSession(for root: URL) -> URL?

    /// The folder of the agent's newest session launched in a SUBFOLDER of `project` (an agent
    /// started in a worktree or a package of the opened project), or nil when there is none or
    /// the agent cannot tell. The session itself is then ``latestSession(for:)`` of that folder.
    func latestSessionRoot(under project: URL) -> URL?

    /// The activity timeline for `root`, oldest first.
    func events(for root: URL) -> [TimelineEvent]

    /// The activity timeline parsed from one session on disk, wherever it lives — the parsing
    /// half of an adapter without the locating half, so it can be tested against a checked-in
    /// fixture. `url` is a transcript file or, for an agent that stores a session as a folder,
    /// a directory; the adapter decides. Oldest first; empty when the session is absent or not
    /// in this agent's format.
    func events(fromSession url: URL) -> [TimelineEvent]

    /// Token/cost telemetry for `root`, or `nil` when unavailable.
    func usage(for root: URL) -> AgentUsage?

    /// The edited-files roll-up for `root`, or `nil` when unavailable.
    func summary(for root: URL) -> AgentSummary?
}

public extension AgentAdapter {
    /// Whether this agent has a recorded session for `root`.
    func hasSession(for root: URL) -> Bool { latestSession(for: root) != nil }

    /// Nil: an adapter that files sessions only by exact folder cannot look beneath one.
    func latestSessionRoot(under project: URL) -> URL? { nil }
}
