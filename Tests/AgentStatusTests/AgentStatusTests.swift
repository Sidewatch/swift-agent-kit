//
//  AgentStatusTests.swift
//  AgentStatusTests
//
//  Ported from Sidewatch's --dump-terminal-status: the rules, calling the REAL derivation.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

/// Ported from Sidewatch's --dump-terminal-status: the rules, calling the REAL derivation.
final class AgentStatusTests: XCTestCase {
    func testAgentWhitelistByNameExactNamesAndNeverGenericRuntimes() {
        for name in ["claude", "Claude", "claude-code", "codex", "aider", "goose", "opencode", "hermes", "grok", "grok-cli", "pi"] {
            XCTAssertTrue(TerminalStatus.isAgentProcess(name), name)
        }
        for name in ["node", "python3", "vim", "npm", "cargo", "swift", "", "bash", "pip", "ping", "pigz", "pipx"] {
            XCTAssertFalse(TerminalStatus.isAgentProcess(name), "\(name) is not an agent (pi is exact-only)")
        }
        XCTAssertFalse(TerminalStatus.isAgentProcess(nil))
    }

    /// The prefix rule exists for versioned or suffixed binaries (`claude-code`, `codex-cli`,
    /// `grok-cli`), not for any program that happens to START with an agent's name: `amplify`
    /// (AWS) and `ampl` begin with "amp", and a terminal running them read as an agent working.
    func testAgentPrefixMatchStopsAtAWordBoundary() {
        for name in ["claude-code", "codex-cli", "grok-cli", "cursor-agent", "claude2"] {
            XCTAssertTrue(TerminalStatus.isAgentProcess(name), name)
        }
        for name in ["amplify", "ampl", "ampere", "copilotd", "goosefs", "geminiscope"] {
            XCTAssertFalse(TerminalStatus.isAgentProcess(name), "\(name) merely starts with an agent's name")
        }
    }

    func testScreenStateFallbackReadsPromptsAndWorkingMarkers() {
        let screens: [(String, [String], ScreenState?)] = [
            ("claude permission dialog", ["Do you want to make this edit to main.swift?", "❯ 1. Yes", "  2. Yes, and don't ask again this session", "  3. No"], .waitingForInput),
            ("claude working", ["✻ Baking… (esc to interrupt)", "", "> "], .working),
            ("gemini allow prompt", ["Allow execution of 'rm -rf build'?", "● 1. Yes, allow once", "  2. Yes, allow always", "  3. No (esc)"], .waitingForInput),
            ("codex y/n", ["Run `npm test`? [y/N]"], .waitingForInput),
            ("plain shell prompt", ["user@mac proj % "], nil),
            ("agent output, nothing asked", ["Found 3 TODO comments in src/:", "- src/main.py:7 — read config_path from argv"], nil),
            ("numbered list without cursor is not a prompt", ["1. Initial commit", "2. Added parser"], nil),
            ("empty screen", ["", "", ""], nil),
            // Claude Code 2.1.2xx shapes, checked against real screens.
            ("mcp elicitation", ["MCP server \"github\" requests your input", "  Repository name: ", "  ❯ Accept   Decline"], .waitingForInput),
            ("dynamic workflow confirmation", ["Run a dynamic workflow?", "  This will start 6 agents.", "  ❯ 1. Yes", "    2. No"], .waitingForInput),
            ("plan approval footer", ["Ready to code?", "  Here is the plan…", "  ↑/↓ to navigate · enter to confirm · esc to cancel"], .waitingForInput),
            ("esc to cancel alone is still working", ["✻ Thinking… (esc to cancel)", "", "> "], .working),
        ]
        for (label, rows, want) in screens { XCTAssertEqual(ScreenStateClassifier.classify(rows), want, label) }
        XCTAssertEqual(ScreenStateClassifier.promptLine(["Do you want to make this edit to main.swift?", "❯ 1. Yes", "  2. No"]), "Do you want to make this edit to main.swift?", "the question above the cursor, not the cursor's line")
        XCTAssertEqual(ScreenStateClassifier.promptLine(["Run `npm test`? [y/N]"]), "Run `npm test`? [y/N]")
        XCTAssertEqual(ScreenStateClassifier.promptLine(["Ready to code?", "  ↑/↓ to navigate · enter to confirm · esc to cancel"]), "Ready to code?")
        XCTAssertNil(ScreenStateClassifier.promptLine(["✻ Baking… (esc to interrupt)"]))
    }

    func testAttentionNoticeFiresOnlyForWhatThePersonCannotSee() {
        XCTAssertTrue(AttentionNotice.shouldNotify(enabled: true, appActive: false, paneVisible: true), "app in the background")
        XCTAssertTrue(AttentionNotice.shouldNotify(enabled: true, appActive: true, paneVisible: false), "pane hidden behind another tab or a collapsed panel")
        XCTAssertFalse(AttentionNotice.shouldNotify(enabled: true, appActive: true, paneVisible: true), "the pane in front: the badge is enough")
        XCTAssertFalse(AttentionNotice.shouldNotify(enabled: false, appActive: false, paneVisible: false), "off is off")
        let needs = AttentionNotice.needsYou(prompt: "Do you want to proceed?").text(agent: "Claude")
        XCTAssertEqual(needs.title, "Claude needs you"); XCTAssertEqual(needs.body, "Do you want to proceed?")
        XCTAssertEqual(AttentionNotice.needsYou(prompt: "  ").text(agent: "").body, "A prompt is waiting in the terminal.")
        XCTAssertEqual(AttentionNotice.finished.text(agent: "Codex").title, "Codex finished")
    }

    private func status(_ busy: Bool, _ process: String?, _ path: String?, _ args: String?, unseen: Bool) -> TerminalStatus {
        TerminalStatus.derive(foreground: ForegroundInfo(isBusy: busy, process: process, processPath: path, processArgs: args),
                              unseenCompletion: unseen, attention: nil)
    }

    func testDerivationCoversTheThreeInstallShapesAndTheFalsePositives() {
        XCTAssertEqual(status(false, nil, nil, nil, unseen: false), .idle)
        XCTAssertEqual(status(true, "claude", nil, nil, unseen: false), .agent)
        XCTAssertEqual(status(true, "cargo", nil, nil, unseen: false), .running)
        XCTAssertEqual(status(false, nil, nil, nil, unseen: true), .finished)
        XCTAssertEqual(status(true, "claude", nil, nil, unseen: true), .agent, "busy outranks a pending notice")
        XCTAssertEqual(status(true, "2.1.223", "/Users/x/.local/share/claude/versions/2.1.223", nil, unseen: false), .agent, "native: the binary is a version number; the PATH says claude")
        XCTAssertEqual(status(true, "node", "/usr/local/bin/node", "node /usr/local/lib/node_modules/@openai/codex/bin/codex.js", unseen: false), .agent, "npm: only the ARGS say codex")
        XCTAssertEqual(status(true, "python3", "/opt/homebrew/bin/python3", "python3 /opt/homebrew/bin/aider --model gpt-4", unseen: false), .agent)
        XCTAssertEqual(status(true, "vim", "/Users/x/claude-notes/bin/vim", nil, unseen: false), .running, "a project merely named claude-notes")
        XCTAssertEqual(status(true, "node", "/usr/local/bin/node", "node server.js", unseen: false), .running)
        XCTAssertEqual(status(true, "python3", "/opt/homebrew/bin/python3", "python3 manage.py", unseen: false), .running)
    }

    func testAttentionOutranksTheProcessAndNeedsYouSortsFirst() {
        let running = ForegroundInfo(isBusy: true, process: "claude", processPath: nil, processArgs: nil)
        XCTAssertEqual(TerminalStatus.derive(foreground: running, unseenCompletion: false, attention: .waiting), .waiting)
        XCTAssertEqual(TerminalStatus.derive(foreground: running, unseenCompletion: false, attention: nil), .agent)
        XCTAssertEqual([TerminalStatus.idle, .running, .agent, .finished, .waiting].sorted { $0.priority < $1.priority }, [.waiting, .finished, .agent, .running, .idle])
        XCTAssertEqual([TerminalStatus.idle, .running, .agent, .finished, .waiting].filter(\.isActionable), [.finished, .waiting])
        XCTAssertEqual([TerminalStatus.idle, .running, .agent, .finished, .waiting].filter(\.impliesAgent), [.agent, .finished, .waiting])
    }

    func testCommandNameComesFromArgvNotTheExecutable() {
        let cases: [(String?, String?)] = [
            ("claude", "claude"),
            ("/Users/x/.local/share/claude/versions/2.1.223", "2.1.223"),
            ("node /opt/homebrew/lib/node_modules/@openai/codex/cli.js", "codex"),
            ("node /Users/x/.npm/lib/node_modules/@anthropic-ai/claude-code/cli.js", "claude-code"),
            ("python3 /opt/homebrew/bin/aider --model gpt-4", "aider"),
            ("node server.js", "server"),
            ("cargo build --release", "cargo"),
            ("vim README.md", "vim"),
            // Inline code is not a program; a module is.
            ("python3 -c import time; time.sleep(9)", "python3"),
            ("node -e setTimeout(()=>{},1e4)", "node"),
            ("sh -c make test", "sh"),
            ("python3 -m http.server 8000", "http.server"),
            (nil, nil), ("", nil),
        ]
        for (args, want) in cases { XCTAssertEqual(AgentProcess.commandName(fromArgs: args), want, args ?? "nil") }
    }

    // MARK: - Short and newer agent names

    func testTheNewlyListedAgentsAreRecognisedByName() {
        for name in ["crush", "antigravity", "ori", "droid", "pi"] {
            XCTAssertTrue(TerminalStatus.isAgentProcess(name), "\(name) should read as an agent")
        }
        XCTAssertTrue(TerminalStatus.isAgentProcess("crush-cli"), "a suffixed binary still counts")
    }

    /// The word-boundary rule already declines these, whether the stem is exact or prefixed —
    /// asserted so a change to THAT rule is caught here too.
    func testOrdinaryProgramsSharingAStemAreNotAgents() {
        for name in ["origin", "original", "droidcam", "pip", "ping", "pigz", "orient", "crushftp"] {
            XCTAssertFalse(TerminalStatus.isAgentProcess(name), "\(name) is not an agent")
        }
    }

    /// What equality actually buys over the prefix rule: a non-letter after a two- or
    /// three-letter stem. `pi2` and `ori-2` would pass the boundary rule and must not pass this.
    func testAShortStemFollowedByANonLetterIsNotAnAgent() {
        for name in ["pi2", "ori-2", "droid.old", "pi_", "ori3"] {
            XCTAssertFalse(TerminalStatus.isAgentProcess(name), "\(name) is not an agent")
        }
        // The longer, distinctive names keep the looseness on purpose.
        XCTAssertTrue(TerminalStatus.isAgentProcess("antigravity2"))
    }

    /// Amazon Q's `q` is deliberately absent: a single letter is a name other tools use, and a
    /// pane claiming an agent is running when one is not is a false fact on a windshield.
    func testAmazonQIsNotClaimedByASingleLetter() {
        XCTAssertFalse(TerminalStatus.isAgentProcess("q"))
    }

    /// The gap this closed: the ARGUMENTS tier never consulted the exact names, so an agent
    /// installed under a runtime was invisible to all three tiers.
    func testAnExactlyNamedAgentUnderARuntimeIsSeenThroughItsArguments() {
        XCTAssertTrue(TerminalStatus.isAgentProcess("node", path: "/usr/local/bin/node",
                                                    args: "node /opt/pi/cli.js --resume"))
        XCTAssertTrue(TerminalStatus.isAgentProcess("node", path: "/usr/local/bin/node",
                                                    args: "node /opt/ori/index.js"))
        XCTAssertFalse(TerminalStatus.isAgentProcess("node", path: "/usr/local/bin/node",
                                                     args: "node /srv/origin/server.js"),
                       "a path merely containing the word is not a token match")
    }

    func testTheNewNamesAreSeenInAPathComponentToo() {
        XCTAssertTrue(TerminalStatus.isAgentProcess("1.4.2", path: "/Users/x/.local/share/crush/versions/1.4.2"))
        XCTAssertTrue(TerminalStatus.isAgentProcess("2.0.0", path: "/Users/x/.local/share/droid/2.0.0"))
    }
}
