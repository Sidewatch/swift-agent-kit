//
//  ClaudeSubagentsTests.swift
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
final class ClaudeSubagentsTests: XCTestCase {
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
        ClaudeSubagents.folder(forSession: session).appendingPathComponent("agent-a000000000000002.jsonl")
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

    func testTheCallThatStartedASubagentCarriesWhatItDid() throws {
        let events = ClaudeCodeAdapter(projectsRoot: projectsRoot).events(for: root)
        let started = events.filter { $0.subagent != nil }
        XCTAssertEqual(started.map(\.title), ["Agent", "Agent"], "the two calls the meta files name, and no other event")
        XCTAssertEqual(started.map(\.toolUseID), ["toolu_0017", "toolu_0021"])
        XCTAssertEqual(
            started.first?.subagent, SubagentWork(type: "general-purpose", toolCalls: 1, editedFiles: [], isFinished: true),
            "the first ran one command and wrote nothing")
        XCTAssertEqual(
            started.last?.subagent,
            SubagentWork(
                type: "general-purpose", toolCalls: 3, editedFiles: ["/tmp/project/Sources/File56.py", "/tmp/project/Sources/File57.md"],
                isFinished: true),
            "the second ran one command and wrote two files, in that order")
        XCTAssertEqual(started.last?.filesWritten, ["/tmp/project/Sources/File56.py", "/tmp/project/Sources/File57.md"])
        XCTAssertEqual(started.last?.kind, .toolUse, "the call itself is not a file edit")
    }

    func testATurnsFilesIncludeItsSubagents() throws {
        let events = ClaudeCodeAdapter(projectsRoot: projectsRoot).events(for: root)
        let turns = TurnBoundary.turns(in: events)
        let files = turns.flatMap { $0.editedFiles(in: events) }
        XCTAssertTrue(Set(files).isSuperset(of: subagentFiles), "what the sub-agents wrote is the turn's")
        XCTAssertEqual(Set(files).count, files.count, "each file once")
        let turn = try XCTUnwrap(turns.first { $0.editedFiles(in: events).contains("/tmp/project/Sources/File56.py") })
        XCTAssertTrue(turn.transcript(in: events).contains("`/tmp/project/Sources/File57.md`"), "and in the turn's document")
        var away = AwayDigest()
        away.add(events)
        XCTAssertTrue(away.editedFiles.isSuperset(of: subagentFiles), "and in what happened while the person was away")
    }

    func testASubagentWithNoMetaFileHasNoCallToShowItUnder() throws {
        let folder = ClaudeSubagents.folder(forSession: session)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("agent-a000000000000002.meta.json"))
        let subagents = ClaudeSubagents()
        XCTAssertEqual(Array(subagents.work(forSession: session).keys), ["toolu_0017"])
        XCTAssertEqual(subagents.editedFiles(forSession: session), subagentFiles, "its files are still the session's")
    }

    func testAMetaFileThatChangesIsReadAgainUntilTheSubagentHasFinished() throws {
        let meta = ClaudeSubagents.folder(forSession: session).appendingPathComponent("agent-a000000000000002.meta.json")
        try #"{"agentType":"Explore","toolUseId":"toolu_0021","finished":false}"#.write(to: meta, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: meta.path)
        let subagents = ClaudeSubagents()
        XCTAssertEqual(subagents.work(forSession: session)["toolu_0021"]?.isFinished, false)
        XCTAssertEqual(subagents.work(forSession: session)["toolu_0021"]?.type, "Explore")
        try #"{"agentType":"Explore","toolUseId":"toolu_0021","finished":true}"#.write(to: meta, atomically: true, encoding: .utf8)
        XCTAssertEqual(subagents.work(forSession: session)["toolu_0021"]?.isFinished, true)
    }

    func testSeveralSessionsAreRememberedAtOnce() throws {
        let subagents = ClaudeSubagents()
        _ = subagents.editedFiles(forSession: session)
        let read = subagents.bytesRead
        let other = session.deletingLastPathComponent().appendingPathComponent("00000000-0000-0000-0000-000000000002.jsonl")
        _ = subagents.editedFiles(forSession: other)
        _ = subagents.editedFiles(forSession: session)
        XCTAssertEqual(subagents.bytesRead, read, "asking about another session does not forget this one")
    }

    func testOnlyTheSessionsOwnSubagentsAreRead() throws {
        XCTAssertEqual(ClaudeSubagents().editedFiles(forSession: session), subagentFiles)
        let other = session.deletingLastPathComponent().appendingPathComponent("00000000-0000-0000-0000-000000000002.jsonl")
        XCTAssertEqual(ClaudeSubagents().editedFiles(forSession: other), [], "a session with no sub-agents")
        // A file in the folder that is not a sub-agent's transcript is not read as one.
        try (edit("/tmp/project/notes.txt") + "\n").write(
            to: ClaudeSubagents.folder(forSession: session).appendingPathComponent("notes.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeSubagents().editedFiles(forSession: session), subagentFiles)
    }

    func testAFinishedSubagentIsNotReadAgainAndAGrowingOneOnlyForWhatWasAdded() throws {
        let edits = ClaudeSubagents()
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
        let edits = ClaudeSubagents()
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
        let edits = ClaudeSubagents()
        _ = edits.editedFiles(forSession: session)
        try FileManager.default.removeItem(at: writer)
        try (edit("/tmp/project/Sources/Other.swift") + "\n").write(to: writer, atomically: true, encoding: .utf8)
        XCTAssertEqual(edits.editedFiles(forSession: session), ["/tmp/project/Sources/Other.swift"])
    }

    func testAPollReadsNoMoreThanItsBudgetAndLaterPollsFinish() throws {
        let edits = ClaudeSubagents(budget: 1)  // one piece of one file a poll
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
            ClaudeSubagents.linesWithToolCalls(in: data, upTo: end).map { String(decoding: $0, as: UTF8.self) },
            ["{\"type\":\"tool_use\",\"n\":1}", "{\"type\":\"tool_use\",\"n\":2}"])
        XCTAssertEqual(ClaudeSubagents.linesWithToolCalls(in: Data(), upTo: 0), [])
    }

    func testAReadOnlyToolInASubagentIsNotAnEdit() throws {
        let read =
            #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Read","input":{"file_path":"/tmp/project/Sources/Seen.swift"}}]}}"#
        try append(read + "\n", to: writer)
        XCTAssertEqual(ClaudeSubagents().editedFiles(forSession: session), subagentFiles)
    }
}
