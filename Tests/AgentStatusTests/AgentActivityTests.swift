//
//  AgentActivityTests.swift
//  AgentStatusTests
//
//  Live versus settled, and the edge between them that is a run's end.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

final class AgentActivityTests: XCTestCase {
    func testWorkingAndNeedsYouAreLiveTheRestSettled() {
        XCTAssertTrue(AgentActivity.working.isActive)
        XCTAssertTrue(AgentActivity.needsYou(kind: .permission).isActive)
        XCTAssertTrue(AgentActivity.needsYou(kind: nil).needsYou)
        XCTAssertFalse(AgentActivity.working.needsYou)
        for settled in [AgentActivity.idle, .finished, .failed] {
            XCTAssertTrue(settled.isSettled, "\(settled)")
            XCTAssertFalse(settled.needsYou, "\(settled)")
        }
    }

    /// A run ends on the edge from live to settled — and only there. Idle at launch ends
    /// nothing; idle seen twice is one end, not two; no verdict on either side is no edge.
    func testARunEndsOnlyOnTheEdgeFromLiveToSettled() {
        XCTAssertTrue(AgentActivity.runEnded(from: .working, to: .idle), "a turn's end")
        XCTAssertTrue(AgentActivity.runEnded(from: .needsYou(kind: .question), to: .finished))
        XCTAssertTrue(AgentActivity.runEnded(from: .working, to: .failed))
        XCTAssertFalse(AgentActivity.runEnded(from: nil, to: .idle), "idle at launch")
        XCTAssertFalse(AgentActivity.runEnded(from: .idle, to: .idle), "the same end seen twice")
        XCTAssertFalse(AgentActivity.runEnded(from: .finished, to: .idle))
        XCTAssertFalse(AgentActivity.runEnded(from: .working, to: .needsYou(kind: .permission)), "a prompt mid-run is not an end")
        XCTAssertFalse(AgentActivity.runEnded(from: .working, to: nil), "losing the verdict is not an end")
        XCTAssertFalse(AgentActivity.runEnded(from: .idle, to: .working), "a start")
    }
}
