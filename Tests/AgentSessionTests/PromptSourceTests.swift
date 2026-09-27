//
//  PromptSourceTests.swift
//  AgentSessionTests
//
//  Who wrote each prompt, the whole text of prompts and replies, and one turn as a document.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

final class PromptSourceTests: XCTestCase {
    private func events(_ lines: [String]) -> [TimelineEvent] {
        var state = ClaudeTranscriptState()
        for line in lines { state.ingest(lineData: Data(line.utf8)) }
        return state.eventsResult
    }

    private func json(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private let notification = "<task-notification>\n<task-id>a57</task-id>\n<status>completed</status>\n<summary>Agent \"Research formats\" finished</summary>\n</task-notification>"

    /// Shapes read from real Claude Code transcripts: a notification queued while the agent works
    /// arrives as a `queue-operation` with no origin; one delivered idle is a user line with
    /// `origin.kind: "task-notification"`; a sub-agent's report is an `<agent-message>`.
    func testClaudeCodesOwnMessagesAreTurnsMarkedAsTheAgents() {
        let e = events([
            json(["type": "user", "timestamp": "2026-09-27T10:00:00Z", "origin": ["kind": "human"], "message": ["content": "Fix the parser\nand the tests too"]]),
            json(["type": "queue-operation", "operation": "remove", "reason": "absorbed_mid_turn", "timestamp": "2026-09-27T10:01:00Z", "content": notification]),
            json(["type": "queue-operation", "operation": "remove", "reason": "absorbed_mid_turn", "timestamp": "2026-09-27T10:02:00Z",
                  "content": "<agent-message from=\"a57\">\n[Subagent hand-back] The report follows:\n  ## Findings"]),
            json(["type": "user", "timestamp": "2026-09-27T10:03:00Z", "origin": ["kind": "task-notification"], "promptSource": "system", "message": ["content": notification]]),
            json(["type": "queue-operation", "operation": "remove", "reason": "absorbed_mid_turn", "timestamp": "2026-09-27T10:04:00Z", "content": "also check the docs"]),
            json(["type": "user", "timestamp": "2026-09-27T10:05:00Z", "message": ["content": "<local-command-stdout>ok</local-command-stdout>"]]),
        ])
        let prompts = e.filter { $0.kind == .userPrompt }
        XCTAssertEqual(prompts.map(\.detail), ["Fix the parser", "Agent \"Research formats\" finished", "Report from a sub-agent",
                                               "Agent \"Research formats\" finished", "also check the docs"])
        XCTAssertEqual(prompts.map(\.source), [.person, .agent, .agent, .agent, .person])
        XCTAssertEqual(prompts[0].fullText, "Fix the parser\nand the tests too", "the whole prompt, not its first line")
        XCTAssertEqual(prompts[1].fullText, notification)
    }

    func testRepliesKeepTheirWholeTextToTheCap() {
        let reply = "First line\n\nSecond paragraph."
        let e = events([json(["type": "assistant", "timestamp": "2026-09-27T10:00:00Z", "message": ["id": "m1", "content": [["type": "text", "text": reply]]]])])
        XCTAssertEqual(e.first?.fullText, reply)
        XCTAssertEqual(e.first?.detail, "First line")
        let huge = TimelineEvent(kind: .userPrompt, title: "You", detail: "x", filePath: nil, timestamp: "", fullText: String(repeating: "a", count: 30_000))
        XCTAssertEqual(huge.fullText?.count, TimelineEvent.fullTextCap + 1, "kept to the cap, with an ellipsis")
    }

    func testATurnReadsAsOneDocument() throws {
        let e = [
            TimelineEvent(kind: .userPrompt, title: "You", detail: "Fix the parser", filePath: nil, timestamp: "10:00", fullText: "Fix the parser\nand the tests too"),
            TimelineEvent(kind: .assistantText, title: "Claude", detail: "On it", filePath: nil, timestamp: "10:00", fullText: "On it.\nReading first."),
            TimelineEvent(kind: .fileEdit, title: "Edit", detail: "a.swift", filePath: "/w/a.swift", timestamp: "10:01"),
            TimelineEvent(kind: .fileEdit, title: "Edit", detail: "a.swift", filePath: "/w/a.swift", timestamp: "10:01"),
            TimelineEvent(kind: .toolUse, title: "Bash", detail: "swift test", filePath: nil, timestamp: "10:02", command: "swift test"),
            TimelineEvent(kind: .assistantText, title: "Claude", detail: "Done", filePath: nil, timestamp: "10:03", fullText: "Done."),
        ]
        let doc = try XCTUnwrap(TurnBoundary.turns(in: e).first).transcript(in: e)
        XCTAssertTrue(doc.hasPrefix("# Fix the parser\n\n*You · 10:00*\n\nFix the parser\nand the tests too\n"))
        XCTAssertTrue(doc.contains("On it.\nReading first.\n\n---\n\nDone."), "every reply, whole, in order")
        XCTAssertEqual(doc.components(separatedBy: "- `/w/a.swift`").count, 2, "a file edited twice is listed once")
        XCTAssertTrue(doc.contains("```sh\nswift test\n```"))
        XCTAssertEqual(TurnBoundary(start: 5, end: 9, prompt: "", timestamp: "").transcript(in: e), "")
    }
}
