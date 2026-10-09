//
//  TranscriptCacheByPathTests.swift
//  AgentSessionTests
//
//  The cache remembers each transcript by its path, so a project whose live session changes
//  does not re-parse what it already read.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// The cache remembers each transcript by its path, so a project whose live session changes
/// does not re-parse what it already read, and keeps only the most recently served few.
final class TranscriptCacheByPathTests: XCTestCase {
    private var projectsRoot: URL!
    private var projectDir: URL!
    private let root = URL(fileURLWithPath: "/private/tmp/cache-by-path/project")

    override func setUpWithError() throws {
        projectsRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cache-by-path-\(UUID().uuidString)", isDirectory: true)
        projectDir = projectsRoot.appendingPathComponent("-private-tmp-cache-by-path-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: projectsRoot) }

    private func prompt(_ text: String) -> String {
        #"{"type":"user","timestamp":"2026-10-09T10:00:00.000Z","message":{"content":"TEXT"}}"#.replacingOccurrences(of: "TEXT", with: text)
            + "\n"
    }

    private func stamp(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func append(_ s: String, to url: URL) throws {
        let fh = try FileHandle(forWritingTo: url)
        fh.seekToEndOfFile()
        fh.write(Data(s.utf8))
        fh.closeFile()
    }

    func testSwitchingBackToACachedTranscriptCostsAStatNotAParse() throws {
        let now = Date()
        let a = projectDir.appendingPathComponent("a.jsonl"), b = projectDir.appendingPathComponent("b.jsonl")
        try prompt("a").write(to: a, atomically: false, encoding: .utf8)
        try stamp(a, now.addingTimeInterval(-60))
        try prompt("b").write(to: b, atomically: false, encoding: .utf8)
        try stamp(b, now.addingTimeInterval(-45))
        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        XCTAssertEqual(adapter.events(for: root).map(\.detail), ["b"], "the newest")
        XCTAssertEqual(adapter.transcriptReadCount, 1)

        try append(prompt("a2"), to: a)  // a is written again; b has been quiet for 45 s, so a takes over
        XCTAssertEqual(adapter.events(for: root).map(\.detail), ["a", "a2"])
        XCTAssertEqual(adapter.transcriptReadCount, 2)

        try stamp(a, now.addingTimeInterval(-60))  // a goes quiet; b is the newer file again, and is still cached
        XCTAssertEqual(adapter.events(for: root).map(\.detail), ["b"])
        XCTAssertEqual(adapter.transcriptReadCount, 2, "switching back is a stat, not a parse")

        try prompt("b2").write(to: b, atomically: true, encoding: .utf8)  // a rewrite (new inode) is still a full re-parse
        XCTAssertEqual(adapter.events(for: root).map(\.detail), ["b2"])
        XCTAssertEqual(adapter.transcriptReadCount, 3)
    }

    func testOnlyTheMostRecentlyServedTranscriptsStayCached() throws {
        let capacity = TranscriptCache<ClaudeTranscriptState>.capacity
        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        let files = try (0...capacity).map { i in
            let url = projectDir.appendingPathComponent("s\(i).jsonl")
            try prompt("\(i)").write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        for file in files { _ = adapter.events(fromSession: file) }
        XCTAssertEqual(adapter.transcriptReadCount, capacity + 1)
        _ = adapter.events(fromSession: files[1])
        XCTAssertEqual(adapter.transcriptReadCount, capacity + 1, "served after the first, so still cached")
        XCTAssertEqual(adapter.events(fromSession: files[0]).first?.detail, "0")
        XCTAssertEqual(adapter.transcriptReadCount, capacity + 2, "the least recently served was let go and is parsed again")
    }
}
