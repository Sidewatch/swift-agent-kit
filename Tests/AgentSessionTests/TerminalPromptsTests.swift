//
//  TerminalPromptsTests.swift
//  AgentSessionTests
//
//  The last prompt of a terminal's agent is given only where the session is certainly its own.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

final class TerminalPromptsTests: XCTestCase {
    private var root: URL!
    private var rollout: URL!
    /// The folder the fixture rollouts were recorded in.
    private let repo = URL(fileURLWithPath: "/tmp/large", isDirectory: true)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-prompts-\(UUID().uuidString)", isDirectory: true)
        let day = root.appendingPathComponent("2026/08/03", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "rollout-large", withExtension: "jsonl", subdirectory: "Fixtures/Codex"))
        rollout = day.appendingPathComponent("rollout-large.jsonl")
        try FileManager.default.copyItem(at: fixture, to: rollout)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func written(_ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: rollout.path)
    }

    private func latest(_ terminals: [TerminalPrompts.Terminal<Int>]) -> [Int: String] {
        TerminalPrompts.latest(for: terminals, in: [CodexAdapter(sessionsRoot: root)])
    }

    private func terminal(_ id: Int, in directory: URL? = nil, agent: String = CodexAdapter().name, seen: Date)
        -> TerminalPrompts.Terminal<Int>
    {
        TerminalPrompts.Terminal(id: id, directory: directory ?? repo, agent: agent, agentSeen: seen)
    }

    func testATerminalsAgentIsNamedByTheLastThingItWasAsked() throws {
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        try written(seen.addingTimeInterval(60))
        XCTAssertEqual(latest([terminal(1, seen: seen)]), [1: "Step 5"], "the last prompt of the fixture, read by hand")
    }

    func testASessionFromBeforeTheAgentAppearedIsNotItsOwn() throws {
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        try written(seen.addingTimeInterval(-600))
        XCTAssertEqual(latest([terminal(1, seen: seen)]), [:], "an earlier run's last prompt is not what this agent was asked")
    }

    func testTwoOfOneAgentInOneFolderAreNotGuessedApart() throws {
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        try written(seen.addingTimeInterval(60))
        XCTAssertEqual(latest([terminal(1, seen: seen), terminal(2, seen: seen)]), [:])
        let elsewhere = URL(fileURLWithPath: "/tmp/other", isDirectory: true)
        XCTAssertEqual(
            latest([terminal(1, seen: seen), terminal(2, in: elsewhere, seen: seen)]), [1: "Step 5"],
            "another folder's agent does not make this one uncertain, and has no session of its own")
        XCTAssertEqual(
            latest([terminal(1, seen: seen), terminal(2, agent: ClaudeCodeAdapter().name, seen: seen)]), [1: "Step 5"],
            "nor does another agent")
        XCTAssertEqual(latest([terminal(1, agent: "nobody", seen: seen)]), [:], "an agent with no adapter")
    }

    func testOnlyASessionWrittenSinceTheAgentAppearedIsItsOwn() {
        let seen = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(TerminalPrompts.sessionIsThisAgents(modified: seen.addingTimeInterval(30), agentSeen: seen))
        XCTAssertTrue(
            TerminalPrompts.sessionIsThisAgents(modified: seen.addingTimeInterval(-2), agentSeen: seen),
            "the file is made as the agent starts")
        XCTAssertFalse(TerminalPrompts.sessionIsThisAgents(modified: seen.addingTimeInterval(-600), agentSeen: seen))
        XCTAssertFalse(TerminalPrompts.sessionIsThisAgents(modified: nil, agentSeen: seen))
        XCTAssertFalse(TerminalPrompts.sessionIsThisAgents(modified: seen, agentSeen: nil))
    }
}
