//
//  EditReconciliation.swift
//  AgentSession
//
//  The files git shows changed against the files an agent says it edited, compared as the same
//  file however each side spells its path.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// The files git shows changed, set against the files an agent's transcript says it edited.
///
/// The two sides spell paths differently: the transcript holds the KERNEL's path (links resolved,
/// `/private` kept for `/tmp` and `/var`), the project is often opened through a link or as `/tmp/…`.
/// A plain or standardized comparison then calls every change "unmentioned". Both sides are reduced to
/// one ``identity(of:)`` first.
public enum EditReconciliation {
    /// The path compared on both sides: the real path (`realpath(3)`: links resolved, `/private` kept).
    /// For a path that no longer exists (a deleted file) its folder's real path plus its name, else the
    /// standardized path.
    public static func identity(of path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let real = url.realPath { return real }
        if let folder = url.deletingLastPathComponent().realPath { return folder.directoryPrefix + url.lastPathComponent }
        return url.standardizedFileURL.path
    }

    /// Whether `claimed` (a transcript's paths) names `file`, under ``identity(of:)``.
    public static func contains(_ claimed: some Sequence<String>, _ file: URL) -> Bool {
        let wanted = identity(of: file.path)
        return claimed.contains { identity(of: $0) == wanted }
    }

    /// `changed` split against `claimed`: the changed items no claimed path names (to mark as edits the
    /// agent never mentioned), and the claimed paths no changed item matches (edits it described that git
    /// does not show), sorted. `url` gives each item's file.
    public static func partition<Item>(
        changed: [Item], url: (Item) -> URL, claimed: some Sequence<String>
    ) -> (unmentioned: [Item], notChanged: [String]) {
        let claimedIDs = Dictionary(claimed.map { (identity(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let changedIDs = Set(changed.map { identity(of: url($0).path) })
        let unmentioned = changed.filter { claimedIDs[identity(of: url($0).path)] == nil }
        let notChanged = claimedIDs.filter { !changedIDs.contains($0.key) }.map(\.value).sorted()
        return (unmentioned, notChanged)
    }
}
