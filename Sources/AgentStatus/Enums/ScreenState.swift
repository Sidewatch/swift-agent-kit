//
//  ScreenState.swift
//  AgentStatus
//
//  A prompt is on screen: the agent is blocked until the user answers.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What the visible screen says the agent is doing: blocked on a prompt (`waitingForInput`) or
/// busy (`working`).
public enum ScreenState: Equatable, Sendable {
    /// A prompt is on screen: the agent is blocked until the user answers.
    case waitingForInput
    /// The agent's own "esc to interrupt" (or equivalent) is showing: it is working.
    case working
}
