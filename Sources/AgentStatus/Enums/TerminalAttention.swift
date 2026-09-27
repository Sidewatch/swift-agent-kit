//
//  TerminalAttention.swift
//  AgentStatus
//
//  Kept separate from ``TerminalStatus`` because it is a different KIND of fact: status is
//  observed continuously from the process table, while this is an event that arrived once and
//  stays true until you look.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An unacknowledged signal from the agent running in a terminal. Kept separate from
/// ``TerminalStatus`` because it is a different KIND of fact: status is observed continuously
/// from the process table, while this is a verdict about the screen that stays true until you
/// look. Completion is not a case here: it is the process transition's business
/// (``TerminalStatus/finished``).
public enum TerminalAttention: Equatable, Sendable {
    /// A prompt is on screen — a permission ask or a question. Nothing moves until you answer.
    case waiting
}
