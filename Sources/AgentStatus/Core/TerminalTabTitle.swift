//
//  TerminalTabTitle.swift
//  AgentStatus
//
//  What a terminal tab is called while an agent runs in it.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The name on a terminal's tab. A name the person gave it stands. Otherwise a program that titled
/// its own window (most agents do, with what they are working on) keeps that title; an agent that
/// did not is named by what it was last asked, so two of them can be told apart; and with neither,
/// the tab is the program's name as before.
public enum TerminalTabTitle {
    /// The most characters of a prompt a tab shows.
    public static let promptLimit = 40
    /// The tab's title.
    ///
    /// - Parameters:
    ///   - custom: The name the person gave the tab, if any.
    ///   - program: The title the terminal has from its program or shell.
    ///   - agentTitledItself: Whether the agent now running set that title itself.
    ///   - prompt: What the agent was last asked, already known to be this terminal's.
    public static func title(custom: String?, program: String, agentTitledItself: Bool, prompt: String?) -> String {
        if let custom, !custom.isEmpty { return custom }
        if !agentTitledItself, let asked = prompt.flatMap(clipped) { return asked }
        return program
    }

    /// A prompt as a tab shows it: its first line that says anything, runs of white space made one
    /// space, cut to ``promptLimit`` with an ellipsis. Nil for a prompt with nothing in it.
    public static func clipped(_ prompt: String) -> String? {
        guard
            let line = prompt.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: {
                !$0.isEmpty
            })
        else { return nil }
        let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return words.count > promptLimit ? String(words.prefix(promptLimit - 1)).trimmingCharacters(in: .whitespaces) + "…" : words
    }
}
