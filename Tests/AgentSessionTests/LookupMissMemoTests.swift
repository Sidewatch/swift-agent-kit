//
//  LookupMissMemoTests.swift
//  AgentSessionTests
//
//  Idle polling with no session lists each directory once per interval, not once per tick.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// Idle polling with no session lists each directory once per interval, not once per tick.
final class LookupMissMemoTests: XCTestCase {
    private var scratch: URL!
    private let root = URL(fileURLWithPath: "/private/tmp/miss-memo/project")

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("miss-memo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    private func folder(_ path: String) throws -> URL {
        let url = scratch.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAMissIsRememberedForTheIntervalAndAHitIsNot() {
        let misses = LookupMisses()
        let t0 = Date()
        var calls = 0
        func look(_ answer: Int?, at now: Date) -> Int? {
            misses.remembering("k", now: now) {
                calls += 1; return answer
            }
        }
        XCTAssertNil(look(nil, at: t0))
        XCTAssertEqual(calls, 1)
        XCTAssertNil(look(7, at: t0.addingTimeInterval(1)))
        XCTAssertEqual(calls, 1, "within the interval the lookup is not made")
        XCTAssertEqual(look(7, at: t0.addingTimeInterval(LookupMisses.interval)), 7)
        XCTAssertEqual(calls, 2, "the interval over, it is")
        XCTAssertEqual(look(8, at: t0.addingTimeInterval(LookupMisses.interval + 0.1)), 8)
        XCTAssertEqual(calls, 3, "a hit is never remembered")
        XCTAssertNil(look(nil, at: t0.addingTimeInterval(LookupMisses.interval + 0.2)))
        XCTAssertNil(look(9, at: t0.addingTimeInterval(LookupMisses.interval + 0.3)))
        XCTAssertEqual(calls, 4, "a new miss is remembered again")
        XCTAssertFalse(misses.isFresh("other", now: t0), "keys are independent")
    }

    func testIdlePollingWithNoSessionListsEachDirectoryOnce() throws {
        // Claude: the project folder exists but holds no transcript.
        let projects = try folder("projects")
        _ = try folder("projects/-private-tmp-miss-memo-project")
        let claude = ClaudeCodeAdapter(projectsRoot: projects)
        XCTAssertNil(claude.latestSession(for: root))
        let claudeListings = claude.locator.reader.listings
        XCTAssertEqual(claudeListings, 1)
        XCTAssertNil(claude.latestSession(for: root))
        XCTAssertNil(Agents.resolve(candidates: [root], in: [claude]))
        XCTAssertEqual(
            claude.locator.reader.listings, claudeListings + 1, "the subfolder search lists the projects folder once, then nothing")

        // Codex: a day folder with no rollout for the project.
        let codex = CodexAdapter(sessionsRoot: try folder("codex"))
        _ = try folder("codex/2026/10/09")
        XCTAssertNil(codex.latestSession(for: root))
        let codexListings = codex.index.reader.listings
        XCTAssertEqual(codexListings, 4, "sessions, year, month, day")
        XCTAssertNil(codex.latestSession(for: root))
        XCTAssertEqual(codex.index.reader.listings, codexListings)

        // Gemini: the registry names the project, whose chats folder is empty.
        let gemini = try folder("gemini")
        try #"{"projects":{"ROOT":"p"}}"#.replacingOccurrences(of: "ROOT", with: root.path)
            .write(to: gemini.appendingPathComponent("projects.json"), atomically: true, encoding: .utf8)
        _ = try folder("gemini/tmp/p/chats")
        let geminiAdapter = GeminiAdapter(runtimeRoots: [gemini])
        XCTAssertNil(geminiAdapter.latestSession(for: root))
        let geminiListings = geminiAdapter.index.reader.listings
        XCTAssertEqual(geminiListings, 2, "the registry's slug and the legacy hash folder")
        XCTAssertNil(geminiAdapter.latestSession(for: root))
        XCTAssertEqual(geminiAdapter.index.reader.listings, geminiListings)

        // Grok: an empty bucket.
        let grok = GrokAdapter(sessionsRoot: try folder("grok"))
        _ = try folder("grok/\(GrokSessionIndex.encode(root.path))")
        XCTAssertNil(grok.latestSession(for: root))
        let grokListings = grok.index.reader.listings
        XCTAssertEqual(grokListings, 1)
        XCTAssertNil(grok.latestSession(for: root))
        XCTAssertEqual(grok.index.reader.listings, grokListings)
    }
}
