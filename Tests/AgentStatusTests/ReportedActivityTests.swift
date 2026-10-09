//
//  ReportedActivityTests.swift
//  AgentStatusTests
//
//  The merge: reports decide while any is held; the screen decides otherwise; the most urgent record wins.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

final class ReportedActivityTests: XCTestCase {
    private let dialogOnScreen: ScreenState = .waitingForInput

    func testWithNoReportTheScreenDecidesAsBefore() {
        let empty = ReportedActivity()
        XCTAssertFalse(empty.hasReports)
        XCTAssertEqual(empty.activity(screen: .waitingForInput), .needsYou(kind: nil), "the screen cannot say which kind")
        XCTAssertEqual(empty.activity(screen: .working), .working)
        XCTAssertNil(empty.activity(screen: nil), "nothing on screen, nothing reported: no verdict")
    }

    func testEachReportedStateMapsToItsActivity() {
        let cases: [(ProgramStatusState, ProgramStatusKind?, AgentActivity)] = [
            (.working, nil, .working), (.blocked, .permission, .needsYou(kind: .permission)),
            (.blocked, .question, .needsYou(kind: .question)), (.blocked, .auth, .needsYou(kind: .auth)),
            (.blocked, nil, .needsYou(kind: nil)), (.idle, nil, .idle), (.done, nil, .finished), (.error, nil, .failed),
        ]
        for (state, kind, want) in cases {
            let held = ReportedActivity(reports: [ProgramStatusReport(state: state, kind: kind)])
            XCTAssertEqual(held.activity(screen: nil), want, "\(state)")
        }
    }

    /// The point of the protocol: a program that reports is believed over what the screen looks
    /// like. Claude Code keeps its dialog's text on screen for a moment after an answer, and
    /// "esc to interrupt" under a permission prompt; the report settles both.
    func testAReportOutranksTheScreenWhicheverWaySay() {
        var held = ReportedActivity()
        held.update([ProgramStatusReport(state: .working)])
        XCTAssertEqual(held.activity(screen: dialogOnScreen), .working, "working by its own account, whatever the screen shows")
        held.update([ProgramStatusReport(state: .idle)])
        XCTAssertEqual(held.activity(screen: .working), .idle, "idle by its own account, whatever marker is still painted")
        held.update([ProgramStatusReport(state: .blocked, kind: .question)])
        XCTAssertEqual(held.activity(screen: nil), .needsYou(kind: .question), "blocked with nothing the screen reader knows")
    }

    /// A new prompt or the program's exit ends working and blocked records; results survive.
    func testAReportOlderThanANewPromptIsDropped() {
        var held = ReportedActivity(reports: [ProgramStatusReport(state: .blocked, kind: .permission)])
        held.promptStarted()
        XCTAssertFalse(held.hasReports)
        XCTAssertEqual(held.activity(screen: dialogOnScreen), .needsYou(kind: nil), "with the stale record gone the screen decides again")
        XCTAssertNil(held.activity(screen: nil))

        held.update([ProgramStatusReport(id: "build", state: .working), ProgramStatusReport(state: .done)])
        held.promptStarted()
        XCTAssertEqual(held.reports, [ProgramStatusReport(state: .done)], "a result survives the prompt; work in flight does not")
    }

    func testResetForgetsEverythingAPredecessorReported() {
        var held = ReportedActivity(reports: [ProgramStatusReport(state: .done), ProgramStatusReport(state: .error)])
        held.reset()
        XCTAssertFalse(held.hasReports)
        XCTAssertEqual(held.activity(screen: .working), .working, "the next program is read off the screen")
    }

    /// Several records: the most urgent decides — a blocked child blocks the whole program, a
    /// working child is work in flight whatever the root says.
    func testTheMostUrgentRecordDecidesAcrossIds() {
        let root = ProgramStatusReport(state: .working)
        let blockedChild = ProgramStatusReport(id: "build", state: .blocked, kind: .permission, message: "Allow rm?")
        var held = ReportedActivity(reports: [root, blockedChild])
        XCTAssertEqual(held.decidingReport, blockedChild)
        XCTAssertEqual(held.activity(screen: nil), .needsYou(kind: .permission), "a child asking permission outranks a working root")

        held.update([ProgramStatusReport(state: .idle), ProgramStatusReport(id: "build", state: .working)])
        XCTAssertEqual(held.activity(screen: nil), .working, "a working child outranks an idle root")

        held.update([ProgramStatusReport(state: .idle), ProgramStatusReport(id: "build", state: .error)])
        XCTAssertEqual(held.activity(screen: nil), .failed, "a failed child is the more informative result")

        held.update([ProgramStatusReport(id: "a", state: .working), ProgramStatusReport(state: .working, message: "root")])
        XCTAssertEqual(held.decidingReport?.message, "root", "among equals the root wins")

        held.update([
            ProgramStatusReport(id: "a", state: .working, message: "older"),
            ProgramStatusReport(id: "b", state: .working, message: "newer"),
        ])
        XCTAssertEqual(held.decidingReport?.message, "newer", "among equal children the most recently updated wins")
    }

    func testUrgencyOrdersBlockedWorkingErrorDoneIdle() {
        let ordered = ProgramStatusState.allCases.sorted { ReportedActivity.urgency($0) > ReportedActivity.urgency($1) }
        XCTAssertEqual(ordered, [.blocked, .working, .error, .done, .idle])
    }
}
