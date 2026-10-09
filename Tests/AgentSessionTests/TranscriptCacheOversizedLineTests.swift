//
//  TranscriptCacheOversizedLineTests.swift
//  AgentSessionTests
//
//  A line longer than the cap is skipped whole, complete or still being written.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// A transcript is written by another program, and one of its lines can be as long as that
/// program likes. The cache reads such a line's bytes once, parses nothing of it, and moves its
/// offset past it — so a poll never holds more than the cap in memory for a line and never
/// re-reads a half-written giant on every tick.
final class TranscriptCacheOversizedLineTests: XCTestCase {
    private var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("oversized-\(UUID().uuidString).jsonl")
        try Data().write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func append(_ s: String) throws {
        let fh = try FileHandle(forWritingTo: file)
        fh.seekToEndOfFile()
        fh.write(Data(s.utf8))
        fh.closeFile()
    }

    /// A user message of `text`, as Claude Code writes one.
    private func userLine(_ text: String) -> String {
        "{\"type\":\"user\",\"timestamp\":\"2026-07-09T10:07:12.000Z\",\"message\":{\"content\":\"\(text)\"}}\n"
    }

    private func prompts(_ snapshot: TranscriptCache<ClaudeTranscriptState>.Snapshot) -> [String] {
        snapshot.events.map(\.detail)
    }

    func testACompleteOversizedLineIsSkippedAndTheRestParsed() throws {
        let cache = TranscriptCache<ClaudeTranscriptState>()
        let giant = String(repeating: "x", count: TranscriptCache<ClaudeTranscriptState>.lineCap)
        try append(userLine("first") + userLine(giant) + userLine("third"))
        let snapshot = cache.results(for: file)
        XCTAssertEqual(prompts(snapshot), ["first", "third"], "the giant is valid JSON, and still skipped for its size")
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        XCTAssertEqual(cache.bytesRead, size, "read once, whole")
        XCTAssertEqual(cache.readCount, 1)
        XCTAssertEqual(prompts(cache.results(for: file)), ["first", "third"], "a second poll is the memoized snapshot")
        XCTAssertEqual(cache.readCount, 1, "and costs no read")
    }

    func testAnOversizedLineStillBeingWrittenIsDroppedAsItArrives() throws {
        let cache = TranscriptCache<ClaudeTranscriptState>()
        let cap = TranscriptCache<ClaudeTranscriptState>.lineCap
        try append(userLine("first"))
        XCTAssertEqual(prompts(cache.results(for: file)), ["first"])
        // The giant arrives in two polls: a tail past the cap, then its end and a normal line.
        try append("{\"type\":\"user\",\"message\":{\"content\":\"" + String(repeating: "y", count: cap))
        let bytesAfterFirst = cache.bytesRead
        XCTAssertEqual(prompts(cache.results(for: file)), ["first"], "a tail past the cap is not parsed")
        let readForTail = cache.bytesRead - bytesAfterFirst
        try append(String(repeating: "y", count: 1000) + "\"}}\n" + userLine("after"))
        XCTAssertEqual(prompts(cache.results(for: file)), ["first", "after"], "the giant's end is dropped, the line after it parsed")
        XCTAssertLessThan(
            cache.bytesRead - bytesAfterFirst - readForTail, 2000, "the third poll read only what was appended since, not the tail again")
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        XCTAssertEqual(cache.bytesRead, size, "every byte read exactly once")
        XCTAssertEqual(prompts(cache.results(for: file)), ["first", "after"], "steady state: memoized")
    }
}
