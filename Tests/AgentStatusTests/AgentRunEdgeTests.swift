//
//  AgentRunEdgeTests.swift
//  AgentStatusTests
//
//  An agent run's edges, through the sequences a terminal sees.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

/// `AgentRunEdge`.
final class AgentRunEdgeTests: XCTestCase {
    private let prompt = AgentRunEdge.Reading(isBusy: false, agentKey: nil)
    private let claude = AgentRunEdge.Reading(isBusy: true, agentKey: "claude|/bin/claude|")
    private let codex = AgentRunEdge.Reading(isBusy: true, agentKey: "codex|/bin/codex|")
    private let build = AgentRunEdge.Reading(isBusy: true, agentKey: nil)  // swift build, not an agent

    /// Steps through `readings`, returning each step's effects.
    private func run(_ edge: inout AgentRunEdge, _ readings: [AgentRunEdge.Reading], userAtTerminal: Bool = false) -> [AgentRunEdge.Effects]
    {
        var effects: [AgentRunEdge.Effects] = []
        var previous = prompt
        for reading in readings {
            effects.append(edge.step(from: previous, to: reading, userAtTerminal: userAtTerminal))
            previous = reading
        }
        return effects
    }

    func testAnAgentExitingToThePromptIsDoneAndUnseen() {
        var edge = AgentRunEdge()
        let effects = run(&edge, [claude, claude, prompt])
        XCTAssertTrue(effects[2].contains(.notifyFinished))
        XCTAssertTrue(effects[2].contains(.clearAttention), "its question died with it")
        XCTAssertTrue(effects[2].contains(.readDiagnostics), "a command finished")
        XCTAssertTrue(edge.unseenCompletion)
    }

    func testAHandoffToABuildToolIsStillWorkInFlight() {
        var edge = AgentRunEdge()
        let effects = run(&edge, [claude, build, build, prompt])
        XCTAssertFalse(effects[1].contains(.notifyFinished), "the agent left, but the build is running")
        XCTAssertTrue(edge.unseenCompletion)
        XCTAssertTrue(effects[3].contains(.notifyFinished), "Done once the shell is back")
        XCTAssertEqual(effects.filter { $0.contains(.notifyFinished) }.count, 1)
    }

    func testAnotherAgentInOnePollIsAFreshRun() {
        var edge = AgentRunEdge()
        let effects = run(&edge, [claude, codex])
        XCTAssertTrue(effects[1].contains(.forgetReports), "the previous agent's reports are history")
        XCTAssertFalse(effects[1].contains(.notifyFinished), "still busy: no Done yet")
        XCTAssertEqual(edge.agentKey, codex.agentKey)
    }

    func testARunWhoseReportsSaidDoneIsNotAnnouncedAgainOnExit() {
        var edge = AgentRunEdge()
        _ = run(&edge, [claude])
        edge.noteFinishedTold()
        let exit = edge.step(from: claude, to: prompt, userAtTerminal: false)
        XCTAssertFalse(exit.contains(.notifyFinished), "told once already")
        XCTAssertTrue(edge.unseenCompletion, "the Done badge stays until the person looks")
    }

    func testANewTurnGoingLiveReArmsTheAnnouncement() {
        var edge = AgentRunEdge()
        _ = run(&edge, [claude])
        edge.noteFinishedTold()
        edge.noteRunLive()  // the person asked for more, the agent is working again
        XCTAssertTrue(edge.step(from: claude, to: prompt, userAtTerminal: false).contains(.notifyFinished))
    }

    func testAFreshRunForgetsThatThePreviousOneWasTold() {
        var edge = AgentRunEdge()
        _ = run(&edge, [claude])
        edge.noteFinishedTold()
        _ = edge.step(from: claude, to: codex, userAtTerminal: false)
        XCTAssertTrue(edge.step(from: codex, to: prompt, userAtTerminal: false).contains(.notifyFinished))
    }

    func testThePersonAtTheTerminalAccruesNothing() {
        var edge = AgentRunEdge()
        _ = run(&edge, [claude, prompt], userAtTerminal: true)
        XCTAssertFalse(edge.unseenCompletion)
        var looked = AgentRunEdge()
        _ = run(&looked, [claude, prompt])
        looked.acknowledge()
        XCTAssertFalse(looked.unseenCompletion)
    }

    func testAPlainCommandFinishingOnlyReadsItsOutput() {
        var edge = AgentRunEdge()
        let effects = run(&edge, [build, prompt])
        XCTAssertEqual(effects[1], [.readDiagnostics])
        XCTAssertFalse(edge.unseenCompletion)
    }

    func testAnIdleForegroundHoldsNoAgent() {
        XCTAssertNil(AgentRunEdge.Reading(isBusy: false, agentKey: "claude|/bin/claude|").agentKey, "the shell is in front")
        var edge = AgentRunEdge()
        _ = run(&edge, [claude, AgentRunEdge.Reading(isBusy: false, agentKey: "claude|/bin/claude|")])
        XCTAssertTrue(edge.unseenCompletion, "a stale key on an idle reading is still the agent leaving")
    }
}
