//
//  TerminalPrompts.swift
//  AgentSession
//
//  What the agent in each terminal was last asked, where that can be known.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What the agent in each terminal was last asked, for naming its tab. A session is filed by the
/// folder its agent runs in, not by terminal, so a prompt is given only where it is certain whose
/// it is: one terminal runs that agent in that folder, and the folder's newest session was written
/// since the terminal first showed the agent. Anything else names nothing, never a guess.
public enum TerminalPrompts {
    /// A terminal running an agent.
    public struct Terminal<ID: Hashable & Sendable>: Sendable {
        /// What the caller knows the terminal by.
        public let id: ID
        /// The folder the agent runs in.
        public let directory: URL
        /// The agent's adapter name (``AgentAdapter/name``).
        public let agent: String
        /// When the terminal first showed this agent.
        public let agentSeen: Date

        /// A terminal running `agent` in `directory`, first seen at `agentSeen`.
        public init(id: ID, directory: URL, agent: String, agentSeen: Date) {
            self.id = id
            self.directory = directory
            self.agent = agent
            self.agentSeen = agentSeen
        }
    }

    /// How far before a terminal first showed its agent a session file may have been written and
    /// still be that agent's: the file is made as the agent starts, the terminal notices a poll later.
    public static let sessionSlack: TimeInterval = 5

    /// The last prompt of each terminal whose session is certain. Reads transcripts: call off the
    /// main thread.
    public static func latest<ID>(for terminals: [Terminal<ID>]) -> [ID: String] { latest(for: terminals, in: Agents.all) }

    /// Test seam: ``latest(for:)`` over an explicit adapter list.
    static func latest<ID>(for terminals: [Terminal<ID>], in adapters: [AgentAdapter]) -> [ID: String] {
        var prompts: [ID: String] = [:]
        for terminal in unshared(terminals) {
            guard let adapter = adapters.first(where: { $0.name == terminal.agent }),
                let session = adapter.latestSession(for: terminal.directory),
                sessionIsThisAgents(modified: modified(session), agentSeen: terminal.agentSeen),
                let prompt = TurnBoundary.turns(in: adapter.events(fromSession: session)).last?.prompt,
                !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            prompts[terminal.id] = prompt
        }
        return prompts
    }

    /// The terminals that share their agent and folder with no other: two of one agent in one folder
    /// write two sessions, and nothing says which terminal has which.
    static func unshared<ID>(_ terminals: [Terminal<ID>]) -> [Terminal<ID>] {
        func key(_ t: Terminal<ID>) -> String { t.agent + "|" + t.directory.standardizedFileURL.path }
        var count: [String: Int] = [:]
        for t in terminals { count[key(t), default: 0] += 1 }
        return terminals.filter { count[key($0)] == 1 }
    }

    /// Whether a session file is the one the agent in a terminal is writing: it was written after
    /// the terminal first showed that agent (less ``sessionSlack``). A folder's newest session may
    /// be an earlier run's, and its last prompt is not what this agent was asked.
    public static func sessionIsThisAgents(modified: Date?, agentSeen: Date?) -> Bool {
        guard let modified, let agentSeen else { return false }
        return modified >= agentSeen.addingTimeInterval(-sessionSlack)
    }

    private static func modified(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }
}
