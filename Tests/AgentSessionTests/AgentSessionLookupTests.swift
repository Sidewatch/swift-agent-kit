//
//  AgentSessionLookupTests.swift
//  AgentSessionTests
//
//  One lookup per agent terminal, each finding its own agent's session — two agents in one folder.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// `AgentSessionLookup.perTerminal`, `resolve`, `uniqued` and `Agents.sessionKey`.
final class AgentSessionLookupTests: XCTestCase {
    /// An agent with one session file per folder it has run in.
    private struct FakeAgent: AgentAdapter {
        let name: String
        let sessions: [String: URL]
        var processNames: Set<String> { [name] }
        func latestSession(for root: URL) -> URL? { sessions[root.standardizedFileURL.path] }
        func events(for root: URL) -> [TimelineEvent] { [] }
        func events(fromSession url: URL) -> [TimelineEvent] { [] }
        func usage(for root: URL) -> AgentUsage? { nil }
        func summary(for root: URL) -> AgentSummary? { nil }
    }

    private let folder = URL(fileURLWithPath: "/work/site")
    private let project = URL(fileURLWithPath: "/work")

    func testEachTerminalsLookupFindsItsOwnAgentInASharedFolder() throws {
        let claude = FakeAgent(name: "claude", sessions: [folder.path: URL(fileURLWithPath: "/sessions/claude.jsonl")])
        let codex = FakeAgent(name: "codex", sessions: [folder.path: URL(fileURLWithPath: "/sessions/codex.jsonl")])
        let lookups = AgentSessionLookup.perTerminal(
            [(directory: folder, agent: "claude"), (directory: folder, agent: "codex")], folders: [project], fallbackAgent: "claude",
            project: project)
        let found = lookups.compactMap { $0.resolve(in: [claude, codex]) }
        XCTAssertEqual(found.map(\.adapter.name), ["claude", "codex"], "both agents' sessions, not the current one twice")
        XCTAssertEqual(Set(found.map(\.session.lastPathComponent)), ["claude.jsonl", "codex.jsonl"])
    }

    func testATerminalsDirectoryLeadsAndRepeatsAreDropped() {
        let lookups = AgentSessionLookup.perTerminal(
            [(directory: URL(fileURLWithPath: "/p/a"), agent: nil), (directory: URL(fileURLWithPath: "/p/b"), agent: "codex")],
            folders: [URL(fileURLWithPath: "/p"), URL(fileURLWithPath: "/p/x/../a")], fallbackAgent: nil, project: nil)
        XCTAssertEqual(
            lookups.map { $0.candidates.map(\.path) }, [["/p/a", "/p"], ["/p/b", "/p", "/p/x/../a"]],
            "a repeat is dropped by its standardized path; a kept one keeps its spelling")
        XCTAssertEqual(lookups.map(\.preferredAgent), [nil, "codex"])
    }

    func testWithNoAgentTerminalTheProjectsFoldersAreTheOneLookup() {
        let lookups = AgentSessionLookup.perTerminal([], folders: [project, project], fallbackAgent: "gemini", project: project)
        XCTAssertEqual(lookups, [AgentSessionLookup(candidates: [project], preferredAgent: "gemini", project: project)])
    }

    func testASessionsKeyIsItsAgentAndTranscript() {
        let hit: Agents.Hit = (FakeAgent(name: "codex", sessions: [:]), folder, URL(fileURLWithPath: "/s/x.jsonl"))
        XCTAssertEqual(Agents.sessionKey(hit), "codex|/s/x.jsonl")
    }
}
