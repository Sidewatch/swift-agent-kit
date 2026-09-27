//
//  GeminiAdapter.swift
//  AgentSession
//
//  The Gemini CLI adapter.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The Gemini CLI adapter: reads `~/.gemini/tmp/<project>/chats/session-*.jsonl` (the runtime
/// folder under `$GEMINI_CLI_HOME` when set, read-only) through the shared incremental
/// ``TranscriptCache``. Parsing follows Gemini's own source (`packages/core`) and is tested against
/// a sanitized real session. Sessions from before Gemini 0.40, one `.json` document each, are
/// not read.
public struct GeminiAdapter: AgentAdapter {
    /// `"Gemini"`.
    public let name = "Gemini"

    /// `gemini`.
    public let processNames: Set<String> = ["gemini"]

    private let index: GeminiSessionIndex
    private let cache = TranscriptCache<GeminiTranscriptState>()

    /// An adapter over the real Gemini runtime folders: `$GEMINI_CLI_HOME/.gemini` (default
    /// `~/.gemini`) and `~/.cache/.gemini`, where a Seatbelt-sandboxed run writes.
    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let geminiHome = ProcessInfo.processInfo.environment["GEMINI_CLI_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? home
        self.init(runtimeRoots: [
            geminiHome.appendingPathComponent(".gemini", isDirectory: true),
            home.appendingPathComponent(".cache/.gemini", isDirectory: true),
        ])
    }

    /// Test seam: an adapter over any runtime folders.
    init(runtimeRoots: [URL]) { index = GeminiSessionIndex(runtimeRoots: runtimeRoots) }

    public func latestSession(for root: URL) -> URL? { index.latestSession(for: root) }

    public func events(for root: URL) -> [TimelineEvent] {
        cache.results(for: root, file: latestSession(for: root)).events.map { SessionPaths.resolved($0, in: root) }
    }

    public func events(fromSession url: URL) -> [TimelineEvent] { cache.results(for: url, file: url).events }

    public func usage(for root: URL) -> AgentUsage? { cache.results(for: root, file: latestSession(for: root)).usage }

    public func summary(for root: URL) -> AgentSummary? {
        // Gemini's edit tools take a path relative to the project root (`tools/edit.ts`).
        SessionPaths.resolved(cache.results(for: root, file: latestSession(for: root)).summary, in: root)
    }
}
