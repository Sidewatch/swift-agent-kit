//
//  AgentProcessJoinTests.swift
//  AgentSessionTests
//
//  Every session reader is reachable from the agent name a terminal reports.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import AgentStatus
@testable import AgentSession

/// A terminal names the agent it sees (`TerminalStatus.agentName`); the session library picks
/// the reader by that name (`Agents.adapter(forProcess:)`). Two modules, one vocabulary.
final class AgentProcessJoinTests: XCTestCase {
    func testEveryReaderIsReachableFromWhatATerminalReports() {
        for adapter in Agents.all {
            for process in adapter.processNames {
                XCTAssertEqual(Agents.adapter(forProcess: TerminalStatus.agentName(process))?.name, adapter.name,
                               "a terminal running \(process) must prefer the \(adapter.name) session")
            }
        }
    }

    func testInstallsUnderARuntimeReachTheirReader() {
        let npmCodex = TerminalStatus.agentName("node", path: "/opt/homebrew/bin/node",
                                                args: "node /opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js")
        XCTAssertEqual(Agents.adapter(forProcess: npmCodex)?.name, "Codex")
        let npmGemini = TerminalStatus.agentName("node", args: "node /usr/local/lib/node_modules/@google/gemini-cli/dist/index.js")
        XCTAssertEqual(Agents.adapter(forProcess: npmGemini)?.name, "Gemini")
        XCTAssertEqual(Agents.adapter(forProcess: TerminalStatus.agentName("grok-1.0.41-darwin-arm64"))?.name, "Grok",
                       "Grok's updater runs a versioned binary behind a `grok` symlink")
        XCTAssertNil(Agents.adapter(forProcess: TerminalStatus.agentName("vim")))
    }
}
