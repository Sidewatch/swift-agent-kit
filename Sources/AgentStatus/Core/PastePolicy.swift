//
//  PastePolicy.swift
//  AgentStatus
//
//  When pasting text into a terminal would run several commands at once.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The rule for asking before a paste into a terminal. A program that has turned on bracketed paste
/// (DEC mode 2004) receives a paste whole, its line feeds as text; one that has not receives every line
/// feed as Return, so a pasted block runs line by line as separate commands. A single line never asks,
/// even with a trailing break: pasting a command and Return is what pasting one line means everywhere.
public enum PastePolicy {
    /// How many separate commands `text` would type into a program without bracketed paste (blank lines
    /// not counted), or nil when the paste is safe: one line, or `bracketed`.
    public static func commandsTyped(by text: String, bracketed: Bool) -> Int? {
        guard !bracketed else { return nil }
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).count
        return lines > 1 ? lines : nil
    }
}
