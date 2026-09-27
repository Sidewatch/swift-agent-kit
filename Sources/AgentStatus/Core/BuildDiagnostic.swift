//
//  BuildDiagnostic.swift
//  AgentStatus
//
//  One compiler or linter diagnostic, parsed from a line of terminal output.
//
//  Created by David Sherlock on 9/11/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One compiler or linter diagnostic, parsed from a line of terminal output, so a host can show
/// it next to the line the toolchain named after it has scrolled away. It reads facts the
/// toolchain printed and nothing more. **Never add a rule that infers a diagnostic the terminal
/// did not print**; that is a linter, and the agent in the terminal already has one.
public struct BuildDiagnostic: Equatable, Sendable {

    /// How the toolchain labelled it. Kept as the toolchain's own word, not re-ranked.
    public enum Severity: String, Sendable {
        case error, warning, note
    }

    /// Path exactly as the toolchain printed it: absolute for most compilers, repo-relative
    /// for some linters. Resolution against the project root is the caller's job.
    public let path: String
    /// 1-based line.
    public let line: Int
    /// 1-based column, when the toolchain gave one.
    public let column: Int?
    /// The toolchain's own label.
    public let severity: Severity
    /// The message after the label, trimmed.
    public let message: String

    /// Creates a diagnostic by hand — a host's own source, or a test.
    public init(path: String, line: Int, column: Int?, severity: Severity, message: String) {
        self.path = path
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
    }

    /// `path:line:col: severity: message` — the shape Swift, clang, gcc, and most Unix tools
    /// print, with the column optional. Anchored at the start so a sentence that merely
    /// contains a colon-separated path cannot match.
    ///
    /// Deliberately ONE format. Every extra dialect is another chance to mark the wrong line in
    /// someone's file, and a wrong gutter mark is worse than a missing one because it is
    /// believed. A format nobody here has seen output from does not get a pattern.
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(\S[^:]*?):(\d+)(?::(\d+))?:\s*(error|warning|note)\s*:\s*(.+?)\s*$"#,
        options: [.caseInsensitive])

    /// Parses one line of terminal output.
    ///
    /// - Parameter text: A single line, ANSI escapes already stripped (see ``stripANSI(_:)``).
    /// - Returns: The diagnostic, or `nil` when the line is ordinary output.
    public static func parse(_ text: String) -> BuildDiagnostic? {
        let ns = text as NSString
        guard ns.length > 0, ns.length < 4_000,  // a pathological line is not a diagnostic
            let m = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
            m.numberOfRanges == 6
        else { return nil }

        let path = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, let line = Int(ns.substring(with: m.range(at: 2))), line > 0,
            // A bare word with no separator or extension is prose, not a path: "warning" in
            // "note:12: warning: ..." style log lines would otherwise mark a phantom file.
            path.contains("/") || path.contains(".")
        else { return nil }

        let column = m.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 3)))
        guard let severity = Severity(rawValue: ns.substring(with: m.range(at: 4)).lowercased())
        else { return nil }

        return BuildDiagnostic(
            path: path, line: line, column: column, severity: severity,
            message: ns.substring(with: m.range(at: 5)).trimmingCharacters(in: .whitespaces))
    }

    /// Parses many lines, keeping the LAST diagnostic per (file, line).
    ///
    /// Last wins because a build prints its history: a line fixed in the second run still has
    /// its error from the first sitting further up the scrollback, and marking that would be
    /// showing you a problem you already solved. Locations keep first-seen order.
    ///
    /// - Parameter lines: Terminal rows, oldest first, ANSI already stripped.
    /// - Returns: One diagnostic per location, oldest location first.
    public static func parseAll(_ lines: [String]) -> [BuildDiagnostic] {
        var byKey: [String: BuildDiagnostic] = [:]
        var order: [String] = []
        for text in lines {
            guard let d = parse(text) else { continue }
            let key = "\(d.path)|\(d.line)"
            if byKey[key] == nil { order.append(key) }
            byKey[key] = d
        }
        return order.compactMap { byKey[$0] }
    }

    /// Strips ANSI CSI and OSC escapes so a coloured compiler line parses like a plain one.
    ///
    /// - Parameter text: One terminal row, escapes and all.
    /// - Returns: The row with every `ESC[…` sequence (to its final byte `@`–`~`) and every
    ///   `ESC]…` sequence (to BEL or the next ESC) removed; other text untouched.
    public static func stripANSI(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }  // the overwhelmingly common case
        var out = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            guard scalars[i] == "\u{1B}" else { out.append(scalars[i]); i += 1; continue }
            i += 1
            guard i < scalars.count else { break }
            if scalars[i] == "[" {  // CSI: ends at a final byte @–~
                i += 1
                while i < scalars.count, !(scalars[i].value >= 0x40 && scalars[i].value <= 0x7E) { i += 1 }
                i += 1
            } else if scalars[i] == "]" {  // OSC: ends at BEL or ST
                i += 1
                while i < scalars.count, scalars[i] != "\u{07}", scalars[i] != "\u{1B}" { i += 1 }
                i += 1
            } else {
                i += 1
            }
        }
        return String(out)
    }
}
