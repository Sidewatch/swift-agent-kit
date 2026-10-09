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
/// from the process table, while this is a verdict — from the program's own report or from the
/// screen — that stays true until you look.
public enum TerminalAttention: Equatable, Sendable {
    /// A prompt is up — a permission ask, a question, a sign-in. Nothing moves until you answer.
    case waiting
    /// The agent's run ended by its own account: its report went from working or blocked to
    /// idle, done or error while it stayed in the foreground. The process transition cannot see
    /// this for an agent that stays resident between turns; only the program's report can.
    case done
}
