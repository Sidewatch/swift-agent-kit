//
//  StableSessionChoiceTests.swift
//  AgentSessionTests
//
//  Two transcripts in one folder: the one chosen stays chosen while it is being written.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// Two transcripts in one folder: the one chosen stays chosen while it is being written, and a
/// newer one takes over only once it has gone quiet.
final class StableSessionChoiceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("stable-choice-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Writes `name` under `folder` with the given modification date.
    private func file(_ name: String, in folder: URL? = nil, content: String = "x\n", at date: Date) throws -> URL {
        let url = (folder ?? dir).appendingPathComponent(name)
        try content.write(to: url, atomically: false, encoding: .utf8)
        try stamp(url, date)
        return url
    }

    private func stamp(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testTheChosenTranscriptIsKeptWhileBothAreBeingWritten() throws {
        let now = Date()
        let a = try file("a.jsonl", at: now.addingTimeInterval(-2)), b = try file("b.jsonl", at: now.addingTimeInterval(-1))
        let choice = SessionChoice()
        XCTAssertEqual(choice.choose(for: "k", newest: b, now: now)?.lastPathComponent, "b.jsonl", "nothing held yet: the newest")
        try stamp(a, now)
        XCTAssertEqual(choice.choose(for: "k", newest: a, now: now)?.lastPathComponent, "b.jsonl", "b was written a second ago: live")
        try stamp(b, now.addingTimeInterval(1))
        XCTAssertEqual(choice.choose(for: "k", newest: b, now: now.addingTimeInterval(1))?.lastPathComponent, "b.jsonl")
        try stamp(a, now.addingTimeInterval(2))
        XCTAssertEqual(
            choice.choose(for: "k", newest: a, now: now.addingTimeInterval(2))?.lastPathComponent, "b.jsonl",
            "alternating writes never flip the choice")
        try stamp(b, now.addingTimeInterval(3))
        try stamp(a, now.addingTimeInterval(41))
        XCTAssertEqual(
            choice.choose(for: "k", newest: a, now: now.addingTimeInterval(41))?.lastPathComponent, "b.jsonl",
            "b advanced since the previous poll, so it is live however old the clock says it is")
        XCTAssertEqual(
            choice.choose(for: "k", newest: a, now: now.addingTimeInterval(80))?.lastPathComponent, "a.jsonl",
            "b did not advance and its last write is old: it has gone quiet")
    }

    func testAQuietTranscriptYieldsToTheGrowingOneOnce() throws {
        let now = Date()
        let a = try file("a.jsonl", at: now)
        let choice = SessionChoice()
        XCTAssertEqual(choice.choose(for: "k", newest: a, now: now)?.lastPathComponent, "a.jsonl")
        let later = now.addingTimeInterval(SessionChoice.quietAfter + 5)
        let b = try file("b.jsonl", at: later)
        XCTAssertEqual(choice.choose(for: "k", newest: b, now: later)?.lastPathComponent, "b.jsonl", "a has gone quiet: switch")
        try stamp(a, later.addingTimeInterval(1))
        XCTAssertEqual(
            choice.choose(for: "k", newest: a, now: later.addingTimeInterval(1))?.lastPathComponent, "b.jsonl",
            "b is live now; a's return does not flip back")
        XCTAssertNil(choice.choose(for: "k", newest: nil, now: later), "no candidate: no session, and the key is forgotten")
        XCTAssertEqual(choice.choose(for: "k", newest: a, now: later)?.lastPathComponent, "a.jsonl")
        try FileManager.default.removeItem(at: a)
        XCTAssertEqual(choice.choose(for: "k", newest: b, now: later)?.lastPathComponent, "b.jsonl", "a deleted file cannot be held")
    }

    func testTheAdapterDoesNotFlipBetweenTwoLiveClaudeSessions() throws {
        let projectsRoot = dir.appendingPathComponent("projects", isDirectory: true)
        let projectDir = projectsRoot.appendingPathComponent("-private-tmp-stable-choice-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: "/private/tmp/stable-choice/project")
        func prompt(_ text: String) -> String {
            #"{"type":"user","timestamp":"2026-10-09T10:00:00.000Z","message":{"content":"TEXT"}}"#.replacingOccurrences(
                of: "TEXT", with: text) + "\n"
        }
        let now = Date()
        _ = try file("a.jsonl", in: projectDir, content: prompt("a"), at: now)
        let b = try file("b.jsonl", in: projectDir, content: prompt("b"), at: now.addingTimeInterval(-1))
        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        XCTAssertEqual(adapter.latestSession(for: root)?.lastPathComponent, "a.jsonl")
        XCTAssertEqual(adapter.events(for: root).first?.detail, "a")
        try stamp(b, now.addingTimeInterval(1))
        XCTAssertEqual(adapter.latestSession(for: root)?.lastPathComponent, "a.jsonl", "a is live: held")
        XCTAssertEqual(adapter.events(for: root).first?.detail, "a")
        XCTAssertEqual(adapter.transcriptReadCount, 1, "no flip, no re-parse")
        XCTAssertEqual(
            Agents.resolve(candidates: [root], in: [adapter])?.session.lastPathComponent, "a.jsonl", "the hit carries the held file")
    }
}
