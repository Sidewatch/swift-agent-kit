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

    /// Whether this agent has a recorded session for the given project root.
    func hasSession(for root: URL) -> Bool

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
