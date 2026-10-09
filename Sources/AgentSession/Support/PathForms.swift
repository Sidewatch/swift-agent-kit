//
//  PathForms.swift
//  AgentSession
//
//  Every spelling of a folder's path an agent may have recorded as its working directory.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Every spelling of a folder's path an agent may have recorded as its working directory. An
/// agent records the KERNEL's cwd: symlinks resolved and `/private` kept for `/tmp`, `/var` and
/// `/etc`, where Foundation's `standardizedFileURL` strips `/private` from an existing path and
/// leaves symlinks alone. A lookup therefore tries the path as given, standardized, with symlinks
/// resolved, and each of those with `/private` restored.
enum PathForms {
    /// The roots whose kernel path carries a `/private` prefix.
    private static let privateRoots = ["/tmp", "/var", "/etc"]

    /// The spellings of `url`'s path, first the one given, without repeats.
    static func of(_ url: URL) -> [String] {
        var forms: [String] = []
        var seen = Set<String>()
        func add(_ path: String) {
            if seen.insert(path).inserted { forms.append(path) }
        }
        let standardized = url.standardizedFileURL
        for form in [url.path, standardized.path, url.resolvingSymlinksInPath().path, standardized.resolvingSymlinksInPath().path] {
            add(form)
            if privateRoots.contains(where: { form == $0 || form.hasPrefix($0 + "/") }) { add("/private" + form) }
        }
        return forms
    }
}
