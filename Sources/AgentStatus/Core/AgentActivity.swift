//
//  AgentActivity.swift
//  AgentStatus
//
//  What the agent in a terminal is doing: one verdict, from its own status reports or from the screen.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What the agent in a terminal is doing, as one verdict. ``ReportedActivity`` produces it from
/// the program's own OSC 7501 reports when it sends them, else from the screen
/// (``ScreenStateClassifier``). The screen can only ever say `working` or `needsYou`; the three
/// settled cases come from a report.
public enum AgentActivity: Equatable, Sendable {
    /// Work in flight.
    case working
    /// Stopped until the person acts. `kind` says how when the program said so; nil when the
    /// screen decided.
    case needsYou(kind: ProgramStatusKind?)
    /// At its prompt with nothing in flight.
    case idle
    /// A task completed.
    case finished
    /// A task stopped on an error.
    case failed

    /// Whether the person is needed.
    public var needsYou: Bool {
        if case .needsYou = self { return true }
        return false
    }

    /// Whether a run is live: working, or waiting on the person mid-run.
    public var isActive: Bool { self == .working || needsYou }

    /// Whether the run has ended, however it ended.
    public var isSettled: Bool { !isActive }

    /// Whether a run ended between two verdicts: the earlier one live, the later one settled.
    /// Nil on either side is no verdict, so nothing ended; settled → settled is the same end
    /// seen twice, not a new one.
    public static func runEnded(from earlier: AgentActivity?, to later: AgentActivity?) -> Bool {
        guard let earlier, let later else { return false }
        return earlier.isActive && later.isSettled
    }
}
