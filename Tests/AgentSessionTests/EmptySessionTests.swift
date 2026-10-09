//
//  EmptySessionTests.swift
//  AgentSessionTests
//
//  A transcript written before its first prompt is a session with no turns, not "no session".
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// A transcript written before its first prompt (its only record is the session's mode) is a
/// session with no turns, not "no session", so a host seeds an empty baseline and sees turn 1 as new.
final class EmptySessionTests: XCTestCase {
    func testATranscriptBeforeItsFirstPromptIsASessionWithNoTurns() throws {
        let projectsRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "empty-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: projectsRoot) }
        let projectDir = projectsRoot.appendingPathComponent("-private-tmp-empty-session-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: "/private/tmp/empty-session/project")
        let file = projectDir.appendingPathComponent("fresh.jsonl")
        try #"{"type":"mode"}"#.appending("\n").write(to: file, atomically: false, encoding: .utf8)

        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        let hit = try XCTUnwrap(Agents.resolve(candidates: [root], in: [adapter]), "the file exists: the session has begun")
        XCTAssertEqual(hit.session.canonicalPath, file.canonicalPath)
        XCTAssertTrue(hit.adapter.events(for: hit.root).isEmpty)
        XCTAssertTrue(TurnBoundary.turns(in: hit.adapter.events(for: hit.root)).isEmpty)

        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(
            Data(
                #"{"type":"user","cwd":"/private/tmp/empty-session/project","timestamp":"2026-10-09T10:00:00.000Z","message":{"content":"Go"}}"#
                    .appending("\n").utf8))
        handle.closeFile()
        let turns = TurnBoundary.turns(in: hit.adapter.events(for: hit.root))
        XCTAssertEqual(turns.map(\.prompt), ["Go"], "the first prompt is turn 1 against an empty baseline")
    }
}
