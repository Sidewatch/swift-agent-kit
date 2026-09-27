//
//  SessionPaths.swift
//  AgentSession
//
//  A path an agent's tool call named, made absolute against the project it ran in.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Agents whose edit tools accept a relative path (Gemini's `getTargetDir()`, Grok Build's
/// `resolve_model_path`) record it as the model wrote it; readers need it absolute.
enum SessionPaths {
    /// `path` made absolute: `~` is the home folder, a relative path is `root`'s.
    static func absolute(_ path: String, in root: URL) -> String {
        if path.hasPrefix("/") { return path }
        if path == "~" || path.hasPrefix("~/") { return (path as NSString).expandingTildeInPath }
        return root.appendingPathComponent(path).standardizedFileURL.path
    }

    /// `event` with its file path made absolute against `root`.
    static func resolved(_ event: TimelineEvent, in root: URL) -> TimelineEvent {
        guard let path = event.filePath, !path.hasPrefix("/") else { return event }
        var event = event
        event.filePath = absolute(path, in: root)
        return event
    }

    /// `summary` with every path made absolute against `root`.
    static func resolved(_ summary: AgentSummary?, in root: URL) -> AgentSummary? {
        summary.map { AgentSummary(editedFiles: Set($0.editedFiles.map { absolute($0, in: root) })) }
    }
}
