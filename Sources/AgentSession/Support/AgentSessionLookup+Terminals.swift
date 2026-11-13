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
        // A session the agent named is the session: two of one agent in one folder write two
        // transcripts, and the newest in the folder is as often the other's.
        if let session, let adapter = adapters.first(where: { $0.name == preferredAgent }), let root = candidates.first,
            FileManager.default.fileExists(atPath: session.path)
        {
            return (adapter, root, session)
        }
        return Agents.resolve(candidates: candidates, preferring: preferredAgent, under: project, in: adapters)
    }

    /// One lookup per agent terminal — its directory first, then the project's own `folders` — each
    /// preferring THAT terminal's agent, so every agent's session is found: two agents working in one
    /// folder each keep their own session instead of both resolving to the one the person is looking at.
    /// With no agent terminal (the agent runs in another app), one lookup over `folders` preferring
    /// `fallbackAgent`.
    static func perTerminal(_ terminals: [(directory: URL, agent: String?)], folders: [URL], fallbackAgent: String?, project: URL?)
        -> [AgentSessionLookup]
    {
        perTerminal(
            naming: terminals.map { ($0.directory, $0.agent, nil) }, folders: folders, fallbackAgent: fallbackAgent, project: project)
    }

    /// ``perTerminal(_:folders:fallbackAgent:project:)`` where a terminal's agent may have named its
    /// own session: that terminal's lookup is then that session and no other.
    static func perTerminal(
        naming terminals: [(directory: URL, agent: String?, session: URL?)], folders: [URL], fallbackAgent: String?, project: URL?
    ) -> [AgentSessionLookup] {
        guard !terminals.isEmpty else {
            return [AgentSessionLookup(candidates: uniqued(folders), preferredAgent: fallbackAgent, project: project)]
        }
        return terminals.map { terminal in
            AgentSessionLookup(
                candidates: uniqued([terminal.directory] + folders), preferredAgent: terminal.agent, project: project,
                session: terminal.session)
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
