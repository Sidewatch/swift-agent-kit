//
//  AgentRunEdge.swift
//  AgentStatus
//
//  The edges of an agent's run in a terminal: a fresh run, the agent leaving, the end of the run.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The run-level state machine a terminal keeps for the agent in its foreground, stepped once per
/// reading of the foreground process. It finds three edges and says what each asks of the terminal:
///
/// - **A fresh run**: an agent identity (process, path and arguments) the previous reading did not
///   have — including one agent replacing another inside a single poll. Whatever the previous run still
///   owed is history, and so is what it reported about itself.
/// - **The agent leaving the foreground**: a question dies with the process that asked it, so the
///   verdict clears now; the run's END is latched, because an agent handing off to a build tool is still
///   work in flight.
/// - **Back at the prompt with that end latched**: the run is Done, unseen until the person looks.
///
/// A run whose own reports already said Done (``noteFinishedTold()``) is not announced a second time
/// when the agent then exits; the Done badge still stays until the person looks. Any command finishing
/// also asks for its output to be read once, while it is complete and still on screen.
public struct AgentRunEdge: Sendable, Equatable {
    /// One reading of the terminal's foreground.
    public struct Reading: Sendable, Equatable {
        /// Whether a program other than the shell holds the foreground.
        public let isBusy: Bool
        /// The foreground agent's identity (process, path and arguments), nil when no agent holds it —
        /// always nil when the shell itself is in front.
        public let agentKey: String?

        /// A reading; an agent key given for an idle foreground is dropped (the shell is in front).
        public init(isBusy: Bool, agentKey: String?) {
            self.isBusy = isBusy
            self.agentKey = isBusy ? agentKey : nil
        }
    }

    /// What a step asks of the terminal, applied in this order.
    public struct Effects: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// Drop what the previous program reported about itself.
        public static let forgetReports = Effects(rawValue: 1 << 0)
        /// Clear the "needs you" / Done verdict.
        public static let clearAttention = Effects(rawValue: 1 << 1)
        /// A command just finished: read its output (build diagnostics) now.
        public static let readDiagnostics = Effects(rawValue: 1 << 2)
        /// Tell the person the run finished.
        public static let notifyFinished = Effects(rawValue: 1 << 3)
    }

    /// The previous reading's agent identity, nil when no agent held the foreground.
    public private(set) var agentKey: String?
    /// The run's end, latched from the agent leaving until the shell is back at the prompt.
    public private(set) var completionPending = false
    /// A run finished here and the person has not looked since.
    public private(set) var unseenCompletion = false
    /// The current run's end was already told, by its own reports.
    public private(set) var finishedTold = false

    /// A terminal with no agent seen yet.
    public init() {}

    /// Steps from `previous` to `next`. `userAtTerminal`: the person is at this terminal, so nothing
    /// accrues as unseen.
    public mutating func step(from previous: Reading, to next: Reading, userAtTerminal: Bool) -> Effects {
        var effects: Effects = []
        let key = next.agentKey
        if let key, key != agentKey {
            completionPending = false
            finishedTold = false
            if agentKey != nil { effects.insert(.forgetReports) }
        }
        if agentKey != nil, key == nil {
            completionPending = true
            effects.formUnion([.clearAttention, .forgetReports])
        }
        if previous.isBusy, !next.isBusy { effects.insert(.readDiagnostics) }
        if completionPending, !next.isBusy {
            completionPending = false
            unseenCompletion = true
            if !finishedTold { effects.insert(.notifyFinished) }
            finishedTold = false
        }
        if userAtTerminal {
            unseenCompletion = false
            effects.insert(.clearAttention)
        }
        agentKey = key
        return effects
    }

    /// The run's own reports said Done and the person was told: its exit is not announced again.
    public mutating func noteFinishedTold() { finishedTold = true }

    /// The reports went live again — a new turn in the same agent — whose end is not told yet.
    public mutating func noteRunLive() { finishedTold = false }

    /// The person looked: nothing is unseen.
    public mutating func acknowledge() { unseenCompletion = false }
}
