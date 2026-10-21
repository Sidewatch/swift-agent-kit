//
//  BuildDiagnostic+Marks.swift
//  AgentStatus
//
//  Diagnostics as gutter marks: one severity per file and line, the most serious winning.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension BuildDiagnostic.Severity {
    /// How serious it is: an error over a warning over a note.
    var rank: Int {
        switch self {
        case .error: 2
        case .warning: 1
        case .note: 0
        }
    }
}

public extension BuildDiagnostic {
    /// `diagnostics` (from ``parseAll(_:)``) as marks: severity by file and 1-based line, the file being
    /// what `resolve` makes of the printed path (an absolute path that exists), and a diagnostic whose
    /// path does not resolve dropped — marking the wrong file is worse than marking none. Two printed
    /// paths naming one file merge, the more serious severity winning on a shared line.
    static func marks(_ diagnostics: [BuildDiagnostic], resolve: (String) -> String?) -> [String: [Int: Severity]] {
        var marks: [String: [Int: Severity]] = [:]
        for diagnostic in diagnostics {
            guard let file = resolve(diagnostic.path) else { continue }
            if let existing = marks[file]?[diagnostic.line], existing.rank >= diagnostic.severity.rank { continue }
            marks[file, default: [:]][diagnostic.line] = diagnostic.severity
        }
        return marks
    }

    /// A printed path as an absolute path that exists, or nil: an absolute path is checked as is, a
    /// relative one against `cwd` (the directory the command ran in) — toolchains print whatever they
    /// were given. Nothing is guessed: a path that does not resolve is dropped. `exists` is the file
    /// check (the file system's by default; a test passes its own).
    static func resolvedPath(_ printed: String, cwd: URL?, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> String?
    {
        let candidate: URL? = printed.hasPrefix("/") ? URL(fileURLWithPath: printed) : cwd?.appendingPathComponent(printed)
        guard let path = candidate?.standardizedFileURL.path, exists(path) else { return nil }
        return path
    }
}
