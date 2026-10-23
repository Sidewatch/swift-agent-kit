//
//  DockBounceAllowanceTests.swift
//  AgentSessionTests
//
//  Tests for `DockBounceAllowance`: one bounce per absence.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// One bounce per absence: the first request takes it, the rest of the absence is quiet, and
/// coming back renews it.
final class DockBounceAllowanceTests: XCTestCase {

    func testOneBouncePerAbsence() {
        var allowance = DockBounceAllowance()
        XCTAssertTrue(allowance.take(), "the first agent to need the person bounces")
        XCTAssertFalse(allowance.take(), "a second agent in the same absence does not")
        XCTAssertFalse(allowance.take())
        allowance.renew()
        XCTAssertTrue(allowance.take(), "after coming back, the next absence bounces once")
        XCTAssertFalse(allowance.take())
    }

    func testRenewingWithoutABounceChangesNothing() {
        var allowance = DockBounceAllowance()
        allowance.renew()
        XCTAssertFalse(allowance.spent)
        XCTAssertTrue(allowance.take())
    }
}
