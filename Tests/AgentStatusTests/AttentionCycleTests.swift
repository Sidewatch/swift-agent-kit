//
//  AttentionCycleTests.swift
//  AgentStatusTests
//
//  Tests for `AttentionCycle`: a waiting agent before a finished one, the walk starts after the
//  current terminal and wraps, and nothing to visit is nil.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

/// Tests for `AttentionCycle`: a waiting agent before a finished one, the walk starts after the
/// current terminal and wraps, and nothing to visit is nil.
final class AttentionCycleTests: XCTestCase {
    func testAWaitingAgentComesBeforeAFinishedOne() {
        XCTAssertEqual(AttentionCycle.next(after: 0, in: [.idle, .finished, .agent, .waiting]), 3)
    }

    func testTheWalkStartsAfterTheCurrentTerminalAndWraps() {
        let statuses: [TerminalStatus] = [.waiting, .agent, .waiting, .idle, .waiting]
        XCTAssertEqual(AttentionCycle.next(after: 0, in: statuses), 2)
        XCTAssertEqual(AttentionCycle.next(after: 2, in: statuses), 4)
        XCTAssertEqual(AttentionCycle.next(after: 4, in: statuses), 0, "wraps to the start")
    }

    func testTheCurrentTerminalIsChosenOnlyWhenItIsTheOneLeft() {
        XCTAssertEqual(AttentionCycle.next(after: 1, in: [.idle, .waiting, .agent]), 1)
        XCTAssertEqual(AttentionCycle.next(after: 1, in: [.finished, .waiting, .agent]), 1, "waiting beats another's finished")
    }

    func testFinishedTerminalsAreWalkedTheSameWay() {
        let statuses: [TerminalStatus] = [.finished, .idle, .finished]
        XCTAssertEqual(AttentionCycle.next(after: 0, in: statuses), 2)
        XCTAssertEqual(AttentionCycle.next(after: 2, in: statuses), 0)
    }

    func testNoFocusStartsAtTheFirstTerminal() {
        XCTAssertEqual(AttentionCycle.next(after: nil, in: [.finished, .waiting, .waiting]), 1)
    }

    func testNothingToVisitIsNil() {
        XCTAssertNil(AttentionCycle.next(after: 0, in: [.idle, .agent, .running]))
        XCTAssertNil(AttentionCycle.next(after: nil, in: []))
    }

    func testNeedingYouListsEveryWaitingBeforeEveryFinishedInHostOrder() {
        let statuses: [TerminalStatus] = [.finished, .idle, .waiting, .agent, .finished, .waiting, .running]
        XCTAssertEqual(AttentionCycle.needingYou(in: statuses), [2, 5, 0, 4])
        XCTAssertEqual(AttentionCycle.needingYou(in: [.idle, .agent, .running]), [], "nothing needs you: an empty list")
        XCTAssertEqual(AttentionCycle.needingYou(in: []), [])
    }
}
