//
//  ClaudeCodeAdapter.swift
//  AgentSession
//
//  The Claude Code adapter: reads `~/.claude/projects/<encoded-cwd>/<session>.jsonl`
//  (read-only) and maps it onto the agent-agnostic model. The reference adapter.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The Claude Code adapter: reads `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`
/// (read-only) and maps it onto the agent-agnostic model.
///
/// **Polling is O(appended bytes)**: the three readers share one incremental
/// ``TranscriptCache``, whose results always equal a full re-parse. Copies share the cache, so
/// keep one adapter and poll it; a new one starts cold (``Agents/all`` holds a long-lived one).
public struct ClaudeCodeAdapter: AgentAdapter {

    /// `"Claude Code"`.
    public let name = "Claude Code"

    /// The `~/.claude/projects` container the adapter scans. Internal seam so
    /// tests can point the adapter at a temp directory instead of the real home.
    let projectsRoot: URL

    /// The incremental transcript cache backing the three readers. A reference
    /// type on purpose: copies of this adapter value share the one cache.
    private let cache = TranscriptCache<ClaudeTranscriptState>()

    /// Creates an adapter that reads the real `~/.claude/projects` container.
    public init() {
        self.projectsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Test seam: read transcripts from an arbitrary projects container.
    init(projectsRoot: URL) { self.projectsRoot = projectsRoot }

    /// The latest `.jsonl` transcript Claude Code recorded for `root`.
    public func latestSession(for root: URL) -> URL? { latestSessionFile(for: root) }

    // MARK: - Locating the transcript

    /// The `~/.claude/projects/<encoded-cwd>` directory for `root`, or `nil` when
    /// Claude Code has never run there.
    func projectDir(for root: URL) -> URL? {
        // ONE encoding for the package: the measured per-UTF-16-unit fold in ClaudeSessionIndex.
        let dir = projectsRoot.appendingPathComponent(ClaudeSessionIndex.encode(root), isDirectory: true)
        return dir.isExistingDirectory ? dir : nil
    }

    /// The most recently modified `.jsonl` transcript in the project directory —
    /// "the current session" — or `nil` when there is none.
    func latestSessionFile(for root: URL) -> URL? {
        guard let dir = projectDir(for: root) else { return nil }
        return Files.newest(in: dir, extensions: ["jsonl"])
    }

    // MARK: - Readers (served from the incremental cache)

    /// Token/cost telemetry aggregated over the latest transcript, or `nil` when
    /// there is no transcript or it carries no usage records.
    ///
    /// Cost is estimated from approximate per-model list prices; duplicate JSONL
    /// lines for the same API response (same `message.id`/`requestId`) count once.
    /// - Note: The *first* call on a large session parses the whole file, so call off the
    ///   main thread.
    public func usage(for root: URL) -> AgentUsage? {
        cache.results(for: root, file: latestSessionFile(for: root)).usage
    }

    /// The activity timeline parsed from the latest transcript, oldest first, capped to the most
    /// recent ``EventBuffer/cap`` events. Malformed lines are skipped.
    /// - Note: The *first* call on a large session parses the whole file, so call off the
    ///   main thread.
    public func events(for root: URL) -> [TimelineEvent] {
        cache.results(for: root, file: latestSessionFile(for: root)).events
    }

    /// The activity timeline parsed from one transcript file, bypassing the `~/.claude/projects`
    /// lookup entirely — the seam that lets this adapter be exercised against a checked-in
    /// fixture rather than a live session.
    ///
    /// Keyed in the cache by the file's own path (the cache's `root` parameter is only ever a
    /// key), so a fixture parse can't collide with, or invalidate, a live poll of a project.
    public func events(fromSession url: URL) -> [TimelineEvent] {
        cache.results(for: url, file: url).events
    }

    /// The edited-files set from the latest transcript, or `nil` when there is no
    /// transcript at all.
    /// - Note: The *first* call on a large session parses the whole file, so call off the
    ///   main thread.
    public func summary(for root: URL) -> AgentSummary? {
        cache.results(for: root, file: latestSessionFile(for: root)).summary
    }

    // MARK: - Test seams

    /// The number of transcript *content* reads performed so far by this
    /// adapter's cache (`stat`-only polls do not count). Verifies the zero-read
    /// fast path in tests.
    var transcriptReadCount: Int { cache.readCount }

    /// Total transcript bytes read so far by this adapter's cache. With
    /// incremental polling this grows by roughly the appended bytes per poll,
    /// not the file size. Verifies appended-only reads in tests.
    var transcriptBytesRead: Int { cache.bytesRead }
}
