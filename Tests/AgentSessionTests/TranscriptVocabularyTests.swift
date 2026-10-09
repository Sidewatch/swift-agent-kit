//
//  TranscriptVocabularyTests.swift
//  AgentSessionTests
//
//  The words of Claude Code's filing that the lookup relies on: the `cwd` field, the record that
//  carries it, and the project folder's encoding rule.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// The words of Claude Code's filing that the lookup relies on: the `cwd` field, the record that
/// carries it, and the project folder's encoding rule. Each fails if the rule moves.
final class TranscriptVocabularyTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    private func transcript(_ name: String, _ lines: [String]) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    /// A transcript opens with the session's mode; the launch directory is the `cwd` of the first
    /// record that carries one, and later records (a `cd` away) do not change it.
    func testTheLaunchDirectoryIsTheCwdOfTheFirstRecordThatCarriesOne() throws {
        let locator = ClaudeSessionLocator(projectsRoot: scratch)
        let session = try transcript(
            "s.jsonl",
            [
                #"{"type":"mode"}"#,
                #"{"type":"user","cwd":"/a/b","timestamp":"2026-10-09T10:00:00.000Z","message":{"content":"hi"}}"#,
                #"{"type":"assistant","cwd":"/a/b/sub","message":{"content":[]}}"#,
            ])
        XCTAssertEqual(locator.launchDirectory(of: session), "/a/b")

        let fresh = try transcript("fresh.jsonl", [#"{"type":"mode"}"#])
        XCTAssertNil(locator.launchDirectory(of: fresh), "no record names a directory yet")
        let handle = try FileHandle(forWritingTo: fresh)
        handle.seekToEndOfFile()
        handle.write(Data(#"{"type":"user","cwd":"/c","message":{"content":"hi"}}"#.appending("\n").utf8))
        handle.closeFile()
        XCTAssertEqual(locator.launchDirectory(of: fresh), "/c", "an answer of nil is not remembered")

        let otherKey = try transcript("other.jsonl", [#"{"type":"user","workingDirectory":"/a/b","message":{"content":"hi"}}"#])
        XCTAssertNil(locator.launchDirectory(of: otherKey), "the field is `cwd`")
        let nested = try transcript("nested.jsonl", [#"{"type":"user","message":{"cwd":"/a/b","content":"hi"}}"#])
        XCTAssertNil(locator.launchDirectory(of: nested), "a top-level field of the record")
    }

    /// Running claude in a folder named `Tëst_Prøjéct 2.0` files its sessions under
    /// `T-st-Pr-j-ct-2-0`: every UTF-16 unit outside `[A-Za-z0-9]` is a dash, so a non-BMP
    /// character is two dashes; the path folded is the kernel's, `/private` and all.
    func testTheProjectFolderIsTheKernelPathFoldedPerUTF16Unit() throws {
        XCTAssertEqual(ClaudeSessionIndex.encode(URL(fileURLWithPath: "/Users/x/a.b_c d")), "-Users-x-a-b-c-d")
        let accented = ClaudeSessionIndex.candidateEncodings(of: URL(fileURLWithPath: "/Users/x/T\u{EB}st_Pr\u{F8}j\u{E9}ct 2.0"))
        XCTAssertTrue(accented.contains("-Users-x-T-st-Pr-j-ct-2-0"), "\(accented)")
        let emoji = ClaudeSessionIndex.candidateEncodings(of: URL(fileURLWithPath: "/Users/x/\u{1F600}"))
        XCTAssertTrue(emoji.contains("-Users-x---"), "two units, two dashes: \(emoji)")
        XCTAssertFalse(emoji.contains("-Users-x--"), "not one per character")

        let real = URL(fileURLWithPath: "/tmp/vocabulary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let kernel = "-private" + String(real.path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        XCTAssertTrue(ClaudeSessionIndex.candidateEncodings(of: real).contains(kernel), "an existing /tmp path keeps /private")
    }
}
