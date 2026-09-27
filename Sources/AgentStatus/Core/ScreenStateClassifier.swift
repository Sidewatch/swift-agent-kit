//
//  ScreenStateClassifier.swift
//  AgentStatus
//
//  The no-hooks fallback for "is the agent waiting on me?": classifies the terminal's visible
//  screen text as a prompt (a numbered choice, a y/n, a known ask phrase) or as working (an
//  interrupt hint is showing).
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The no-hooks fallback for "is the agent waiting on me?": classifies the terminal's visible
/// screen text as a prompt (a numbered choice, a y/n, a known ask phrase) or as working (an
/// interrupt hint is showing).
public enum ScreenStateClassifier {
    /// Numbered choice with a selection cursor: Claude Code ("❯ 1. Yes"), Gemini ("● 1. Yes,
    /// allow once"), Codex ("> 1. Yes").
    private static let numberedChoice = try! NSRegularExpression(pattern: #"^\s*[❯>●▸►]\s*\d+\.\s"#)
    /// A yes/no question in any of the usual spellings.
    private static let yesNo = try! NSRegularExpression(pattern: #"(\(y/n\)|\[y/n\]|\[Y/n\]|\[y/N\]|\(yes/no\))"#, options: [.caseInsensitive])
    /// Plain-language permission prompts — only when phrased as a question.
    private static let asks: [String] = [
        "do you want to proceed", "do you want to make this edit", "do you want to allow",
        "allow execution", "allow this", "allow once", "approve", "permission",
        "press enter to continue", "waiting for your", "what would you like to do",
        // Claude Code 2.1.2xx: a workflow's confirmation, and an MCP server's elicitation dialog.
        "run a dynamic workflow", "requests your input",
    ]
    /// A dialog's footer: "esc to cancel" beside "enter to confirm" / "enter to select" is a
    /// prompt waiting on a choice (Claude Code's plan approval, model picker, AskUserQuestion),
    /// whatever the question above it says. "esc to cancel" ALONE is a working marker.
    private static let dialogCancel = "esc to cancel"
    private static let dialogConfirms = ["enter to confirm", "enter to select", "enter to submit"]
    private static let workingMarkers: [String] = ["esc to interrupt", "esc to cancel", "ctrl+c to interrupt", "ctrl-c to interrupt"]

    /// Classifies the bottom rows of a screen (top→bottom order). Nil when nothing on screen
    /// says either way — which is most of the time, and the honest answer.
    public static func classify(_ rows: [String]) -> ScreenState? {
        let trimmed = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.map { $0.lowercased() }
        // A prompt outranks a working marker: Claude keeps "esc to interrupt" on screen
        // while its permission dialog is up, and the dialog is what matters.
        if promptLine(rows) != nil { return .waitingForInput }
        if lower.contains(where: { l in workingMarkers.contains(where: { l.contains($0) }) }) { return .working }
        return nil
    }

    /// The line that makes the screen a prompt — the question or the choice the cursor sits on —
    /// or nil when nothing on it asks. What a notification quotes.
    public static func promptLine(_ rows: [String]) -> String? {
        let trimmed = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lower = trimmed.map { $0.lowercased() }
        for (i, line) in trimmed.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if numberedChoice.firstMatch(in: line, range: range) != nil { return question(before: i, in: trimmed) ?? line }
            if yesNo.firstMatch(in: line, range: range) != nil { return line }
            if asks.contains(where: { lower[i].contains($0) }), lower[i].contains("?") || lower[i].hasSuffix(":") || lower[i].contains("requests your input") { return line }
        }
        if let footer = lower.firstIndex(where: { $0.contains(dialogCancel) && dialogConfirms.contains(where: $0.contains) }) {
            return question(before: footer, in: trimmed) ?? trimmed[footer]
        }
        return nil
    }

    /// The nearest line above `index` that reads as the question a choice answers.
    private static func question(before index: Int, in rows: [String]) -> String? {
        rows[..<index].last { $0.contains("?") }
    }
}
