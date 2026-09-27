//
//  ApplyPatch.swift
//  AgentSession
//
//  The files an `apply_patch` body names.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The `apply_patch` format Codex defined (`codex-rs/apply-patch/src/parser.rs`) and Grok Build's
/// codex toolset reuses (`xai-grok-tools/src/implementations/codex/apply_patch`).
enum ApplyPatch {
    /// The files a patch body names, in order, as written (relative paths are the session's cwd's).
    static func paths(_ patch: String) -> [String] {
        let markers = ["*** Add File: ", "*** Update File: ", "*** Delete File: ", "*** Move to: "]
        var paths: [String] = []
        for line in patch.split(whereSeparator: \.isNewline) {
            for marker in markers where line.hasPrefix(marker) {
                let path = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty, !paths.contains(path) { paths.append(path) }
            }
        }
        return paths
    }
}
