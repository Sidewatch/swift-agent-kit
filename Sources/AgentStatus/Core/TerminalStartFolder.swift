//
//  TerminalStartFolder.swift
//  AgentStatus
//
//  Where a docked shell starts while a project is open, and when an idle one moves to a new project.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// The rule for a docked terminal's folder while a project is open. A shell that would inherit a
/// folder (a restored tab's saved one, the focused shell's live one) keeps it while it is inside the
/// project, a subfolder included, and starts in the project otherwise: a terminal saved in the home
/// folder, or in the last project, never comes back there under a different one. A folder named
/// explicitly (Open in Terminal on a folder) is not this rule's business.
///
/// Inside is decided by the paths as spelled and by their real paths, because a shell reports where
/// it is resolved (`/private/var/…`, a link's target) while a project keeps the path it was opened by.
public enum TerminalStartFolder {
    /// The folder a shell starts in that would otherwise inherit `inherited`.
    ///
    /// - Parameters:
    ///   - inherited: The folder the shell would inherit; nil when there is none.
    ///   - project: The open project's folder; nil when no project is open.
    /// - Returns: `inherited` when no project is open or it is inside `project` (the project itself
    ///   included), else `project`.
    public static func folder(inheriting inherited: URL?, project: URL?) -> URL? {
        guard let project else { return inherited }
        guard let inherited, isInside(inherited, project) else { return project }
        return inherited
    }

    /// Whether an idle shell standing in `current` moves into `project` when that project opens: it
    /// does when it stands outside it, or nowhere known. A shell already in the project, or in one of
    /// its folders, stays where it is.
    ///
    /// - Parameters:
    ///   - project: The folder just opened as the project.
    ///   - current: Where the shell stands; nil when that cannot be read.
    /// - Returns: True when the shell should move.
    public static func moves(to project: URL, from current: URL?) -> Bool {
        guard let current else { return true }
        return !isInside(current, project)
    }

    /// `folder` is `project` or inside it, by spelling or by real path.
    private static func isInside(_ folder: URL, _ project: URL) -> Bool {
        if folder.isInside(project) { return true }
        guard let real = folder.realPath, let root = project.realPath else { return false }
        return real.isInside(root)
    }
}
