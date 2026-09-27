//
//  CodexAdapterTests.swift
//  AgentSessionTests
//
//  The Codex adapter against sanitized real rollouts, and its rules against Codex's own source.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

final class CodexAdapterTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures/Codex"))
    }

    private func events(_ name: String) throws -> [TimelineEvent] {
        CodexAdapter(sessionsRoot: URL(fileURLWithPath: "/nonexistent")).events(fromSession: try fixture(name))
    }

    // Expectations below were read from the fixture files by hand, not produced by the parser.

    func testARealRolloutGivesThePromptTheReplyAndTheShellCalls() throws {
        let e = try events("rollout-small")
        XCTAssertEqual(e.filter { $0.kind == .userPrompt }.map(\.detail), ["List the files"],
                       "the injected-context message (its only kind is not user.*) is not a prompt")
        XCTAssertEqual(e.filter { $0.kind == .assistantText }.map(\.detail), ["Found 2 files."])
        let shells = e.filter { $0.command == "ls" }
        XCTAssertEqual(shells.count, 2, "the function call and the custom tool call, each `shell` with argv [ls]")
        XCTAssertEqual(shells.first { $0.toolUseID == "call-2" }?.result, "a.txt\n", "a {text} output attaches to its call")
        XCTAssertEqual(shells.first { $0.toolUseID == "call-1" }?.result, "a.txt\nb.txt\n", "a list output attaches to its call")
    }

    func testInjectedEnvironmentContextIsNotAPrompt() throws {
        let e = try events("rollout-large")
        XCTAssertEqual(e.filter { $0.kind == .userPrompt }.map(\.detail), ["Start", "Step 1", "Step 2", "Step 3", "Step 4", "Step 5"])
        XCTAssertEqual(e.filter { $0.kind == .assistantText }.count, 7)
    }

    func testUsageIsTheLatestCumulativeCountAndUnpricedModelsCostNothing() throws {
        let url = try fixture("rollout-rate-limit")
        let adapter = CodexAdapter(sessionsRoot: URL(fileURLWithPath: "/nonexistent"))
        _ = adapter.events(fromSession: url)
        var state = CodexTranscriptState()
        for line in try Data(contentsOf: url).split(separator: UInt8(ascii: "\n")) { state.ingest(lineData: Data(line)) }
        let usage = try XCTUnwrap(state.usageResult, "a token_count with info: null is skipped, not fatal")
        XCTAssertEqual(usage.outputTokens, 182)
        XCTAssertEqual(usage.costUSD, 0, "no OpenAI prices: no cost rather than a guessed one")
    }

    func testLinesInAnotherShapeAreIgnored() throws {
        XCTAssertTrue(try events("rollout-schema-drift").isEmpty)
    }

    /// `codex-rs/core/src/context/`: a fragment is Codex's when the text is one marked element,
    /// AGENTS.md instructions, or one of its exact warnings; the person's otherwise.
    func testCodexsInjectedContextIsRecognisedAndPromptsAreNot() {
        XCTAssertTrue(CodexTranscriptState.isContextualText("<environment_context><cwd>/p</cwd></environment_context>"))
        XCTAssertTrue(CodexTranscriptState.isContextualText("  <turn_aborted>\nstopped\n</turn_aborted>\n"))
        XCTAssertTrue(CodexTranscriptState.isContextualText("# AGENTS.md instructions for /p\n<INSTRUCTIONS>x</INSTRUCTIONS>"))
        XCTAssertTrue(CodexTranscriptState.isContextualText("Warning: apply_patch was requested via exec_command. Use the apply_patch tool instead of exec_command."))
        XCTAssertFalse(CodexTranscriptState.isContextualText("Warning: the build fails on CI, fix it"))
        XCTAssertFalse(CodexTranscriptState.isContextualText("<b>bold</b> should render"))
        XCTAssertFalse(CodexTranscriptState.isContextualText("Refactor the parser"))
        let content: [[String: Any]] = [["type": "input_text", "text": "<environment_context>x</environment_context>"]]
        XCTAssertTrue(CodexTranscriptState.isTypedByPerson(["internal_chat_message_metadata_passthrough": ["content_item_kinds": ["user.input"]]], content: content),
                      "a current rollout's kinds decide over the text")
        XCTAssertFalse(CodexTranscriptState.isTypedByPerson([:], content: content))
    }

    /// `codex-rs/apply-patch/src/parser.rs` markers; a relative path is the session's cwd's.
    func testAPatchIsTheFilesItEditsUnderTheSessionsDirectory() throws {
        let patch = "*** Begin Patch\n*** Update File: src/a.swift\n@@\n-x\n+y\n*** Add File: b.md\n+hi\n*** Delete File: /abs/c.txt\n*** End Patch"
        XCTAssertEqual(CodexTranscriptState.patchedPaths(patch), ["src/a.swift", "b.md", "/abs/c.txt"])
        var state = CodexTranscriptState()
        for line in [
            #"{"type":"session_meta","payload":{"cwd":"/work/app","source":"cli"}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"c1","name":"apply_patch","input":"*** Begin Patch\n*** Update File: src/a.swift\n*** End Patch"}}"#,
        ] { state.ingest(lineData: Data(line.utf8)) }
        XCTAssertEqual(state.eventsResult.map(\.filePath), ["/work/app/src/a.swift"])
        XCTAssertEqual(state.eventsResult.first?.kind, .fileEdit)
        XCTAssertEqual(state.summaryResult.editedFiles, ["/work/app/src/a.swift"])
    }

    func testShellCommandsReadAsTheScriptTheyRun() {
        XCTAssertEqual(CodexTranscriptState.shellCommand("git status"), "git status", "exec_command's cmd / shell_command's command")
        XCTAssertEqual(CodexTranscriptState.shellCommand(["bash", "-lc", "swift test"]), "swift test")
        XCTAssertEqual(CodexTranscriptState.shellCommand(["ls", "-la"]), "ls -la")
        XCTAssertEqual(CodexTranscriptState.outputText(#"{"output":"boom","metadata":{"exit_code":1}}"#).0, "boom")
        XCTAssertTrue(CodexTranscriptState.outputText(#"{"output":"boom","metadata":{"exit_code":1}}"#).1, "a non-zero exit is a failure")
    }

    /// Codex files sessions by date: the index finds a project's newest rollout by its
    /// `session_meta.cwd`, and a sub-agent's rollout (an object `source`) is not the conversation.
    func testTheIndexFindsAProjectsNewestTopLevelRollout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("2026/09/27", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        func write(_ name: String, cwd: String, source: String, age: TimeInterval) throws -> URL {
            let url = day.appendingPathComponent(name)
            try #"{"type":"session_meta","payload":{"cwd":"CWD","source":SOURCE}}"#
                .replacingOccurrences(of: "CWD", with: cwd).replacingOccurrences(of: "SOURCE", with: source)
                .write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        _ = try write("rollout-old.jsonl", cwd: "/work/app", source: #""cli""#, age: 600)
        let newest = try write("rollout-new.jsonl", cwd: "/work/app", source: #""cli""#, age: 60)
        _ = try write("rollout-sub.jsonl", cwd: "/work/app", source: #"{"subagent":"review"}"#, age: 1)
        _ = try write("rollout-other.jsonl", cwd: "/work/other", source: #""cli""#, age: 0)
        let index = CodexSessionIndex(sessionsRoot: root)
        XCTAssertEqual(index.latestRollout(for: URL(fileURLWithPath: "/work/app"))?.lastPathComponent, newest.lastPathComponent)
        XCTAssertNil(index.latestRollout(for: URL(fileURLWithPath: "/work/none")))
    }
}
