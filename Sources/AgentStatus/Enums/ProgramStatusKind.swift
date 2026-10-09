//
//  ProgramStatusKind.swift
//  AgentStatus
//
//  What a blocked program needs from the person: the `kind` of a blocked OSC 7501 record.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What a blocked program needs from the person — the `kind` of a blocked Program Status
/// Protocol (OSC 7501) record. The raw values are the protocol's words.
public enum ProgramStatusKind: String, CaseIterable, Equatable, Sendable {
    /// Permission to do something (run a command, edit a file).
    case permission
    /// An answer to a question.
    case question
    /// A sign-in or a credential.
    case auth

    /// What a notification says when the program sent no message of its own.
    public var label: String {
        switch self {
        case .permission:
            return String(
                localized: "Waiting for permission", bundle: .module,
                comment: "Notification body: the agent asked permission to do something")
        case .question:
            return String(localized: "Waiting for an answer", bundle: .module, comment: "Notification body: the agent asked a question")
        case .auth:
            return String(
                localized: "Waiting for a sign-in", bundle: .module, comment: "Notification body: the agent needs a sign-in or a credential"
            )
        }
    }
}
