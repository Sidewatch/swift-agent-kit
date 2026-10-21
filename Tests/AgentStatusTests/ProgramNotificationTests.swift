//
//  ProgramNotificationTests.swift
//  AgentStatusTests
//
//  OSC 777 notifications and the multi-line paste rule.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

/// `ProgramNotification` and `PastePolicy`.
final class ProgramNotificationTests: XCTestCase {
    func testANotifyPayloadKeepsSemicolonsInItsBody() {
        XCTAssertEqual(
            ProgramNotification(osc777: Array("notify;Build;done; 3 warnings; ok".utf8)),
            ProgramNotification(title: "Build", body: "done; 3 warnings; ok"))
        XCTAssertEqual(ProgramNotification(osc777: Array("notify;Title;".utf8))?.body, "", "an empty body is still one")
    }

    func testOtherPayloadsAreNotNotifications() {
        XCTAssertNil(ProgramNotification(osc777: Array("progress;50".utf8)))
        XCTAssertNil(ProgramNotification(osc777: Array("notify;no body".utf8)))
        XCTAssertNil(ProgramNotification(osc777: Array("Notify;a;b".utf8)), "the verb is exact")
        XCTAssertNil(ProgramNotification(osc777: [0x6E, 0x6F, 0x74, 0x69, 0x66, 0x79, 0x3B, 0xFF, 0x3B, 0x62]), "not UTF-8")
    }

    func testTheTitleNamesTheProgramThatAsked() {
        let note = ProgramNotification(title: "Build finished", body: "")
        XCTAssertEqual(note.displayTitle(program: "claude"), "claude: Build finished")
        XCTAssertEqual(note.displayTitle(program: "  "), "Build finished")
        XCTAssertEqual(note.displayTitle(program: nil), "Build finished")
    }

    func testOnlyAnUnbracketedMultiLinePasteAsks() {
        XCTAssertEqual(PastePolicy.commandsTyped(by: "a\nb", bracketed: false), 2)
        XCTAssertEqual(PastePolicy.commandsTyped(by: "a\r\n\r\nb\r\nc", bracketed: false), 3, "blank lines and CRLF")
        XCTAssertNil(PastePolicy.commandsTyped(by: "a\nb", bracketed: true))
        XCTAssertNil(PastePolicy.commandsTyped(by: "a\n", bracketed: false), "one line, its Return included")
        XCTAssertNil(PastePolicy.commandsTyped(by: "", bracketed: false))
    }
}
