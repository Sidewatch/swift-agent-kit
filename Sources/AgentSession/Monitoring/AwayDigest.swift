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
    }

    /// How long the person must have been away for a summary: shorter absences need none.
    public static let minimumAway: TimeInterval = 180
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

    /// The summary for an absence of `away` seconds; nil when the person was away briefly or the agent
    /// edited nothing and ran nothing. It carries no money: Sidewatch prints no prices.
    public func summary(away: TimeInterval) -> Summary? {
        guard away >= Self.minimumAway, !editedFiles.isEmpty || toolRuns > 0 else { return nil }
        return Summary(filesEdited: editedFiles.count, toolRuns: toolRuns)
    }
}
