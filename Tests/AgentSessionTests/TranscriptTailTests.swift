//
//  TranscriptTailTests.swift
//  AgentSessionTests
//
//  Change detection on a polled transcript, the capped buffer included; the away digest's rule.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// `TranscriptTail` and `AwayDigest`.
final class TranscriptTailTests: XCTestCase {
    private func tool(_ n: Int) -> TimelineEvent {
        TimelineEvent(kind: .toolUse, title: "Bash", detail: "step \(n)", filePath: nil, timestamp: "t\(n)")
    }
    private func edit(_ path: String?) -> TimelineEvent {
        TimelineEvent(kind: .fileEdit, title: "Edit", detail: "", filePath: path, timestamp: "e")
    }
    private func fresh(_ change: TranscriptTail.Change) -> [String]? {
        if case .fresh(let events) = change { return events.map(\.detail) }
        return nil
    }

    func testTheFirstLookBaselinesAndAnUnchangedTailIsQuiet() {
        var tail = TranscriptTail()
        XCTAssertEqual(tail.observe([tool(1), tool(2)]), .baselined, "history is not fresh activity")
        XCTAssertEqual(tail.observe([tool(1), tool(2)]), .unchanged)
    }

    func testAGrowingTranscriptReportsExactlyTheNewEvents() {
        var tail = TranscriptTail()
        _ = tail.observe([tool(1)])
        XCTAssertEqual(fresh(tail.observe([tool(1), tool(2), tool(3)])), ["step 2", "step 3"])
    }

    func testGrowthIsCountedEvenWhenTheOldTailRepeatsInIt() {
        var tail = TranscriptTail()
        let same = tool(4)
        _ = tail.observe([same])
        XCTAssertEqual(fresh(tail.observe([same, tool(5), same])), ["step 5", "step 4"], "the count says two are new")
    }

    func testPastTheCapTheNewEventsFollowTheLastSeenTail() {
        var tail = TranscriptTail()
        _ = tail.observe((1...300).map(tool))
        // Capped at 300: two new events push two old ones out, so the count does not change.
        XCTAssertEqual(fresh(tail.observe((3...302).map(tool))), ["step 301", "step 302"])
    }

    func testARepeatedTailIsMatchedAtItsLastOccurrence() {
        var tail = TranscriptTail()
        let same = tool(7)
        _ = tail.observe([tool(1), same, tool(8), same])
        // Same count (the cap) and the old tail `same` appears twice: only what follows the LAST is new.
        XCTAssertEqual(fresh(tail.observe([same, tool(8), same, tool(9)])), ["step 9"])
    }

    func testNoOverlapReportsOnlyTheNewest() {
        var tail = TranscriptTail()
        _ = tail.observe([tool(1), tool(2)])
        XCTAssertEqual(fresh(tail.observe([tool(5), tool(6)])), ["step 6"])
    }

    func testResetBaselinesAgain() {
        var tail = TranscriptTail()
        _ = tail.observe([tool(1)])
        tail.reset()
        XCTAssertEqual(tail.observe([tool(1), tool(2)]), .baselined)
    }

    // MARK: - Away digest

    func testTheDigestCountsDistinctFilesAndOtherToolRuns() {
        var gap = AwayDigest()
        gap.add([edit("/a"), edit("/a"), edit("/b"), edit(nil), tool(1)])
        XCTAssertEqual(gap.editedFiles, ["/a", "/b"])
        XCTAssertEqual(gap.toolRuns, 2, "a path-less edit counts as a tool run")
    }

    func testASummaryNeedsALongAbsenceAndSomethingToTell() {
        var gap = AwayDigest()
        XCTAssertNil(gap.summary(away: 600), "nothing happened")
        gap.add([edit("/a")])
        XCTAssertNil(gap.summary(away: 179), "a short absence")
        XCTAssertEqual(gap.summary(away: 180), AwayDigest.Summary(filesEdited: 1, toolRuns: 0))
    }
}
