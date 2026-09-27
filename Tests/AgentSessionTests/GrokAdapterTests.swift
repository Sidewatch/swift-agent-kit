//
//  GrokAdapterTests.swift
//  AgentSessionTests
//
//  The Grok Build adapter against a sanitized real session, and its rules against Grok Build's own source.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

final class GrokAdapterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grok-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func state(_ lines: [String]) -> GrokTranscriptState {
        var state = GrokTranscriptState()
        for line in lines { state.ingest(lineData: Data(line.utf8)) }
        return state
    }

    private func user(_ text: String, _ extra: String = "") -> String {
        #"{"type":"user","content":[{"type":"text","text":TEXT}]EXTRA}"#
            .replacingOccurrences(of: "TEXT", with: String(data: try! JSONEncoder().encode(text), encoding: .utf8)!)
            .replacingOccurrences(of: "EXTRA", with: extra)
    }

    /// Writes a session folder under the project's bucket, returning its history file.
    @discardableResult
    private func session(_ project: String, _ id: String, lines: [String], kind: String? = nil, age: TimeInterval = 0) throws -> URL {
        let folder = root.appendingPathComponent("\(GrokSessionIndex.encode(project))/\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let history = folder.appendingPathComponent("chat_history.jsonl")
        try lines.joined(separator: "\n").appending("\n").write(to: history, atomically: true, encoding: .utf8)
        let summary = kind.map { #"{"info":{"id":"x","cwd":"p"},"session_kind":"\#($0)"}"# } ?? #"{"info":{"id":"x","cwd":"p"}}"#
        try summary.write(to: folder.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: history.path)
        return history
    }

    // Expectations below were read from the fixture by hand, not produced by the parser.

    func testARealSessionGivesThePromptsTheCallsTheirOutputAndTheReply() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "chat_history", withExtension: "jsonl", subdirectory: "Fixtures/Grok/session"))
        let e = GrokAdapter(sessionsRoot: root).events(fromSession: url)
        XCTAssertEqual(e.map(\.kind), [.userPrompt, .assistantText, .toolUse, .toolUse, .toolUse, .userPrompt])
        XCTAssertEqual(e.filter { $0.kind == .userPrompt }.map(\.detail),
                       ["Read hello.py and summarize what it prints without editing files.", "Here is a screenshot for reference."],
                       "the injected <user_info> context is not a prompt; an image part adds no text")
        XCTAssertEqual(e[1].detail, "I'll read the file first.")
        XCTAssertEqual(e[2].title, "read_file")
        XCTAssertEqual(e[2].result, "print(\"hello from the grok fixture\")\n", "a tool_result attaches to its call")
        XCTAssertEqual(e[3].title, "web_search")
        XCTAssertEqual(e[3].detail, "python print builtin")
        XCTAssertEqual(e[4].command, "python3 hello.py")
        XCTAssertEqual(e[4].result, "hello from the grok fixture\n")
        XCTAssertEqual(e[4].model, "grok-4.5")
    }

    /// `conversation.rs`: only an item WITHOUT `synthetic_reason` (or an interjection) is the
    /// person's, and `prompt_index` alone does not make one (Grok's wake-ups carry it too). Typed
    /// text sits inside `<user_query>`, with a lead-in after an interrupt or mid-turn.
    func testOnlyWhatThePersonTypedIsAPrompt() {
        let lines = [
            user("<user_info>\nOS Version: macos\n</user_info>"),
            user("<user_query>\nFix the parser\n</user_query>", #","prompt_index":0"#),
            user("summary of earlier turns", #","synthetic_reason":"compaction_meta""#),
            user("Background task finished", #","synthetic_reason":"task_completed","prompt_index":1"#),
            user("The user interrupted the previous turn:\n<user_query>\nStop, use tabs\n</user_query>\nIf the user is asking…", #","prompt_index":2"#),
            user("The user sent a message while you were working:\n<user_query>\nalso the tests\n</user_query>", #","synthetic_reason":"interjection""#),
            user("typed in verbatim mode", #","prompt_index":3"#),
            user("x", #","synthetic_reason":"some_future_reason""#),
        ]
        XCTAssertEqual(state(lines).eventsResult.map(\.detail), ["Fix the parser", "Stop, use tabs", "also the tests", "typed in verbatim mode"])
    }

    /// Edits across the toolsets (`xai-grok-agent/src/config.rs`); a relative path is the
    /// session cwd's, which is the project the session was found under.
    func testEditsAcrossToolsetsResolveUnderTheProject() throws {
        func call(_ id: String, _ name: String, _ args: String) -> String {
            #"{"id":"ID","name":"NAME","arguments":ARGS}"#.replacingOccurrences(of: "ID", with: id).replacingOccurrences(of: "NAME", with: name)
                .replacingOccurrences(of: "ARGS", with: String(data: try! JSONEncoder().encode(args), encoding: .utf8)!)
        }
        let calls = [call("1", "search_replace", #"{"file_path":"src/a.rs","old_string":"x","new_string":"let answer = 42;"}"#),
                     call("2", "write", #"{"file_path":"/abs/b.md","content":"hi"}"#),
                     call("3", "apply_patch", #"{"patch":"*** Begin Patch\n*** Add File: c.txt\n+x\n*** End Patch"}"#),
                     call("4", "run_terminal_command", #"{"command":"cargo test","description":"run tests"}"#),
                     call("5", "hashline_edit", #"{"file_path":"d.rs","edits":[]}"#)]
        let project = "/work/app"
        try session(project, "s1", lines: [#"{"type":"assistant","content":"","tool_calls":[\#(calls.joined(separator: ","))],"model_id":"grok-4.5"}"#,
                                           #"{"type":"tool_result","tool_call_id":"4","content":"ok"}"#])
        let adapter = GrokAdapter(sessionsRoot: root)
        let e = adapter.events(for: URL(fileURLWithPath: project))
        XCTAssertEqual(e.compactMap(\.filePath), ["/work/app/src/a.rs", "/abs/b.md", "/work/app/c.txt", "/work/app/d.rs"])
        XCTAssertEqual(e.first?.anchor, "let answer = 42;")
        XCTAssertEqual(e.first { $0.command != nil }?.command, "cargo test")
        XCTAssertEqual(e.first { $0.command != nil }?.result, "ok")
        XCTAssertEqual(adapter.summary(for: URL(fileURLWithPath: project))?.editedFiles,
                       ["/work/app/src/a.rs", "/abs/b.md", "/work/app/c.txt", "/work/app/d.rs"])
    }

    /// `paths.rs`: the cwd is `urlencoding::encode`d — only `A–Z a–z 0–9 - _ . ~` survive.
    func testTheProjectFolderIsTheCwdPercentEncoded() {
        XCTAssertEqual(GrokSessionIndex.encode("/work/my app/é~_.-"), "%2Fwork%2Fmy%20app%2F%C3%A9~_.-")
    }

    /// The newest top-level session wins; a sub-agent's (`session_kind` `subagent…`) does not; a
    /// cwd too long for a folder name is found through the bucket's `.cwd` file.
    func testTheIndexFindsAProjectsNewestTopLevelSession() throws {
        let project = "/work/app"
        try session(project, "old", lines: [user("a")], age: 600)
        let newest = try session(project, "new", lines: [user("b")], age: 60)
        try session(project, "mid", lines: [user("c")], age: 300)
        for n in 0..<10 { try session(project, "older-\(n)-\(UUID().uuidString.prefix(6))", lines: [user("d")], age: 120 + Double(n)) }
        try session(project, "child", lines: [user("e")], kind: "subagent", age: 1)
        try session(project, "fork", lines: [user("f")], kind: "subagent_fork", age: 2)
        let index = GrokSessionIndex(sessionsRoot: root)
        XCTAssertEqual(index.latestSession(for: URL(fileURLWithPath: project))?.deletingLastPathComponent().lastPathComponent,
                       newest.deletingLastPathComponent().lastPathComponent)
        XCTAssertNil(index.latestSession(for: URL(fileURLWithPath: "/work/none")))

        let long = "/work/" + String(repeating: "deep/", count: 60) + "proj"
        let bucket = root.appendingPathComponent("proj-0123456789abcdef", isDirectory: true)
        try FileManager.default.createDirectory(at: bucket.appendingPathComponent("s"), withIntermediateDirectories: true)
        try long.write(to: bucket.appendingPathComponent(".cwd"), atomically: true, encoding: .utf8)
        try user("g").write(to: bucket.appendingPathComponent("s/chat_history.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertEqual(index.latestSession(for: URL(fileURLWithPath: long))?.deletingLastPathComponent().lastPathComponent, "s")
    }

    /// `usage_file.rs` / `signals.rs`: usage lives beside the history; the cost is Grok's own
    /// (`costUsdTicks`, 10¹⁰ per dollar), not a price this library guessed.
    func testUsageIsReadFromTheSidecarsGrokWrites() throws {
        let project = "/work/app"
        let history = try session(project, "s1", lines: [user("a")])
        let folder = history.deletingLastPathComponent()
        let adapter = GrokAdapter(sessionsRoot: root)
        XCTAssertNil(adapter.usage(for: URL(fileURLWithPath: project)), "no sidecars yet, no usage")
        try #"{"contextTokensUsed":12000,"contextWindowTokens":200000,"primaryModelId":"grok-4.5"}"#
            .write(to: folder.appendingPathComponent("signals.json"), atomically: true, encoding: .utf8)
        try #"{"sessionId":"s1","session":{"inputTokens":50000,"outputTokens":900,"costUsdTicks":12345000000},"turns":[]}"#
            .write(to: folder.appendingPathComponent("usage.json"), atomically: true, encoding: .utf8)
        let usage = try XCTUnwrap(adapter.usage(for: URL(fileURLWithPath: project)))
        XCTAssertEqual(usage.contextTokens, 12000)
        XCTAssertEqual(usage.contextLimit, 200000)
        XCTAssertEqual(usage.outputTokens, 900)
        XCTAssertEqual(usage.costUSD, 1.2345, accuracy: 1e-9)
    }
}
