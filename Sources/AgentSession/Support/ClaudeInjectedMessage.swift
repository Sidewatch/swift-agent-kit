//
//  ClaudeInjectedMessage.swift
//  AgentSession
//
//  The messages Claude Code writes into a session itself, in the person's place.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Claude Code delivers some messages as user turns that no person typed: a background task
/// finishing (`<task-notification>`, `origin.kind: "task-notification"`) and a sub-agent's report
/// (`<agent-message from="…">`). Queued while the agent works, they reach the transcript as a
/// `queue-operation` with no origin at all, so the text is the only witness.
enum ClaudeInjectedMessage {
    /// A readable title for a message Claude Code wrote, or nil when a person wrote it.
    static func title(_ text: String) -> String? {
        let t = text.trimmed
        if t.hasPrefix("<task-notification>") {
            return element("summary", in: t)?.nonEmpty
                ?? String(
                    localized: "A background task finished", bundle: .module,
                    comment: "Timeline: a turn Claude Code started itself when a background task ended")
        }
        if t.hasPrefix("<agent-message") {
            return String(
                localized: "Report from a sub-agent", bundle: .module,
                comment: "Timeline: a turn Claude Code started itself with a sub-agent's report")
        }
        return nil
    }

    /// The text of the first `<name>…</name>` element in `text`.
    private static func element(_ name: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(name)>"), let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex)
        else { return nil }
        return String(text[open.upperBound..<close.lowerBound]).trimmed
    }
}
