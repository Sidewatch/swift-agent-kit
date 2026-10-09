//
//  AgentSendPolicyTests.swift
//  AgentStatusTests
//
//  Text a host derived from a file is submitted only to a live agent.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

final class AgentSendPolicyTests: XCTestCase {
    private typealias Candidate = AgentSendPolicy.Candidate<String>
    private typealias Verdict = AgentSendPolicy.Verdict<String>

    func testOnlyAWorkingOrWaitingAgentIsLive() {
        XCTAssertTrue(TerminalStatus.agent.isLiveAgent)
        XCTAssertTrue(TerminalStatus.waiting.isLiveAgent)
        for status in [TerminalStatus.idle, .running, .finished] {
            XCTAssertFalse(status.isLiveAgent, "\(status): a shell or an exited agent reads the text as a command line")
        }
    }

    func testTheCurrentTerminalSubmitsWhenItRunsALiveAgent() {
        let terminals = [
            Candidate(id: "shell", status: .idle), Candidate(id: "claude", status: .agent), Candidate(id: "codex", status: .waiting),
        ]
        XCTAssertEqual(AgentSendPolicy.verdict(current: "claude", terminals: terminals), Verdict(target: "claude", submits: true))
        XCTAssertEqual(
            AgentSendPolicy.verdict(current: "codex", terminals: terminals), Verdict(target: "codex", submits: true),
            "two agents: the one in front wins, never a guess between them")
    }

    func testASendMovesToTheSingleLiveAgentOnlyWhenAllowed() {
        let terminals = [
            Candidate(id: "shell", status: .idle), Candidate(id: "claude", status: .agent), Candidate(id: "build", status: .running),
        ]
        XCTAssertEqual(AgentSendPolicy.verdict(current: "shell", terminals: terminals), Verdict(target: "claude", submits: true))
        XCTAssertEqual(
            AgentSendPolicy.verdict(current: "shell", terminals: terminals, redirectsToSingleAgent: false),
            Verdict(target: "shell", submits: false), "a terminal the person chose is kept, and the text is left for them to read")
    }

    func testWithNoLiveAgentTheTextIsPastedUnsubmitted() {
        let shells = [
            Candidate(id: "shell", status: .idle), Candidate(id: "done", status: .finished), Candidate(id: "vim", status: .running),
        ]
        XCTAssertEqual(AgentSendPolicy.verdict(current: "shell", terminals: shells), Verdict(target: "shell", submits: false))
        XCTAssertEqual(
            AgentSendPolicy.verdict(current: "done", terminals: shells), Verdict(target: "done", submits: false),
            "finished is not live: the shell may be back at its prompt")
        let two = [Candidate(id: "a", status: .agent), Candidate(id: "b", status: .agent), Candidate(id: "shell", status: .idle)]
        XCTAssertEqual(
            AgentSendPolicy.verdict(current: "shell", terminals: two), Verdict(target: "shell", submits: false),
            "two live agents and neither in front: nobody is chosen for the person")
        XCTAssertEqual(
            AgentSendPolicy.verdict(current: nil, terminals: shells), Verdict(target: "shell", submits: false),
            "no current: the first terminal, unsubmitted")
        XCTAssertEqual(AgentSendPolicy.verdict(current: nil, terminals: [] as [Candidate]), Verdict(target: nil, submits: false))
    }
}
