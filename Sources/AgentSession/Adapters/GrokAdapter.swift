//
//  GrokAdapter.swift
//  AgentSession
//
//  The Grok Build adapter.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The Grok Build adapter (xAI's `grok` CLI): reads
/// `~/.grok/sessions/<encoded cwd>/<id>/chat_history.jsonl` (under `$GROK_HOME` when set,
/// read-only) through the shared incremental ``TranscriptCache``, and the usage Grok keeps beside
/// it. Parsing follows Grok Build's own source (`xai-org/grok-build`) and is tested against a
/// sanitized real session.
public struct GrokAdapter: AgentAdapter {
    /// `"Grok"`.
    public let name = "Grok"

    /// `grok`.
    public let processNames: Set<String> = ["grok"]

    private let index: GrokSessionIndex
    private let cache = TranscriptCache<GrokTranscriptState>()

    /// An adapter over the real Grok home (`$GROK_HOME`, else `~/.grok`).
    public init() {
        let home = ProcessInfo.processInfo.environment["GROK_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true)
        self.init(sessionsRoot: home.appendingPathComponent("sessions", isDirectory: true))
    }

    /// Test seam: an adapter over any sessions folder.
    init(sessionsRoot: URL) { index = GrokSessionIndex(sessionsRoot: sessionsRoot) }

    public func latestSession(for root: URL) -> URL? { index.latestSession(for: root) }

    public func events(for root: URL) -> [TimelineEvent] {
        cache.results(for: root, file: latestSession(for: root)).events.map { SessionPaths.resolved($0, in: root) }
    }

    public func events(fromSession url: URL) -> [TimelineEvent] { cache.results(for: url, file: url).events }

    public func usage(for root: URL) -> AgentUsage? { latestSession(for: root).flatMap(GrokSessionIndex.usage(ofSession:)) }

    public func summary(for root: URL) -> AgentSummary? {
        SessionPaths.resolved(cache.results(for: root, file: latestSession(for: root)).summary, in: root)
    }
}
