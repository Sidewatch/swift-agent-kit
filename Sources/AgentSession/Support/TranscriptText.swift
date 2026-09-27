//
//  TranscriptText.swift
//  AgentSession
//
//  How every transcript parser renders a prompt, a path and a time.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// How every transcript parser renders text for a timeline row — one rule for all agents.
enum TranscriptText {
    /// The trimmed first line of `s`, truncated to `max` characters with an ellipsis.
    static func firstLine(_ s: String, _ max: Int = 160) -> String {
        // `isNewline`: "\r\n" is one Character, so a "\n" split would keep a CRLF prompt whole.
        let line = s.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isNewline).first.map(String.init) ?? s
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > max ? String(t.prefix(max)) + "…" : t
    }

    /// The first line of inserted text long enough to be findable (skipping braces and blanks),
    /// to locate where an edit landed; nil when there is none.
    static func anchor(_ inserted: String) -> String? {
        // `isNewline`, never the Character "\n": a CRLF file keeps its endings in the inserted
        // text, and "\r\n" is ONE Character in Swift, so a "\n" split never divides it and the
        // anchor would be the whole text, which no single line can contain.
        for raw in inserted.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 4 { return String(t.prefix(200)) }
        }
        return nil
    }

    /// An absolute path as its last two components (`.../Dir/File.swift`).
    static func shortPath(_ p: String) -> String {
        let tail = p.pathTail()
        return tail == p ? p : ".../" + tail
    }

    /// An ISO-8601 timestamp as `HH:mm` on the viewer's clock, or the raw UTC `HH:MM` slice when
    /// it does not parse; empty for none.
    static func shortTime(_ iso: String?) -> String {
        guard let iso else { return "" }
        if let date = ISOTimestamp.date(iso) { return ClockFormat.hhmm(date) }
        guard let tPart = iso.split(separator: "T").dropFirst().first else { return "" }
        return String(tPart.prefix(5))
    }

    /// The row title of a prompt the person typed.
    static var promptTitle: String {
        String(localized: "You", bundle: .module, comment: "Timeline row title for a prompt the person typed to the agent")
    }
}
