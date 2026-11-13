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

    func testAnOSC9MessageIsANotificationAndConEmusNumberedCommandsAreNot() {
        XCTAssertEqual(ProgramNotification(osc9: Array("Turn complete".utf8)), ProgramNotification(title: "", body: "Turn complete"))
        XCTAssertEqual(
            ProgramNotification(osc9: Array("done; 3 files changed".utf8))?.body, "done; 3 files changed", "a later ; is the message's")
        for progress in ["4;1;50", "4;0", "1;500", "2;text", "9;/Users/me", "4"] {
            XCTAssertNil(ProgramNotification(osc9: Array(progress.utf8)), "ConEmu's 9;\(progress) is not a notification")
        }
        XCTAssertNil(ProgramNotification(osc9: Array("".utf8)))
        XCTAssertNil(ProgramNotification(osc9: Array("   ".utf8)))
        XCTAssertNil(ProgramNotification(osc9: [0xFF, 0xFE]))
        XCTAssertEqual(
            ProgramNotification(osc9: Array("3 tests failed".utf8))?.body, "3 tests failed",
            "a message that starts with a number and a space")
        let untitled = ProgramNotification(title: "", body: "Turn complete")
        XCTAssertEqual(untitled.displayTitle(program: "codex"), "codex", "an untitled notice is titled by its sender")
        XCTAssertEqual(untitled.displayTitle(program: nil), "")
        XCTAssertEqual(ProgramNotification(title: "Build", body: "ok").displayTitle(program: "claude"), "claude: Build")
    }

    func testReturnFollowsAPasteAfterTheAgentsOwnDelay() {
        XCTAssertEqual(AgentSendPolicy.returnDelay(forAgent: "claude"), AgentSendPolicy.returnDelay)
        XCTAssertEqual(AgentSendPolicy.returnDelay(forAgent: nil), AgentSendPolicy.returnDelay)
        XCTAssertEqual(AgentSendPolicy.returnDelay(forAgent: "Copilot"), 0.3)
        XCTAssertGreaterThan(AgentSendPolicy.returnDelay(forAgent: "copilot"), AgentSendPolicy.returnDelay(forAgent: "codex"))
    }

    func testATabIsNamedByThePersonThenTheAgentsOwnTitleThenWhatItWasAsked() {
        func title(custom: String? = nil, program: String = "codex", titled: Bool = false, prompt: String? = nil) -> String {
            TerminalTabTitle.title(custom: custom, program: program, agentTitledItself: titled, prompt: prompt)
        }
        XCTAssertEqual(title(prompt: "Fix the login redirect"), "Fix the login redirect")
        XCTAssertEqual(title(custom: "backend", prompt: "Fix the login redirect"), "backend", "a name the person gave stands")
        XCTAssertEqual(
            title(program: "✳ Login redirect", titled: true, prompt: "Fix the login redirect"), "✳ Login redirect",
            "an agent's own title stands")
        XCTAssertEqual(title(prompt: nil), "codex")
        XCTAssertEqual(title(prompt: "   \n\t"), "codex", "a prompt with nothing in it names nothing")
        XCTAssertEqual(title(custom: "", prompt: "x"), "x")
        XCTAssertEqual(TerminalTabTitle.clipped("\n  first   real\tline  \nsecond"), "first real line")
        let long = TerminalTabTitle.clipped(String(repeating: "word ", count: 30))
        XCTAssertEqual(long?.count, TerminalTabTitle.promptLimit)
        XCTAssertEqual(long?.last, "…")
        XCTAssertNil(TerminalTabTitle.clipped(""))
    }
}
