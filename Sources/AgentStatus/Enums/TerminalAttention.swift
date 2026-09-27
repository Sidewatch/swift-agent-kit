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

/// Kept separate from ``TerminalStatus`` because it is a different KIND of fact: status is
/// observed continuously from the process table, while this is a verdict about the screen that
/// stays true until you look. Merging them would mean re-deriving it on every poll.
///
/// One case since 18 Sep 2026: `done` was the `Stop` hook's signal, and nothing had produced it
/// since the hooks layer was removed on 11 Sep — completion is the process transition's business
/// (``TerminalStatus/finished``).
public enum TerminalAttention: Equatable, Sendable {
    /// A prompt is on screen — a permission ask or a question. Nothing moves until you answer.
    case waiting
}

/// One terminal's row in the rail: identity, how to name it, what it is doing, and where.
///
