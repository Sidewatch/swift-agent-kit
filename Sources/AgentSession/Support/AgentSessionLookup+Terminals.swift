//
//  AgentSessionLookup+Terminals.swift
//  AgentSession
//
//  Resolving a lookup, one lookup per agent terminal, and a session's key.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension AgentSessionLookup {
    /// The live session this lookup names (``Agents/resolve(candidates:preferring:under:)`` with its
    /// candidates, agent and project). Every reader resolves through this one call, so none disagrees
    /// about which session is live.
    func resolve() -> Agents.Hit? { resolve(in: Agents.all) }

    /// Test seam: ``resolve()`` over an explicit adapter list.
    internal func resolve(in adapters: [AgentAdapter]) -> Agents.Hit? {
        Agents.resolve(candidates: candidates, preferring: preferredAgent, under: project, in: adapters)
    }

    /// One lookup per agent terminal — its directory first, then the project's own `folders` — each
    /// preferring THAT terminal's agent, so every agent's session is found: two agents working in one
    /// folder each keep their own session instead of both resolving to the one the person is looking at.
    /// With no agent terminal (the agent runs in another app), one lookup over `folders` preferring
    /// `fallbackAgent`.
    static func perTerminal(_ terminals: [(directory: URL, agent: String?)], folders: [URL], fallbackAgent: String?, project: URL?)
        -> [AgentSessionLookup]
    {
        guard !terminals.isEmpty else {
            return [AgentSessionLookup(candidates: uniqued(folders), preferredAgent: fallbackAgent, project: project)]
        }
        return terminals.map { terminal in
            AgentSessionLookup(candidates: uniqued([terminal.directory] + folders), preferredAgent: terminal.agent, project: project)
        }
    }

    /// `urls` with later spellings of a path already listed left out (compared standardized), order kept.
    static func uniqued(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

public extension Agents {
    /// The key every per-session state is filed under: the agent and its transcript. Which transcript is
    /// read can change with the terminal in focus, and a resumed session is an old one made latest.
    static func sessionKey(_ hit: Hit) -> String { hit.adapter.name + "|" + hit.session.path }
}
