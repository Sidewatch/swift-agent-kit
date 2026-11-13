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

    func testASessionTheAgentNamedIsTheSessionWhateverIsNewestInTheFolder() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("named-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let mine = scratch.appendingPathComponent("mine.jsonl"), theirs = scratch.appendingPathComponent("theirs.jsonl")
        try "{}".write(to: mine, atomically: true, encoding: .utf8)
        try "{}".write(to: theirs, atomically: true, encoding: .utf8)
        // The folder's latest is the other terminal's: two of one agent in one folder.
        let claude = FakeAgent(name: "claude", sessions: [folder.path: theirs])
        let lookups = AgentSessionLookup.perTerminal(
            naming: [(directory: folder, agent: "claude", session: mine), (directory: folder, agent: "claude", session: nil)],
            folders: [project],
            fallbackAgent: nil, project: project)
        let found = lookups.compactMap { $0.resolve(in: [claude]) }
        XCTAssertEqual(found.map(\.session.lastPathComponent), ["mine.jsonl", "theirs.jsonl"], "the one that named its session reads it")
        XCTAssertEqual(found.first?.root, folder)
        XCTAssertEqual(Set(found.map { Agents.sessionKey($0) }).count, 2, "two sessions, two keys")

        func resolved(_ session: URL?, agent: String?) -> String? {
            AgentSessionLookup(candidates: [folder], preferredAgent: agent, project: project, session: session)
                .resolve(in: [claude])?.session.lastPathComponent
        }
        XCTAssertEqual(
            resolved(scratch.appendingPathComponent("gone.jsonl"), agent: "claude"), "theirs.jsonl",
            "a session that is gone is searched for as before")
        XCTAssertEqual(resolved(mine, agent: nil), "theirs.jsonl", "a session with no agent to read it")
        XCTAssertEqual(resolved(mine, agent: "codex"), "theirs.jsonl", "nor one whose agent has no adapter here")
        XCTAssertNil(
            AgentSessionLookup(candidates: [], preferredAgent: "claude", session: mine).resolve(in: [claude]), "nothing open: nothing read")
    }

    func testClaudeCodeReadsTheUsageOfTheSessionAskedFor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("named-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func transcript(_ name: String, output: Int) throws -> URL {
            let url = root.appendingPathComponent(name)
            let line =
                #"{"type":"assistant","timestamp":"2026-07-09T10:08:00.000Z","message":{"model":"claude-sonnet-4","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":OUT},"content":[{"type":"text","text":"ok"}]}}"#
            try (line.replacingOccurrences(of: "OUT", with: "\(output)") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        let adapter = ClaudeCodeAdapter(projectsRoot: root.appendingPathComponent("none"))
        let folder = URL(fileURLWithPath: "/nowhere")
        XCTAssertEqual(adapter.usage(fromSession: try transcript("a.jsonl", output: 111), root: folder)?.outputTokens, 111)
        XCTAssertEqual(adapter.usage(fromSession: try transcript("b.jsonl", output: 222), root: folder)?.outputTokens, 222)
        XCTAssertNil(adapter.usage(for: folder), "the folder has no session of its own")
    }

    func testASessionsKeyIsItsAgentAndTranscript() {
        let hit: Agents.Hit = (FakeAgent(name: "codex", sessions: [:]), folder, URL(fileURLWithPath: "/s/x.jsonl"))
        XCTAssertEqual(Agents.sessionKey(hit), "codex|/s/x.jsonl")
    }
}
