//
//  TurnBoundary+Search.swift
//  AgentSession
//
//  Whether a turn mentions what the person is looking for.
//
//  Created by David Sherlock on 9/28/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension TurnBoundary {

    /// Whether every word of `query` appears somewhere in the turn: its whole prompt, the agent's
    /// replies, the files it touched, the commands it ran, or a tool call's detail. Case and
    /// diacritics are ignored; an empty query matches every turn.
    ///
    /// - Parameters:
    ///   - query: What the person typed, split on whitespace.
    ///   - events: The timeline the turn indexes into.
    public func matches(_ query: String, in events: [TimelineEvent]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        guard start <= end, events.indices.contains(start), events.indices.contains(end) else { return false }
        let haystack = events[start...end].map(\.searchableText).joined(separator: "\n")
        return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

extension TimelineEvent {
    /// Everything a search can find in this entry.
    var searchableText: String {
        [detail, fullText ?? "", filePath ?? "", command ?? ""].joined(separator: "\n")
    }
}
