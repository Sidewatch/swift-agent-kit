//
//  URL+CanonicalPath.swift
//  AgentSessionTests
//
//  One spelling for a file's path, so a URL a listing returned compares equal to the one a test built.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension URL {
    /// The path with symlinks resolved and `/private` dropped: a directory listing returns
    /// `/private/var/…` for a file a test wrote as `/var/…`.
    var canonicalPath: String { resolvingSymlinksInPath().path }
}
