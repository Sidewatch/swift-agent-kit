//
//  ClaudeHookPayload.swift
//  AgentStatus
//
//  Reading the JSON Claude Code hands a hook.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// The JSON Claude Code writes to a hook's standard input (`hook_event_name`, `session_id`,
/// `transcript_path`, `cwd`, and the event's own fields), read into an ``AgentHookEvent``. Checked
/// against Claude Code's hooks reference and against payloads captured from Claude Code 2.1.323.
///
/// Only what a host watching from outside needs is read. A permission request's own event
/// (`PermissionRequest`) and tool events are not: nothing here answers the agent or decides for it.
public enum ClaudeHookPayload {
    /// The longest payload read. A prompt or a last message can be long; nothing a hook sends is this long.
    public static let sizeLimit = 1 << 20
    /// The most characters of a prompt or message kept.
    public static let textLimit = 4_000

    /// The event in `data`, or nil for anything that is not one this reads: another event, a
    /// payload with no session, text that is not a JSON object, or one past ``sizeLimit``.
    public static func event(from data: Data) -> AgentHookEvent? {
        guard data.count <= sizeLimit, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let name = object["hook_event_name"] as? String, let session = text(object["session_id"]),
            let kind = kind(name, object)
        else { return nil }
        return AgentHookEvent(
            kind: kind, sessionID: session, transcriptPath: text(object["transcript_path"]),
            directory: text(object["cwd"]))
    }

    private static func kind(_ name: String, _ object: [String: Any]) -> AgentHookEvent.Kind? {
        switch name {
        case "SessionStart": return .sessionStarted
        case "UserPromptSubmit": return .promptSubmitted(clipped(object["prompt"]) ?? "")
        case "Stop": return .stopped
        case "SessionEnd": return .sessionEnded
        case "Notification":
            guard let need = need(object["notification_type"] as? String) else { return nil }
            return .needsYou(need, message: clipped(object["message"]))
        default: return nil
        }
    }

    /// What a notification says the agent is waiting for; nil for one that is not a wait (a sign-in
    /// that succeeded, a quota notice, the idle reminder that follows a finished turn).
    static func need(_ notificationType: String?) -> ProgramStatusKind? {
        switch notificationType {
        case "permission_prompt": return .permission
        case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input": return .question
        default: return nil
        }
    }

    /// A field's text without surrounding white space; nil when it is not text or says nothing.
    private static func text(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private static func clipped(_ value: Any?) -> String? {
        text(value).map { String($0.prefix(textLimit)) }
    }
}
