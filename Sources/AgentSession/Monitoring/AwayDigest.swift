//
//  AwayDigest.swift
//  AgentSession
//
//  What an agent did while the person was away, and whether it is worth telling them.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The agent's activity while the person was away from the app: distinct files edited and other tool
/// runs, gathered from fresh transcript events, and the rule for when a "while you were away" summary
/// is worth showing.
public struct AwayDigest: Sendable, Equatable {
    /// A summary to show.
    public struct Summary: Sendable, Equatable {
        /// Distinct files the agent edited.
        public let filesEdited: Int
        /// Tool runs that were not file edits.
        public let toolRuns: Int
        /// What the session cost over the gap, when a cost worth showing is known (see ``showsCost(_:)``).
        public let cost: Double?
    }

    /// How long the person must have been away for a summary: shorter absences need none.
    public static let minimumAway: TimeInterval = 180
    /// The smallest cost worth showing: under half a cent rounds to nothing.
    public static let minimumCost = 0.005

    /// Distinct files edited so far in the gap.
    public private(set) var editedFiles = Set<String>()
    /// Non-edit tool runs so far in the gap (an edit with no path counts here).
    public private(set) var toolRuns = 0

    /// An empty gap.
    public init() {}

    /// Folds fresh transcript events in.
    public mutating func add(_ events: some Sequence<TimelineEvent>) {
        for event in events {
            switch event.kind {
            case .fileEdit:
                if let path = event.filePath { editedFiles.insert(path) } else { toolRuns += 1 }
            case .toolUse:
                toolRuns += 1
            case .userPrompt, .assistantText:
                break
            }
        }
    }

    /// Whether a cost difference is worth printing.
    public static func showsCost(_ cost: Double?) -> Bool { (cost ?? 0) >= minimumCost }

    /// The summary for an absence of `away` seconds, the session having cost `costBefore` when the person
    /// left and `costNow` now; nil when they were away briefly or nothing worth telling happened.
    public func summary(away: TimeInterval, costBefore: Double?, costNow: Double?) -> Summary? {
        guard away >= Self.minimumAway else { return nil }
        // A cost that went down (a new session) is negative, and so never past the threshold.
        let cost = costBefore.flatMap { before in costNow.map { $0 - before } }
        guard !editedFiles.isEmpty || toolRuns > 0 || Self.showsCost(cost) else { return nil }
        return Summary(filesEdited: editedFiles.count, toolRuns: toolRuns, cost: Self.showsCost(cost) ? cost : nil)
    }
}
