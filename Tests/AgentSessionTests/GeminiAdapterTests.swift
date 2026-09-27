//
//  GeminiAdapterTests.swift
//  AgentSessionTests
//
//  The Gemini adapter against a sanitized real session, and its rules against Gemini's own source.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

final class GeminiAdapterTests: XCTestCase {
    private func state(_ lines: [String]) -> GeminiTranscriptState {
        var state = GeminiTranscriptState()
        for line in lines { state.ingest(lineData: Data(line.utf8)) }
        return state
    }

    private let meta =
        #"{"sessionId":"s","projectHash":"h","startTime":"2026-09-27T10:00:00.000Z","lastUpdated":"2026-09-27T10:00:00.000Z","kind":"main"}"#
    private func user(_ id: String, _ text: String) -> String {
        #"{"id":"ID","timestamp":"2026-09-27T10:00:01.000Z","type":"user","content":[{"text":"TEXT"}]}"#
            .replacingOccurrences(of: "ID", with: id).replacingOccurrences(of: "TEXT", with: text)
    }
    private func reply(_ id: String, _ text: String, tokens: String = "null") -> String {
        #"{"id":"ID","timestamp":"2026-09-27T10:00:02.000Z","type":"gemini","content":"TEXT","tokens":TOKENS,"model":"gemini-3-pro"}"#
            .replacingOccurrences(of: "ID", with: id).replacingOccurrences(of: "TEXT", with: text).replacingOccurrences(
                of: "TOKENS", with: tokens)
    }

    // Expectations below were read from the fixture by hand, not produced by the parser.

    func testARealSessionGivesThePromptTheShellCallAndTheReply() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "session-v040", withExtension: "jsonl", subdirectory: "Fixtures/Gemini"))
        let e = GeminiAdapter(runtimeRoots: []).events(fromSession: url)
        XCTAssertEqual(e.map(\.kind), [.userPrompt, .toolUse, .assistantText])
        XCTAssertEqual(e[0].detail, "Say hello and list files.")
        XCTAssertEqual(e[1].command, "ls -F")
        XCTAssertEqual(e[1].result, "AgentSessions/\nREADME.md", "what the person was shown, not the raw function response")
        XCTAssertEqual(e[2].detail, "Hello! I listed the files.")
        var s = GeminiTranscriptState()
        for line in try Data(contentsOf: url).split(separator: UInt8(ascii: "\n")) { s.ingest(lineData: Data(line)) }
        let usage = try XCTUnwrap(s.usageResult)
        XCTAssertEqual(usage.outputTokens, 81 + 147)
        XCTAssertEqual(usage.contextTokens, 12216, "the last reply's total")
        XCTAssertEqual(usage.costUSD, 0, "no Google prices: no cost rather than a guessed one")
    }

    /// `pushMessage` re-appends a reply under its id as tokens and tool results arrive; the
    /// loader keeps the LAST record for an id, in the place the id first appeared.
    func testARecordWithAKnownIdReplacesThatMessage() {
        let s = state([
            meta, user("u1", "Go"), reply("g1", "Working"), user("u2", "Next"),
            reply("g1", "Done", tokens: #"{"input":100,"output":5,"cached":40,"thoughts":3,"tool":0,"total":108}"#),
        ])
        XCTAssertEqual(s.eventsResult.map(\.detail), ["Go", "Done", "Next"])
        XCTAssertEqual(s.eventsResult[1].usage?.input, 60, "input less the cached part")
        XCTAssertEqual(s.eventsResult[1].usage?.output, 8, "thinking is billed as output")
    }

    /// `$rewindTo` drops that message and everything after it; an unknown id drops everything.
    func testRewindDropsTheMessageAndWhatFollows() {
        XCTAssertEqual(
            state([meta, user("u1", "A"), reply("g1", "B"), user("u2", "C"), #"{"$rewindTo":"g1"}"#, user("u3", "D")])
                .eventsResult.map(\.detail), ["A", "D"])
        XCTAssertEqual(state([meta, user("u1", "A"), #"{"$rewindTo":"nope"}"#]).eventsResult.count, 0)
    }

    /// A `$set` carrying `messages` is a checkpoint (`/compress`): it replaces every message.
    func testACheckpointReplacesTheMessages() {
        let checkpoint =
            #"{"$set":{"messages":[{"id":"c1","timestamp":"2026-09-27T10:05:00.000Z","type":"user","content":"Summary so far"}]}}"#
        XCTAssertEqual(state([meta, user("u1", "A"), reply("g1", "B"), checkpoint]).eventsResult.map(\.detail), ["Summary so far"])
        XCTAssertEqual(
            state([meta, user("u1", "A"), #"{"$set":{"lastUpdated":"2026-09-27T10:05:00.000Z"}}"#]).eventsResult.count, 1,
            "a plain metadata update touches no message")
    }

    /// `isIgnoredUserContent` (`utils/sessionUtils.ts`); `displayContent` is what was typed.
    func testCommandsHelpAndInjectedContextAreNotPrompts() {
        for text in ["/compress", "?", "<session_context>cwd</session_context>", "<hook_context>x</hook_context>", " "] {
            XCTAssertFalse(GeminiTranscriptState.isTypedByPerson(text.trimmingCharacters(in: .whitespaces)), text)
        }
        XCTAssertTrue(GeminiTranscriptState.isTypedByPerson("Fix the /usr path"))
        let typed =
            #"{"id":"u1","timestamp":"t","type":"user","content":[{"text":"@a.swift expanded file body"}],"displayContent":[{"text":"explain @a.swift"}]}"#
        XCTAssertEqual(state([typed]).eventsResult.map(\.detail), ["explain @a.swift"])
        XCTAssertEqual(state([#"{"id":"i1","timestamp":"t","type":"info","content":"Switched model"}"#]).eventsResult.count, 0)
    }

    /// `replace` / `write_file` edit files; a relative path is the project root's
    /// (`tools/edit.ts`); a failed call reads as one.
    func testEditsResolveUnderTheProjectAndFailuresShow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gemini-edits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = URL(fileURLWithPath: "/work/app")
        let chats = root.appendingPathComponent("tmp/app/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try #"{"projects":{"/work/app":"app"}}"#.write(to: root.appendingPathComponent("projects.json"), atomically: true, encoding: .utf8)
        let calls =
            #"{"id":"g1","timestamp":"t","type":"gemini","content":"","model":"gemini-3-pro","toolCalls":["#
            + #"{"id":"c1","name":"replace","args":{"file_path":"src/a.swift","old_string":"x","new_string":"let answer = 42"},"status":"success","timestamp":"t"},"#
            + #"{"id":"c2","name":"write_file","args":{"file_path":"/abs/b.md","content":"hi"},"status":"success","timestamp":"t"},"#
            + #"{"id":"c3","name":"run_shell_command","args":{"command":"swift test"},"status":"error","timestamp":"t","result":[{"functionResponse":{"id":"c3","name":"run_shell_command","response":{"error":"exit 1"}}}]},"#
            + #"{"id":"c4","name":"run_shell_command","args":{"command":"make"},"status":"error","timestamp":"t","resultDisplay":"make: *** No targets."}]}"#
        try [meta, calls].joined(separator: "\n").write(
            to: chats.appendingPathComponent("session-2026-09-27T10-00-abcd1234.jsonl"), atomically: true, encoding: .utf8)
        let adapter = GeminiAdapter(runtimeRoots: [root])
        let e = adapter.events(for: project)
        XCTAssertEqual(e.compactMap(\.filePath), ["/work/app/src/a.swift", "/abs/b.md"])
        XCTAssertEqual(e.first?.anchor, "let answer = 42")
        XCTAssertEqual(adapter.summary(for: project)?.editedFiles, ["/work/app/src/a.swift", "/abs/b.md"])
        XCTAssertEqual(e[2].result, "exit 1")
        XCTAssertEqual(e[2].resultIsError, true, "an error response")
        XCTAssertEqual(e[3].result, "make: *** No targets.")
        XCTAssertEqual(e[3].resultIsError, true, "an `error` status, whatever the output says")
        XCTAssertEqual(e.first?.resultIsError, false)
    }

    /// Chats are found by the registry's slug, or the pre-registry SHA-256 folder; the newest
    /// top-level `session-*.jsonl` wins, and a sub-agent's (in a folder) is not the conversation.
    func testTheIndexFindsAProjectsNewestSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gemini-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"projects":{"/work/app":"app"}}"#.write(
            to: root.appendingPathComponent("projects.json").creatingParent(), atomically: true, encoding: .utf8)
        func session(_ id: String, _ name: String, age: TimeInterval) throws -> URL {
            let url = root.appendingPathComponent("tmp/\(id)/chats/\(name)").creatingParent()
            try meta.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        // Older sessions sort both before and after the newest, so no listing order can pass for recency.
        _ = try session("app", "session-2026-01-01T10-00-aaaa.jsonl", age: 600)
        let newest = try session("app", "session-2026-05-01T10-00-mmmm.jsonl", age: 60)
        _ = try session("app", "session-2026-09-01T10-00-zzzz.jsonl", age: 300)
        for n in 0..<12 {
            _ = try session("app", "session-2026-02-0\(n % 9 + 1)T10-00-\(UUID().uuidString.prefix(8)).jsonl", age: 120 + Double(n))
        }
        _ = try session("app", "parent-id/sub.jsonl", age: 1)
        _ = try session("app", "session-legacy.json", age: 0)
        let legacy = try session(GeminiSessionIndex.legacyID("/work/old"), "session-a.jsonl", age: 0)
        let index = GeminiSessionIndex(runtimeRoots: [root])
        XCTAssertEqual(index.latestSession(for: URL(fileURLWithPath: "/work/app"))?.lastPathComponent, newest.lastPathComponent)
        XCTAssertEqual(index.latestSession(for: URL(fileURLWithPath: "/work/old"))?.lastPathComponent, legacy.lastPathComponent)
        XCTAssertNil(index.latestSession(for: URL(fileURLWithPath: "/work/none")))
        XCTAssertEqual(
            GeminiSessionIndex.legacyID("/a"), "6a50dc8584134c7de537c0052ff6d236bf874355e050c90523e0c5ff2a543a28",
            "`shasum -a 256` of the path, as Gemini's getFilePathHash")
    }
}

private extension URL {
    /// Creates this file's folder, returning the URL.
    func creatingParent() -> URL {
        try? FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
