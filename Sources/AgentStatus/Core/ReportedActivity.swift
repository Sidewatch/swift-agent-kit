//
//  ReportedActivity.swift
//  AgentStatus
//
//  The program's own account of itself (OSC 7501 records) merged with the screen into one verdict.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The program's own account of itself — its Program Status Protocol (OSC 7501) records — merged
/// with what the screen shows, into one ``AgentActivity``.
///
/// The rule: **a program that speaks the protocol is believed; one that does not is read off the
/// screen.** While any report is held, the reports decide and the screen is not consulted — a
/// program that reports `working` while a dialog is still on screen is working. With no report,
/// ``ScreenStateClassifier``'s verdict stands as before.
///
/// Across several records (a root and its children, `build`, `build/tests`) **the most urgent
/// decides**: blocked, then working, then error, done, idle. A blocked child blocks the whole
/// program and a working child is work in flight whatever the root says; among equals the root
/// wins, then the most recently updated. The alternative — the root alone — would hide a child
/// asking for permission.
///
/// Lifetime follows the protocol: a new shell prompt or the program's exit ends working and
/// blocked records (``promptStarted()``); idle, done and error are results and survive until the
/// program replaces them or the host ``reset()``s — which a host does when another program takes
/// the terminal, since a predecessor's results say nothing about it.
public struct ReportedActivity: Equatable, Sendable {
    /// The records held, oldest update first (the order the terminal keeps them in).
    public private(set) var reports: [ProgramStatusReport]

    public init(reports: [ProgramStatusReport] = []) { self.reports = reports }

    /// Replaces the records with the terminal's current set.
    public mutating func update(_ reports: [ProgramStatusReport]) { self.reports = reports }

    /// A new shell prompt, or the program exited: working and blocked records are stale and go;
    /// idle, done and error are results and stay.
    public mutating func promptStarted() {
        reports.removeAll { $0.state == .working || $0.state == .blocked }
    }

    /// Another program took the terminal: nothing its predecessor reported applies to it.
    public mutating func reset() { reports = [] }

    /// Whether any report is held — then the reports decide, not the screen.
    public var hasReports: Bool { !reports.isEmpty }

    /// The record that decides when several are held: the most urgent state; among equals the
    /// root, then the most recently updated. Nil when none is held.
    public var decidingReport: ProgramStatusReport? {
        reports.enumerated().max { Self.rank($0.element, at: $0.offset) < Self.rank($1.element, at: $1.offset) }?.element
    }

    /// The verdict: the deciding report's, else the screen's; nil when neither says anything.
    public func activity(screen: ScreenState?) -> AgentActivity? {
        if let report = decidingReport { return Self.activity(of: report) }
        return Self.activity(ofScreen: screen)
    }

    /// What one report says on its own.
    public static func activity(of report: ProgramStatusReport) -> AgentActivity {
        switch report.state {
        case .working: return .working
        case .blocked: return .needsYou(kind: report.kind)
        case .idle: return .idle
        case .done: return .finished
        case .error: return .failed
        }
    }

    /// What the screen says on its own — the fallback for a program that does not report.
    public static func activity(ofScreen screen: ScreenState?) -> AgentActivity? {
        switch screen {
        case .waitingForInput: return .needsYou(kind: nil)
        case .working: return .working
        case nil: return nil
        }
    }

    /// How urgently a state wants the person's eyes, highest first.
    static func urgency(_ state: ProgramStatusState) -> Int {
        switch state {
        case .blocked: return 4
        case .working: return 3
        case .error: return 2
        case .done: return 1
        case .idle: return 0
        }
    }

    /// The comparison key behind ``decidingReport``: urgency, then the root, then recency.
    private static func rank(_ report: ProgramStatusReport, at index: Int) -> (Int, Int, Int) {
        (urgency(report.state), report.id.isEmpty ? 1 : 0, index)
    }
}
