//
//  CodexAdapter.swift
//  AgentSession
//
//  The Codex CLI adapter: its rollouts, read incrementally.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The Codex CLI adapter: reads `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl` (default
/// `~/.codex`, read-only) through the shared incremental ``TranscriptCache``. Parsing follows
/// Codex's own source (`codex-rs`) and is tested against sanitized real rollouts.
public struct CodexAdapter: AgentAdapter {
    /// `"Codex"`.
    public let name = "Codex"

    /// `codex`.
    public let processNames: Set<String> = ["codex"]

    private let index: CodexSessionIndex
    private let cache = TranscriptCache<CodexTranscriptState>()

    /// An adapter over the real Codex home (`$CODEX_HOME`, else `~/.codex`).
    public init() {
        let home =
            ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        self.init(sessionsRoot: home.appendingPathComponent("sessions", isDirectory: true))
    }

    /// Test seam: an adapter over any sessions folder.
    init(sessionsRoot: URL) { index = CodexSessionIndex(sessionsRoot: sessionsRoot) }

    public func latestSession(for root: URL) -> URL? { index.latestRollout(for: root) }

    public func events(for root: URL) -> [TimelineEvent] { cache.results(for: root, file: latestSession(for: root)).events }

    public func events(fromSession url: URL) -> [TimelineEvent] { cache.results(for: url, file: url).events }

    public func usage(for root: URL) -> AgentUsage? { cache.results(for: root, file: latestSession(for: root)).usage }

    public func summary(for root: URL) -> AgentSummary? { cache.results(for: root, file: latestSession(for: root)).summary }
}
