//
//  AgentSessionLookup.swift
//  AgentSession
//
//  Where to look for an agent's live session: the folders, the agent wanted, the project.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Where an agent's live session may be found: the folders a transcript may be keyed under, most
/// specific first; the agent wanted when several have sessions there; and the opened project, beneath
/// which a session launched in a subfolder is searched.
public struct AgentSessionLookup: Sendable, Equatable {
    /// Folders a session may be keyed under, most specific first.
    public let candidates: [URL]
    /// The adapter name of the agent wanted (the one running in the terminal concerned), if any.
    public let preferredAgent: String?
    /// The opened folder, nil when none is open.
    public let project: URL?

    /// A lookup over `candidates`, preferring `preferredAgent`, beneath `project`.
    public init(candidates: [URL], preferredAgent: String?, project: URL? = nil) {
        self.candidates = candidates
        self.preferredAgent = preferredAgent
        self.project = project
    }

    /// No folder open: nothing to look in.
    public static let none = AgentSessionLookup(candidates: [], preferredAgent: nil)
}
