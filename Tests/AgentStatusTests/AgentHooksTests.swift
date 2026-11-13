//
//  AgentHooksTests.swift
//  AgentStatusTests
//
//  Claude Code's hook payloads, the status they add up to, the settings file and the spool.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

final class AgentHooksTests: XCTestCase {
    private static let session = "00000000-0000-0000-0000-000000000001"
    private static let transcript = "/Users/example/.claude/projects/-tmp-project/00000000-0000-0000-0000-000000000001.jsonl"
    private static let common =
        #""session_id":"00000000-0000-0000-0000-000000000001","transcript_path":"/Users/example/.claude/projects/-tmp-project/00000000-0000-0000-0000-000000000001.jsonl","cwd":"/tmp/project""#

    // The four payloads below are what Claude Code 2.1.323 wrote to a hook's standard input for one
    // `claude -p` run, with the ids, paths and texts replaced. The notification is the example in
    // Claude Code's hooks reference: a headless run raises none.
    private static let started = "{\(common),\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}"
    private static let submitted =
        "{\(common),\"prompt_id\":\"00000000-0000-0000-0000-00000000000a\",\"permission_mode\":\"auto\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"Reply with the single word ok\"}"
    private static let stopped =
        "{\(common),\"prompt_id\":\"00000000-0000-0000-0000-00000000000a\",\"permission_mode\":\"auto\",\"effort\":{\"level\":\"medium\"},\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"ok\",\"background_tasks\":[],\"session_crons\":[]}"
    private static let ended =
        "{\(common),\"prompt_id\":\"00000000-0000-0000-0000-00000000000a\",\"hook_event_name\":\"SessionEnd\",\"reason\":\"other\"}"
    private static let permission =
        "{\(common),\"hook_event_name\":\"Notification\",\"message\":\"Claude needs your permission\",\"title\":\"Permission needed\",\"notification_type\":\"permission_prompt\"}"

    private func event(_ json: String) -> AgentHookEvent? { ClaudeHookPayload.event(from: Data(json.utf8)) }

    func testClaudeCodesPayloadsAreRead() {
        func expected(_ kind: AgentHookEvent.Kind) -> AgentHookEvent {
            AgentHookEvent(kind: kind, sessionID: Self.session, transcriptPath: Self.transcript, directory: "/tmp/project")
        }
        XCTAssertEqual(event(Self.started), expected(.sessionStarted))
        XCTAssertEqual(event(Self.submitted), expected(.promptSubmitted("Reply with the single word ok")))
        XCTAssertEqual(event(Self.stopped), expected(.stopped))
        XCTAssertEqual(event(Self.ended), expected(.sessionEnded))
        XCTAssertEqual(event(Self.permission), expected(.needsYou(.permission, message: "Claude needs your permission")))
    }

    func testOnlyANoticeThatTheAgentIsWaitingIsOne() {
        XCTAssertEqual(ClaudeHookPayload.need("permission_prompt"), .permission)
        XCTAssertEqual(ClaudeHookPayload.need("elicitation_dialog"), .question)
        XCTAssertEqual(ClaudeHookPayload.need("agent_needs_input"), .question)
        for other in ["idle_prompt", "auth_success", "agent_completed", "quota_auto_resume_fired", "plugin_notification", "", nil] {
            XCTAssertNil(ClaudeHookPayload.need(other), "\(other ?? "nil") is not the agent waiting on the person")
        }
        XCTAssertNil(event(Self.permission.replacingOccurrences(of: "permission_prompt", with: "idle_prompt")))
    }

    func testWhatIsNotAnEventIsNothing() {
        XCTAssertNil(event(""))
        XCTAssertNil(event("[]"))
        XCTAssertNil(event("{\"hook_event_name\":\"Stop\"}"), "no session")
        XCTAssertNil(event("{\"hook_event_name\":\"Stop\",\"session_id\":\"  \"}"), "an empty session")
        XCTAssertNil(event("{\"hook_event_name\":7,\"session_id\":\"s\"}"))
        XCTAssertNil(
            event(Self.stopped.replacingOccurrences(of: "\"Stop\"", with: "\"PermissionRequest\"")), "a permission request is not read")
        XCTAssertNil(event(Self.stopped.replacingOccurrences(of: "\"Stop\"", with: "\"PreToolUse\"")))
        let padded =
            "{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"pad\":\"" + String(repeating: "x", count: ClaudeHookPayload.sizeLimit)
            + "\"}"
        XCTAssertNil(event(padded), "a payload past the limit is not read, well formed or not")
        let long = String(repeating: "x", count: ClaudeHookPayload.textLimit + 500)
        let clipped = event("{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s\",\"prompt\":\"\(long)\"}")
        XCTAssertEqual(clipped?.kind, .promptSubmitted(String(repeating: "x", count: ClaudeHookPayload.textLimit)))
        XCTAssertEqual(event("{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s\",\"prompt\":7}")?.kind, .promptSubmitted(""))
    }

    func testEventsAddUpToAStatusAndTheSessionsFacts() throws {
        var activity = HookActivity()
        XCTAssertNil(activity.report)
        activity.note(try XCTUnwrap(event(Self.started)))
        XCTAssertNil(activity.report, "a session that has only started says nothing of work")
        XCTAssertEqual(activity.sessionID, Self.session)
        XCTAssertEqual(activity.transcriptPath, Self.transcript)
        activity.note(try XCTUnwrap(event(Self.submitted)))
        XCTAssertEqual(activity.report, ProgramStatusReport(id: HookActivity.reportID, state: .working))
        XCTAssertEqual(activity.prompt, "Reply with the single word ok")
        activity.note(try XCTUnwrap(event(Self.permission)))
        XCTAssertEqual(
            activity.report,
            ProgramStatusReport(id: HookActivity.reportID, state: .blocked, kind: .permission, message: "Claude needs your permission"))
        activity.note(try XCTUnwrap(event(Self.stopped)))
        XCTAssertEqual(activity.report?.state, .done)
        XCTAssertEqual(activity.prompt, "Reply with the single word ok", "the prompt outlasts its turn")
        activity.note(try XCTUnwrap(event(Self.ended)))
        XCTAssertEqual(activity, HookActivity(), "a session that ended leaves nothing")
    }

    func testAReportIsDroppedWhenThePersonTypesUnlessTheAgentHadFinished() throws {
        var activity = HookActivity()
        activity.note(try XCTUnwrap(event(Self.submitted)))
        activity.personTyped()
        XCTAssertNil(activity.report, "an interrupted turn sends no stop: working is no longer known")
        XCTAssertEqual(activity.prompt, "Reply with the single word ok")
        activity.note(try XCTUnwrap(event(Self.permission)))
        activity.personTyped()
        XCTAssertNil(activity.report, "no event says a prompt was answered")
        activity.note(try XCTUnwrap(event(Self.stopped)))
        activity.personTyped()
        XCTAssertEqual(activity.report?.state, .done, "typing does not unfinish a turn")
        activity.agentLeft()
        XCTAssertEqual(activity, HookActivity())
    }

    func testAnotherSessionsPromptIsNotThisOnes() throws {
        var activity = HookActivity()
        activity.note(try XCTUnwrap(event(Self.submitted)))
        activity.note(AgentHookEvent(kind: .sessionStarted, sessionID: "another"))
        XCTAssertNil(activity.prompt)
        XCTAssertEqual(activity.sessionID, "another")
    }

    // MARK: - The settings file

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInstallingIntoNoFileMakesOneWithABackgroundHookPerEvent() throws {
        let made = try ClaudeHookSettings.installing(in: nil)
        let hooks = try XCTUnwrap(try json(made)["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(Set(hooks.keys), ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"])
        for (event, groups) in hooks {
            XCTAssertEqual(groups.count, 1, event)
            XCTAssertNil(groups[0]["matcher"], "every event of the kind")
            let handler = try XCTUnwrap((groups[0]["hooks"] as? [[String: Any]])?.first)
            XCTAssertEqual(handler["type"] as? String, "command")
            XCTAssertEqual(handler["command"] as? String, HookSpool.command)
            XCTAssertEqual(handler["async"] as? Bool, true, "in the background: nothing it returns can decide for the agent")
        }
        XCTAssertTrue(ClaudeHookSettings.isInstalled(in: made))
        XCTAssertEqual(try ClaudeHookSettings.installing(in: made), made, "installing twice changes nothing")
        XCTAssertEqual(try ClaudeHookSettings.installing(in: Data("  \n".utf8)), made, "an empty file is no file")
    }

    func testThePersonsSettingsAndHooksAreCarriedThroughBothWays() throws {
        let theirs = Data(
            #"{"model":"opus","permissions":{"allow":["Bash(ls:*)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"./check.sh"}]}]}}"#
                .utf8)
        XCTAssertFalse(ClaudeHookSettings.isInstalled(in: theirs))
        let installed = try ClaudeHookSettings.installing(in: theirs)
        let root = try json(installed)
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertEqual((root["permissions"] as? [String: [String]])?["allow"], ["Bash(ls:*)"])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(hooks["Stop"]?.count, 2, "theirs, then the host's")
        XCTAssertEqual(((hooks["Stop"]?[0]["hooks"] as? [[String: Any]])?.first)?["command"] as? String, "say done")
        XCTAssertEqual(hooks["PreToolUse"]?.count, 1, "an event the host does not listen to is untouched")
        XCTAssertTrue(ClaudeHookSettings.isInstalled(in: installed))

        let removed = try json(try ClaudeHookSettings.removing(from: installed))
        XCTAssertEqual(
            NSDictionary(dictionary: removed), NSDictionary(dictionary: try json(theirs)), "removing leaves exactly what the person had")
        XCTAssertFalse(ClaudeHookSettings.isInstalled(in: try ClaudeHookSettings.removing(from: installed)))
    }

    func testRemovingFromAFileWithOnlyTheHostsHooksLeavesNoHooksKey() throws {
        let removed = try json(
            try ClaudeHookSettings.removing(from: try ClaudeHookSettings.installing(in: Data(#"{"theme":"dark"}"#.utf8))))
        XCTAssertEqual(NSDictionary(dictionary: removed), ["theme": "dark"])
        XCTAssertEqual(try json(try ClaudeHookSettings.removing(from: nil)).count, 0)
    }

    func testAHookInstalledForOnlySomeEventsIsNotInstalled() throws {
        var root = try json(try ClaudeHookSettings.installing(in: nil))
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        hooks["Stop"] = nil
        root["hooks"] = hooks
        let partial = try JSONSerialization.data(withJSONObject: root)
        XCTAssertFalse(ClaudeHookSettings.isInstalled(in: partial))
        XCTAssertTrue(ClaudeHookSettings.isInstalled(in: try ClaudeHookSettings.installing(in: partial)), "installing completes it")
    }

    func testAFileThatCannotBeReadIsLeftAlone() {
        for bad in ["not json", "[1,2]", #"{"hooks":[]}"#, #"{"hooks":{"Stop":"x"}}"#] {
            XCTAssertThrowsError(try ClaudeHookSettings.installing(in: Data(bad.utf8)), bad) {
                XCTAssertEqual($0 as? ClaudeHookSettings.Failure, .unreadable)
            }
        }
        XCTAssertThrowsError(try ClaudeHookSettings.removing(from: Data("not json".utf8)))
        XCTAssertFalse(ClaudeHookSettings.isInstalled(in: Data("not json".utf8)))
        XCTAssertFalse(ClaudeHookSettings.isInstalled(in: nil))
    }

    func testAGroupThatAlsoRunsTheirCommandIsNotTheHosts() {
        let mixed: [String: Any] = [
            "hooks": [["type": "command", "command": HookSpool.command], ["type": "command", "command": "say hi"]]
        ]
        XCTAssertFalse(ClaudeHookSettings.isOurs(mixed), "removing it would remove their command")
        XCTAssertTrue(ClaudeHookSettings.isOurs(ClaudeHookSettings.group))
    }

    // MARK: - The spool

    func testAFinishedEventFileNamesItsTerminal() {
        XCTAssertEqual(
            HookSpool.terminalID(ofFileNamed: "6F9619FF-8B86-D011-B42D-00C04FC964FF.1474.6594.json"), "6F9619FF-8B86-D011-B42D-00C04FC964FF"
        )
        XCTAssertNil(HookSpool.terminalID(ofFileNamed: "6F9619FF.1474.6594.tmp"), "still being written")
        XCTAssertNil(HookSpool.terminalID(ofFileNamed: ".1474.6594.json"), "no terminal")
        XCTAssertNil(HookSpool.terminalID(ofFileNamed: "a.b.c.json"))
        XCTAssertNil(HookSpool.terminalID(ofFileNamed: "notes.json"))
        XCTAssertNil(HookSpool.terminalID(ofFileNamed: ".DS_Store"))
    }

    /// The command as a shell runs it: a whole file named for the terminal when the folder is set,
    /// nothing when it is not, and success either way.
    func testTheHookCommandWritesOneWholeFileAndNothingOutsideTheHost() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hook-spool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func run(_ environment: [String: String]) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", HookSpool.command]
            process.environment = environment
            process.currentDirectoryURL = folder
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(Self.stopped.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationStatus
        }
        XCTAssertEqual(try run([HookSpool.folderVariable: folder.path, HookSpool.terminalVariable: "TERM-1"]), 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(files.count, 1, "\(files)")
        XCTAssertEqual(HookSpool.terminalID(ofFileNamed: files[0]), "TERM-1")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(files[0])), Data(Self.stopped.utf8))

        XCTAssertEqual(try run([:]), 0, "outside the host: nothing, and no failure for the agent to report")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
        XCTAssertEqual(
            try run([HookSpool.folderVariable: folder.path + "/missing", HookSpool.terminalVariable: "TERM-1"]), 0, "a folder that is gone")
    }

    func testTheSpoolIsDrainedOldestFirstAndEveryFinishedFileIsRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hook-drain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func put(_ name: String, _ text: String, age: TimeInterval) throws {
            let url = folder.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: url.path)
        }
        try put("B.2.2.json", Self.stopped, age: 10)
        try put("A.1.1.json", Self.submitted, age: 20)
        try put("A.3.3.json", "not json", age: 15)
        try put("A.4.4.tmp", Self.stopped, age: 30)
        try put("notes.txt", "theirs", age: 30)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("C.5.5.json"), withIntermediateDirectories: true)

        let taken = HookSpoolReader.drain(folder)
        XCTAssertEqual(taken.map(\.terminalID), ["A", "B"], "oldest first; the file that is not an event gives none")
        XCTAssertEqual(taken.map(\.event.kind), [.promptSubmitted("Reply with the single word ok"), .stopped])
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["A.4.4.tmp", "notes.txt", "C.5.5.json"],
            "finished files are removed, read or not; a file still being written, another's file and a folder are left")
        XCTAssertEqual(HookSpoolReader.drain(folder), [], "nothing is delivered twice")
        XCTAssertEqual(HookSpoolReader.drain(folder.appendingPathComponent("missing")), [])
    }
}
