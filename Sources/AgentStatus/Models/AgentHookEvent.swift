//
//  AgentHookEvent.swift
//  AgentStatus
//
//  One thing an agent said about itself through a hook.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One event an agent reported through a hook the person installed: which session it is, and
/// what just happened in it. Text fields are the agent's own, untrusted: show them as plain text.
public struct AgentHookEvent: Equatable, Sendable {
    /// What happened.
    public enum Kind: Equatable, Sendable {
        /// A session began, resumed or was cleared.
        case sessionStarted
        /// The person submitted a prompt.
        case promptSubmitted(String)
        /// The agent finished responding.
        case stopped
        /// The agent is waiting on the person: for permission, or for an answer.
        case needsYou(ProgramStatusKind, message: String?)
        /// The session ended.
        case sessionEnded
    }

    /// What happened.
    public let kind: Kind
    /// The agent's id for the session.
    public let sessionID: String
    /// The session's transcript, when the agent names it.
    public let transcriptPath: String?
    /// The folder the session runs in, when the agent names it.
    public let directory: String?

    /// One event.
    public init(kind: Kind, sessionID: String, transcriptPath: String? = nil, directory: String? = nil) {
        self.kind = kind
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
        self.directory = directory
    }
}
