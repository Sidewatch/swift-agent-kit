//
//  HookActivity.swift
//  AgentStatus
//
//  What an agent's hook events say it is doing, as a status report.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What an agent's hook events say it is doing, held as the one ``ProgramStatusReport`` a host
/// merges with the terminal's own (``ReportedActivity``). A prompt submitted is `working`, a
/// stop is `done`, a permission or question notice is `blocked`.
///
/// Hooks tell the moments exactly but not every moment: a turn the person interrupts sends no
/// stop, and no event says a permission prompt was answered. So a report that says the agent is
/// busy or waiting is dropped the moment the person types in that terminal, and the screen
/// decides again as it does for an agent with no hooks; the next event is believed as before.
/// A report can therefore be missing, never stuck.
public struct HookActivity: Equatable, Sendable {
    /// The id of the record hooks hold among a terminal's reports.
    public static let reportID = "hooks"

    /// The report in force, nil when hooks say nothing just now.
    public private(set) var report: ProgramStatusReport?
    /// The session the last event named, with its transcript.
    public private(set) var sessionID: String?
    /// That session's transcript, when the agent named it.
    public private(set) var transcriptPath: String?
    /// The last prompt submitted in that session.
    public private(set) var prompt: String?

    /// Nothing heard yet.
    public init() {}

    /// Takes one event in.
    public mutating func note(_ event: AgentHookEvent) {
        if event.sessionID != sessionID { prompt = nil }
        sessionID = event.sessionID
        transcriptPath = event.transcriptPath ?? transcriptPath
        switch event.kind {
        case .sessionStarted:
            report = nil
        case .promptSubmitted(let text):
            prompt = text.isEmpty ? prompt : text
            report = ProgramStatusReport(id: Self.reportID, state: .working)
        case .stopped:
            report = ProgramStatusReport(id: Self.reportID, state: .done)
        case .needsYou(let kind, let message):
            report = ProgramStatusReport(id: Self.reportID, state: .blocked, kind: kind, message: message)
        case .sessionEnded:
            self = HookActivity()
        }
    }

    /// The person typed in the terminal: whatever they answered or interrupted, hooks will not say,
    /// so a busy or waiting report is no longer known to be true. A finished one still is.
    public mutating func personTyped() {
        if report?.state == .working || report?.state == .blocked { report = nil }
    }

    /// The agent left the terminal: nothing it said holds.
    public mutating func agentLeft() { self = HookActivity() }
}
