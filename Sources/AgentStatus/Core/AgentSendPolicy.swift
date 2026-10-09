//
//  AgentSendPolicy.swift
//  AgentStatus
//
//  Where text a host did not type may go, and whether it may be submitted.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The one rule for text a host derived from a file or a project — a review comment quoting a
/// diff line, a selection, a project's saved prompt — on its way into a terminal.
///
/// Such text is SUBMITTED (Return pressed after the paste) only into a terminal whose foreground
/// is a live agent, which reads it as a message. Pasted into a shell and submitted, the same text
/// is a command line: a quoted `` `touch marker` `` runs. So the target is the current terminal
/// when it runs a live agent; else the single live agent, when there is exactly one; else the
/// current terminal, pasted and left unsubmitted for the person to read first.
public enum AgentSendPolicy {
    /// One terminal and what it is doing.
    public struct Candidate<ID: Hashable & Sendable>: Equatable, Sendable {
        /// The terminal's identity.
        public let id: ID
        /// Its status, as the host derives it.
        public let status: TerminalStatus

        /// A candidate.
        public init(id: ID, status: TerminalStatus) {
            self.id = id
            self.status = status
        }
    }

    /// Where one send goes.
    public struct Verdict<ID: Hashable & Sendable>: Equatable, Sendable {
        /// The terminal to paste into; nil when there is no terminal at all.
        public let target: ID?
        /// Whether Return follows the paste. False means the text is left for the person to read.
        public let submits: Bool

        /// A verdict.
        public init(target: ID?, submits: Bool) {
            self.target = target
            self.submits = submits
        }
    }

    /// The verdict for a send into `terminals` while `current` is the terminal in front.
    ///
    /// - Parameters:
    ///   - current: The terminal a send defaults to — the focused one, or the one the person chose.
    ///   - terminals: Every live terminal with its status.
    ///   - redirectsToSingleAgent: Whether a send may move from `current` to the only live agent
    ///     when `current` runs none. True for a send with no chosen terminal (a review comment);
    ///     false when the person picked `current` themselves.
    public static func verdict<ID: Hashable & Sendable>(
        current: ID?, terminals: [Candidate<ID>], redirectsToSingleAgent: Bool = true
    ) -> Verdict<ID> {
        let live = terminals.filter { $0.status.isLiveAgent }.map(\.id)
        if let current, live.contains(current) { return Verdict(target: current, submits: true) }
        if redirectsToSingleAgent, live.count == 1 { return Verdict(target: live[0], submits: true) }
        return Verdict(target: current ?? terminals.first?.id, submits: false)
    }
}
