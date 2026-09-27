//
//  AttentionNotice.swift
//  AgentStatus
//
//  Whether a change in an agent's state deserves a notification, and what it should say.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The rule behind an "agent needs you" / "agent finished" notification. A notification is for
/// a state the person cannot see: the app is in the background, or the pane is not on screen.
/// One is never posted for the pane in front of them — the tab badge already says it.
public enum AttentionNotice: Equatable, Sendable {
    /// A prompt is on screen waiting for an answer.
    case needsYou(prompt: String?)
    /// The agent's run ended and the shell is back at its prompt.
    case finished

    /// Whether to post: the feature on, and the pane not in plain sight.
    public static func shouldNotify(enabled: Bool, appActive: Bool, paneVisible: Bool) -> Bool {
        enabled && !(appActive && paneVisible)
    }

    /// The notification's title and body for an agent named `agent` ("Claude", "Codex"…).
    public func text(agent: String) -> (title: String, body: String) {
        let name = agent.isEmpty ? String(localized: "Agent", bundle: .module, comment: "Stand-in agent name in a notification title when the agent's name is unknown") : agent
        switch self {
        case .needsYou(let prompt):
            return (String(localized: "\(name) needs you", bundle: .module, comment: "Notification title; the argument is the agent's name, such as Claude"),
                    prompt?.trimmingCharacters(in: .whitespaces).nonEmpty ?? String(localized: "A prompt is waiting in the terminal.", bundle: .module))
        case .finished:
            return (String(localized: "\(name) finished", bundle: .module, comment: "Notification title; the argument is the agent's name, such as Claude"),
                    String(localized: "Back at the prompt.", bundle: .module, comment: "Notification body: the agent has finished and is back at its input prompt"))
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
