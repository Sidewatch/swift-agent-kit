//
//  AttentionCycle.swift
//  AgentStatus
//
//  Which terminal a "next agent needing you" command goes to.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Which terminal a "next agent needing you" command goes to, given every terminal's status in
/// the host's order (pane by pane, tab by tab).
///
/// A question blocks the agent, so every terminal ``TerminalStatus/waiting`` on you comes before
/// any ``TerminalStatus/finished`` one. Within a kind the search starts AFTER the current
/// terminal and wraps, so pressing the key again walks on to the next one rather than staying
/// put; the current terminal is the last candidate, so it is chosen only when it is the one left.
public enum AttentionCycle {
    /// The index to go to from `current` (nil when no terminal is focused), or nil when no
    /// terminal needs you.
    public static func next(after current: Int?, in statuses: [TerminalStatus]) -> Int? {
        guard !statuses.isEmpty else { return nil }
        let start = current.map { ($0 + 1) % statuses.count } ?? 0
        let order = (0..<statuses.count).map { (start + $0) % statuses.count }
        return order.first { statuses[$0] == .waiting } ?? order.first { statuses[$0] == .finished }
    }

    /// Every terminal that needs you, in the order to offer them: each one ``TerminalStatus/waiting``
    /// on you (a question blocks the agent) before each ``TerminalStatus/finished`` one, the host's
    /// order kept within a kind — the Dock menu's list, where all of them show at once.
    public static func needingYou(in statuses: [TerminalStatus]) -> [Int] {
        statuses.indices.filter { statuses[$0] == .waiting } + statuses.indices.filter { statuses[$0] == .finished }
    }
}
