//
//  DockBadgeVotesTests.swift
//  AgentSessionTests
//
//  Tests for `DockBadgeVotes`: several windows, one badge.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// Several windows, one badge: a question outranks a wait, and one window withdrawing its badge
/// leaves another's.
final class DockBadgeVotesTests: XCTestCase {

    func testOneWindowClearingLeavesTheOthersBadge() {
        var votes = DockBadgeVotes()
        XCTAssertNil(votes.label)
        XCTAssertEqual(votes.set(DockBadgeVotes.waiting, for: "a"), "●")
        XCTAssertEqual(votes.set(DockBadgeVotes.waiting, for: "b"), "●")
        XCTAssertEqual(votes.set(nil, for: "a"), "●", "window b still has an agent waiting")
        XCTAssertNil(votes.set(nil, for: "b"))
    }

    func testAQuestionOutranksAWait() {
        var votes = DockBadgeVotes()
        votes.set(DockBadgeVotes.waiting, for: "a")
        XCTAssertEqual(votes.set(DockBadgeVotes.question, for: "b"), "?")
        XCTAssertEqual(votes.set(DockBadgeVotes.waiting, for: "c"), "?")
        XCTAssertEqual(votes.set(nil, for: "b"), "●")
    }
}
