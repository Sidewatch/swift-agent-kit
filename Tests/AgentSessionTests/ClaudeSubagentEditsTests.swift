//
//  ClaudeSubagentEditsTests.swift
//  AgentSessionTests
//
//  A Claude Code session's edited files include what its sub-agents wrote.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// Over `Fixtures/Claude`: a sanitized real session (Claude Code 2.1.316) whose transcript edits
/// File1 to File55, with two sub-agents beside it, one that edited nothing and one that wrote
/// File56.py and File57.md. Read from the fixture files by hand.
final class ClaudeSubagentEditsTests: XCTestCase {
    private var projectsRoot: URL!
    private var session: URL!
    private let root = URL(fileURLWithPath: "/tmp/project")
    private let subagentFiles: Set<String> = ["/tmp/project/Sources/File56.py", "/tmp/project/Sources/File57.md"]

    override func setUpWithError() throws {
        projectsRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "subagent-edits-\(UUID().uuidString)", isDirectory: true)
        let projectDir = projectsRoot.appendingPathComponent("-tmp-project", isDirectory: true)
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "Claude", withExtension: nil, subdirectory: "Fixtures"))
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: projectDir)
        session = projectDir.appendingPathComponent("00000000-0000-0000-0000-000000000001.jsonl")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: projectsRoot) }

    private var writer: URL {
        ClaudeSubagentEdits.folder(forSession: session).appendingPathComponent("agent-a000000000000002.jsonl")
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func edit(_ path: String) -> String {
        #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Write","input":{"file_path":"PATH"}}]}}"#
            .replacingOccurrences(of: "PATH", with: path)
    }

    func testASessionsEditedFilesIncludeWhatItsSubagentsWrote() throws {
        let edited = try XCTUnwrap(ClaudeCodeAdapter(projectsRoot: projectsRoot).summary(for: root)?.editedFiles)
        XCTAssertEqual(edited.count, 57, "55 in the session's own transcript, two only in a sub-agent's")
        XCTAssertTrue(edited.isSuperset(of: subagentFiles))
        XCTAssertTrue(edited.contains("/tmp/project/Sources/File1.md"), "and its own")
    }

    func testOnlyTheSessionsOwnSubagentsAreRead() throws {
        XCTAssertEqual(ClaudeSubagentEdits().editedFiles(forSession: session), subagentFiles)
        let other = session.deletingLastPathComponent().appendingPathComponent("00000000-0000-0000-0000-000000000002.jsonl")
        XCTAssertEqual(ClaudeSubagentEdits().editedFiles(forSession: other), [], "a session with no sub-agents")
        // A file in the folder that is not a sub-agent's transcript is not read as one.
        try (edit("/tmp/project/notes.txt") + "\n").write(
            to: ClaudeSubagentEdits.folder(forSession: session).appendingPathComponent("notes.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeSubagentEdits().editedFiles(forSession: session), subagentFiles)
    }

    func testAFinishedSubagentIsNotReadAgainAndAGrowingOneOnlyForWhatWasAdded() throws {
        let edits = ClaudeSubagentEdits()
        _ = edits.editedFiles(forSession: session)
        let first = edits.bytesRead
        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(edits.editedFiles(forSession: session), subagentFiles)
        XCTAssertEqual(edits.bytesRead, first, "nothing changed: nothing read")

        let added = edit("/tmp/project/Sources/Added.swift") + "\n"
        try append(added, to: writer)
        XCTAssertEqual(edits.editedFiles(forSession: session), subagentFiles.union(["/tmp/project/Sources/Added.swift"]))
        XCTAssertEqual(edits.bytesRead, first + added.utf8.count, "only the appended line")
    }

    func testALineStillBeingWrittenIsReadOnceItIsWhole() throws {
        let edits = ClaudeSubagentEdits()
        _ = edits.editedFiles(forSession: session)
        let line = edit("/tmp/project/Sources/Half.swift")
        try append(edit("/tmp/project/Sources/Whole.swift") + "\n" + String(line.prefix(60)), to: writer)
        XCTAssertEqual(
            edits.editedFiles(forSession: session), subagentFiles.union(["/tmp/project/Sources/Whole.swift"]),
            "the whole line before it is read; half a line is not a line")
        try append(String(line.dropFirst(60)) + "\n", to: writer)
        XCTAssertTrue(edits.editedFiles(forSession: session).contains("/tmp/project/Sources/Half.swift"))
    }

    func testAReplacedTranscriptIsReadFromItsStart() throws {
        let edits = ClaudeSubagentEdits()
        _ = edits.editedFiles(forSession: session)
        try FileManager.default.removeItem(at: writer)
        try (edit("/tmp/project/Sources/Other.swift") + "\n").write(to: writer, atomically: true, encoding: .utf8)
        XCTAssertEqual(edits.editedFiles(forSession: session), ["/tmp/project/Sources/Other.swift"])
    }

    func testAPollReadsNoMoreThanItsBudgetAndLaterPollsFinish() throws {
        let edits = ClaudeSubagentEdits(budget: 1)  // one piece of one file a poll
        _ = edits.editedFiles(forSession: session)
        XCTAssertTrue([3028, 5112].contains(edits.bytesRead), "the first poll reads one of the two transcripts: \(edits.bytesRead)")
        XCTAssertEqual(edits.editedFiles(forSession: session), subagentFiles, "the next poll takes the other")
        XCTAssertEqual(edits.bytesRead, 3028 + 5112)
        _ = edits.editedFiles(forSession: session)
        XCTAssertEqual(edits.bytesRead, 3028 + 5112, "and then nothing is read again")
    }

    func testOnlyLinesWithAToolCallAreCutOut() {
        let text =
            "{\"a\":1}\n{\"type\":\"tool_use\",\"n\":1}\n{\"text\":\"an escaped \\\"tool_use\\\" is prose\"}\n{\"type\":\"tool_use\",\"n\":2}\nhalf {\"type\":\"tool_use\""
        let data = Data(text.utf8)
        let end = data.lastIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? 0
        XCTAssertEqual(
            ClaudeSubagentEdits.linesWithToolCalls(in: data, upTo: end).map { String(decoding: $0, as: UTF8.self) },
            ["{\"type\":\"tool_use\",\"n\":1}", "{\"type\":\"tool_use\",\"n\":2}"])
        XCTAssertEqual(ClaudeSubagentEdits.linesWithToolCalls(in: Data(), upTo: 0), [])
    }

    func testAReadOnlyToolInASubagentIsNotAnEdit() throws {
        let read =
            #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Read","input":{"file_path":"/tmp/project/Sources/Seen.swift"}}]}}"#
        try append(read + "\n", to: writer)
        XCTAssertEqual(ClaudeSubagentEdits().editedFiles(forSession: session), subagentFiles)
    }
}
