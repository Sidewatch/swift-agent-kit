//
//  TranscriptParsing.swift
//  AgentSession
//
//  A line-at-a-time reader of one agent's transcript format.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A line-at-a-time reader of one agent's transcript format. ``TranscriptCache`` folds each
/// appended line into one and serves its three results, so every agent's adapter polls in
/// O(appended bytes) with results equal to a full re-parse.
protocol TranscriptParsing {
    /// An empty state, before any line.
    init()
    /// Folds one complete line into the state; a line that is not this format is skipped.
    mutating func ingest(lineData: Data)
    /// Token and cost telemetry, or nil when the transcript carries none.
    var usageResult: AgentUsage? { get }
    /// The activity timeline, oldest first.
    var eventsResult: [TimelineEvent] { get }
    /// The edited-files roll-up.
    var summaryResult: AgentSummary { get }
}
