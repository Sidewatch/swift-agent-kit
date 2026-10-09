//
//  ProgramStatusReportTests.swift
//  AgentStatusTests
//
//  The OSC 7501 vocabulary, pinned word by word against the protocol.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

/// The Program Status Protocol's words are someone else's vocabulary: a program writes them on
/// the wire and the terminal maps them by raw value. Each is pinned here, so renaming a case or
/// its raw value fails before it silently stops matching.
final class ProgramStatusReportTests: XCTestCase {
    func testTheStateWordsAreTheProtocolsExactlyAndNothingElse() {
        XCTAssertEqual(ProgramStatusState.allCases.map(\.rawValue), ["idle", "working", "done", "blocked", "error"])
        for word in ["idle", "working", "done", "blocked", "error"] {
            XCTAssertNotNil(ProgramStatusState(rawValue: word), word)
        }
        XCTAssertNil(ProgramStatusState(rawValue: "busy"), "a word the protocol does not use maps to nothing")
        XCTAssertNil(ProgramStatusState(rawValue: "Working"), "the protocol is lower-case")
    }

    func testTheKindWordsAreTheProtocolsExactly() {
        XCTAssertEqual(ProgramStatusKind.allCases.map(\.rawValue), ["permission", "question", "auth"])
        XCTAssertNil(ProgramStatusKind(rawValue: "approval"))
    }

    func testAReportKeepsEveryFieldAndDefaultsToTheRootRecord() {
        let report = ProgramStatusReport(
            state: .blocked, kind: .permission, progress: 40, app: "claude", title: "Bash", message: "rm -rf build?")
        XCTAssertEqual(report.id, "", "no id names the root record")
        XCTAssertEqual(report.state, .blocked)
        XCTAssertEqual(report.kind, .permission)
        XCTAssertEqual(report.progress, 40)
        XCTAssertEqual(report.app, "claude")
        XCTAssertEqual(report.title, "Bash")
        XCTAssertEqual(report.message, "rm -rf build?")
        XCTAssertEqual(ProgramStatusReport(id: "build/tests", state: .working).id, "build/tests")
    }

    func testEachKindHasAPhraseForANotificationWithoutAMessage() {
        XCTAssertEqual(ProgramStatusKind.permission.label, "Waiting for permission")
        XCTAssertEqual(ProgramStatusKind.question.label, "Waiting for an answer")
        XCTAssertEqual(ProgramStatusKind.auth.label, "Waiting for a sign-in")
    }
}
