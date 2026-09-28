//
//  TurnIdentityTests.swift
//  AgentSessionTests
//
//  Two turns opened by the same words are two turns, in every agent's transcript.
//
//  Created by David Sherlock on 9/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// A turn's id keys its checkpoint and its row. It must tell two turns opened by the same words
/// apart — "continue" typed on Monday and again on Tuesday at the same minute, or twice in a Grok
/// session, which records no time at all — and must not change when the transcript is read again.
final class TurnIdentityTests: XCTestCase {
    private func ids<S: TranscriptParsing>(_ state: S.Type, _ lines: [String]) -> [String] {
        var s = S()
        for line in lines { s.ingest(lineData: Data(line.utf8)) }
        return TurnBoundary.turns(in: s.eventsResult).map(\.id)
    }

    private func assertDistinctAndStable<S: TranscriptParsing>(
        _ state: S.Type, _ lines: [String], file: StaticString = #filePath, line: UInt = #line
    ) {
        let first = ids(state, lines)
        XCTAssertEqual(first.count, 2, "two turns", file: file, line: line)
        XCTAssertEqual(Set(first).count, 2, "the same words twice are two turns", file: file, line: line)
        XCTAssertEqual(ids(state, lines), first, "and read again, the same ids", file: file, line: line)
    }

    func testClaudeTurnsOnDifferentDaysAtTheSameMinute() {
        assertDistinctAndStable(
            ClaudeTranscriptState.self,
            [
                #"{"type":"user","origin":{"kind":"human"},"timestamp":"2026-09-27T10:00:05.000Z","message":{"content":"continue"}}"#,
                #"{"type":"user","origin":{"kind":"human"},"timestamp":"2026-09-28T10:00:40.000Z","message":{"content":"continue"}}"#,
            ])
    }

    func testCodexTurnsWithTheSameWords() {
        let msg =
            #"{"timestamp":"TS","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"continue"}]}}"#
        assertDistinctAndStable(
            CodexTranscriptState.self,
            [
                msg.replacingOccurrences(of: "TS", with: "2026-09-27T10:00:05.000Z"),
                msg.replacingOccurrences(of: "TS", with: "2026-09-28T10:00:40.000Z"),
            ])
    }

    func testGeminiTurnsWithTheSameWords() {
        assertDistinctAndStable(
            GeminiTranscriptState.self,
            [
                #"{"id":"u1","timestamp":"2026-09-27T10:00:05.000Z","type":"user","content":[{"text":"continue"}]}"#,
                #"{"id":"u2","timestamp":"2026-09-28T10:00:40.000Z","type":"user","content":[{"text":"continue"}]}"#,
            ])
    }

    func testGrokTurnsWithTheSameWords() {
        assertDistinctAndStable(
            GrokTranscriptState.self,
            [
                #"{"type":"user","content":[{"type":"text","text":"continue"}],"prompt_index":0}"#,
                #"{"type":"user","content":[{"type":"text","text":"continue"}],"prompt_index":1}"#,
            ])
    }

    /// Claude Code writes "[Request interrupted by user]" as a text block of a user line; it is its
    /// marker, not something the person typed.
    func testClaudesInterruptMarkerIsNotAPrompt() {
        var s = ClaudeTranscriptState()
        for line in [
            #"{"type":"user","origin":{"kind":"human"},"timestamp":"2026-09-28T10:00:00.000Z","message":{"content":"Fix it"}}"#,
            #"{"type":"user","timestamp":"2026-09-28T10:01:00.000Z","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#,
        ] { s.ingest(lineData: Data(line.utf8)) }
        XCTAssertEqual(s.eventsResult.filter { $0.kind == .userPrompt }.map(\.detail), ["Fix it"])
    }
}
