//
//  TurnBoundary+Transcript.swift
//  AgentSession
//
//  One turn as a Markdown document: the whole prompt, the agent's replies, what it changed.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension TurnBoundary {

    /// The turn as a Markdown document to read in full: who asked and when, the whole prompt, the
    /// agent's replies in order, the files it edited and the commands it ran.
    ///
    /// - Parameter events: The timeline the turn indexes into.
    /// - Returns: The document, or `""` when the turn's indices are not in `events`.
    public func transcript(in events: [TimelineEvent]) -> String {
        guard start <= end, events.indices.contains(start), events.indices.contains(end) else { return "" }
        let opening = events[start]
        let span = events[start...end]
        let asker = opening.source == .agent
            ? String(localized: "Sent by the agent tool, not typed", bundle: .module, comment: "Turn document: under the title of a turn Claude Code started itself")
            : opening.title
        var doc = "# \(opening.detail)\n\n*\(asker)\(timestamp.isEmpty ? "" : " · \(timestamp)")*\n\n\(opening.fullText ?? opening.detail)\n"

        let replies = span.filter { $0.kind == .assistantText }.map { $0.fullText ?? $0.detail }
        if !replies.isEmpty {
            doc += "\n## " + String(localized: "Replies", bundle: .module, comment: "Turn document: heading over the agent's replies") + "\n\n"
            doc += replies.joined(separator: "\n\n---\n\n") + "\n"
        }
        var seen = Set<String>()
        let files = span.compactMap { $0.kind == .fileEdit ? $0.filePath : nil }.filter { seen.insert($0).inserted }
        if !files.isEmpty {
            doc += "\n## " + String(localized: "Files edited", bundle: .module, comment: "Turn document: heading over the files the turn edited") + "\n\n"
            doc += files.map { "- `\($0)`" }.joined(separator: "\n") + "\n"
        }
        let commands = span.compactMap(\.command)
        if !commands.isEmpty {
            doc += "\n## " + String(localized: "Commands", bundle: .module, comment: "Turn document: heading over the shell commands the turn ran") + "\n\n"
            doc += "```sh\n" + commands.joined(separator: "\n") + "\n```\n"
        }
        return doc
    }
}
