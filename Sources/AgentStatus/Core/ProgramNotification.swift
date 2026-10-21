//
//  ProgramNotification.swift
//  AgentStatus
//
//  A program's own notification request (OSC 777), and the title it is shown under.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A notification a terminal program asked for with OSC 777 (`ESC ] 777 ; notify ; title ; body BEL`),
/// the convention urxvt started and agents and build tools use to say "done".
public struct ProgramNotification: Equatable, Sendable {
    /// The program's title.
    public let title: String
    /// The program's body; it may itself hold `;`.
    public let body: String

    /// A notification of `title` and `body`.
    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    /// The notification in an OSC 777 payload (the bytes after `777;`), parsed as SwiftTerm parses it:
    /// UTF-8, `notify;title;body` with every later `;` belonging to the body. Nil for anything else
    /// (`progress;…`, a missing body, bytes that are not UTF-8).
    public init?(osc777 payload: some Sequence<UInt8>) {
        guard let text = String(bytes: Array(payload), encoding: .utf8) else { return nil }
        let parts = text.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, parts[0] == "notify" else { return nil }
        self.init(title: parts[1], body: parts[2...].joined(separator: ";"))
    }

    /// The title as a notification shows it: prefixed with the program that asked ("claude: Build
    /// finished"), so a program cannot pass itself off as another or as the host; the bare title when
    /// the program is unknown.
    public func displayTitle(program: String?) -> String {
        guard let program = program?.trimmingCharacters(in: .whitespaces), !program.isEmpty else { return title }
        return "\(program): \(title)"
    }
}
