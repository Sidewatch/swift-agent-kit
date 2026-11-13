//
//  HookSpool.swift
//  AgentStatus
//
//  How a hook hands its event to the host: a file in a folder the host watches.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// How a hook reaches the host with no socket and no server: the host gives each terminal's shell
/// two environment variables, a folder and the terminal's id; the hook, which inherits them, writes
/// its event into that folder under a name beginning with the id, and the host reads the folder.
/// Outside the host's terminals the variables are unset and the hook does nothing.
public enum HookSpool {
    /// The environment variable naming the folder hooks write into.
    public static let folderVariable = "SIDEWATCH_HOOKS"
    /// The environment variable naming the terminal a hook runs in.
    public static let terminalVariable = "SIDEWATCH_TERMINAL"
    /// The extension of a finished event file. A hook writes under another name and renames, so a
    /// file with this extension is whole.
    public static let fileExtension = "json"

    /// The shell command a hook runs: standard input into a file named for the terminal, written
    /// under a temporary name and renamed so the host never reads half of it; nothing at all when
    /// the folder variable is unset; and never a failure the agent would report.
    public static let command =
        #"[ -n "$SIDEWATCH_HOOKS" ] && f="$SIDEWATCH_HOOKS/$SIDEWATCH_TERMINAL.$$.$RANDOM" && cat > "$f.tmp" && mv "$f.tmp" "$f.json"; true"#

    /// The terminal id a finished event file is named for (`<id>.<pid>.<random>.json`); nil for any
    /// other file, a temporary one included.
    public static func terminalID(ofFileNamed name: String) -> String? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[3] == Substring(fileExtension), !parts[0].isEmpty, parts[1].allSatisfy(\.isNumber),
            parts[2].allSatisfy(\.isNumber)
        else { return nil }
        return String(parts[0])
    }
}
