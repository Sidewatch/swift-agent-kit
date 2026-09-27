//
//  AgentsResolveTests.swift
//  AgentSessionTests
//
//  Tests for `Agents.resolve(candidates:)`: the first candidate with a session wins, and a
//  terminal cwd deep inside the project still resolves to the opened root.
//
//  Created by David Sherlock on 9/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// Tests for `Agents.resolve(candidates:)`: the first candidate with a session wins, and a
/// terminal cwd deep inside the project still resolves to the opened root.
final class AgentsResolveTests: XCTestCase {

    private var projectsRoot: URL!
    private let opened = URL(fileURLWithPath: "/private/tmp/agents-resolve-tests/site")
    private let terminalCwd = URL(fileURLWithPath: "/private/tmp/agents-resolve-tests/site/wp-admin/css/colors/coffee")

    override func setUpWithError() throws {
        projectsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-resolve-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    /// The `<projectsRoot>/<encoded cwd>` directory Claude Code would use for `root`.
    private func projectDir(_ root: URL) -> URL {
        let encoded = String(root.path.map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : "-" })
        return projectsRoot.appendingPathComponent(encoded, isDirectory: true)
    }

    private func recordSession(for root: URL) throws {
        try FileManager.default.createDirectory(at: projectDir(root), withIntermediateDirectories: true)
        try "{\"type\":\"user\",\"timestamp\":\"2026-09-02T10:00:00.000Z\",\"message\":{\"content\":\"hi\"}}\n"
            .write(to: projectDir(root).appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    }

    func testResolvePicksTheFirstCandidateWithASession() throws {
        try recordSession(for: terminalCwd)
        let adapters: [AgentAdapter] = [ClaudeCodeAdapter(projectsRoot: projectsRoot)]

        XCTAssertNil(Agents.active(for: opened, in: adapters), "the opened folder alone has no session")
        let hit = try XCTUnwrap(Agents.resolve(candidates: [terminalCwd, opened], in: adapters))
        XCTAssertEqual(hit.root, terminalCwd, "the terminal's cwd is where the transcript lives")
        XCTAssertEqual(
            Agents.resolve(candidates: [opened, terminalCwd], in: adapters)?.root, terminalCwd,
            "a candidate without a session is skipped, whatever its position")
        XCTAssertNil(Agents.resolve(candidates: [], in: adapters))
        XCTAssertNil(Agents.resolve(candidates: [opened], in: adapters))
    }

    func testResolveHonoursCandidateOrderWhenSeveralHaveSessions() throws {
        try recordSession(for: terminalCwd)
        try recordSession(for: opened)
        let adapters: [AgentAdapter] = [ClaudeCodeAdapter(projectsRoot: projectsRoot)]
        XCTAssertEqual(Agents.resolve(candidates: [terminalCwd, opened], in: adapters)?.root, terminalCwd)
        XCTAssertEqual(Agents.resolve(candidates: [opened, terminalCwd], in: adapters)?.root, opened)
    }

    /// Several agents can work in one folder (a terminal each): the most recently active one is
    /// read, unless the caller names the agent in the terminal the person is using.
    func testSeveralAgentsInOneFolderResolveByPreferenceThenRecency() throws {
        try recordSession(for: terminalCwd)
        let claudeFile = projectDir(terminalCwd).appendingPathComponent("session.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: claudeFile.path)
        let codexDay = projectsRoot.appendingPathComponent("codex/2026/09/27", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDay, withIntermediateDirectories: true)
        let rollout = codexDay.appendingPathComponent("rollout-1.jsonl")
        try #"{"type":"session_meta","payload":{"cwd":"CWD","source":"cli"}}"#
            .replacingOccurrences(of: "CWD", with: terminalCwd.path).write(to: rollout, atomically: true, encoding: .utf8)
        let adapters: [AgentAdapter] = [
            ClaudeCodeAdapter(projectsRoot: projectsRoot),
            CodexAdapter(sessionsRoot: projectsRoot.appendingPathComponent("codex")),
        ]

        XCTAssertEqual(Agents.resolve(candidates: [terminalCwd], in: adapters)?.adapter.name, "Codex", "the newer session wins")
        XCTAssertEqual(
            Agents.resolve(candidates: [terminalCwd], preferring: "Claude Code", in: adapters)?.adapter.name, "Claude Code",
            "the focused terminal's agent wins when it has a session there")
        XCTAssertEqual(
            Agents.resolve(candidates: [terminalCwd], preferring: "Gemini", in: adapters)?.adapter.name, "Codex",
            "a preferred agent with no session falls back to the most recent")
    }

    /// Edits by every agent in the folder count, not just the latest one's.
    func testEditedFilesAreEveryAgentsEdits() throws {
        try FileManager.default.createDirectory(at: projectDir(terminalCwd), withIntermediateDirectories: true)
        let claudeFile = projectDir(terminalCwd).appendingPathComponent("session.jsonl")
        try
            #"{"type":"assistant","timestamp":"2026-09-27T10:00:00.000Z","message":{"model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"/w/claude.txt","content":"x"}}]}}"#
            .appending("\n").write(to: claudeFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: claudeFile.path)
        let codexDay = projectsRoot.appendingPathComponent("codex/2026/09/27", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDay, withIntermediateDirectories: true)
        try [
            #"{"type":"session_meta","payload":{"cwd":"CWD","source":"cli"}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"c1","name":"apply_patch","input":"*** Begin Patch\n*** Add File: /w/codex.txt\n+x\n*** End Patch"}}"#,
        ]
        .joined(separator: "\n").replacingOccurrences(of: "CWD", with: terminalCwd.path)
        .write(to: codexDay.appendingPathComponent("rollout-1.jsonl"), atomically: true, encoding: .utf8)
        let adapters: [AgentAdapter] = [
            ClaudeCodeAdapter(projectsRoot: projectsRoot),
            CodexAdapter(sessionsRoot: projectsRoot.appendingPathComponent("codex")),
        ]
        XCTAssertEqual(Agents.editedFiles(for: terminalCwd, in: adapters), ["/w/claude.txt", "/w/codex.txt"])
        XCTAssertEqual(Agents.editedFiles(for: opened, in: adapters), [], "no session, no edits")
    }
}
