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
    /// The trimmed first line of `s` that holds anything, at most `max` characters with the ellipsis
    /// (FoundationExtensions `firstLine` / `clipped(to:)`).
    static func firstLine(_ s: String, _ max: Int = 160) -> String { s.firstLine.clipped(to: max) }

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
