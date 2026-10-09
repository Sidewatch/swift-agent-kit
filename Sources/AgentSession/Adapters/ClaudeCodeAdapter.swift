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

    /// `claude`.
    public let processNames: Set<String> = ["claude"]

    /// Finds the transcript under the `~/.claude/projects` container the adapter scans. A
    /// reference type, so copies of this adapter share its memory of what they found.
    let locator: ClaudeSessionLocator

    /// The incremental transcript cache backing the three readers. A reference
    /// type on purpose: copies of this adapter value share the one cache.
    private let cache = TranscriptCache<ClaudeTranscriptState>()

    /// Creates an adapter that reads the real `~/.claude/projects` container.
    public init() { self.init(projectsRoot: ClaudeSessionIndex.defaultProjectsRoot) }

    /// Test seam: read transcripts from an arbitrary projects container.
    init(projectsRoot: URL) { locator = ClaudeSessionLocator(projectsRoot: projectsRoot) }

    /// The `.jsonl` transcript Claude Code is writing for `root`: the newest among every project
    /// directory the path may be filed under, held while it is still being written.
    public func latestSession(for root: URL) -> URL? { locator.latestSession(for: root) }

    /// The directory of the newest session launched in a subfolder of `project`, or nil.
    public func latestSessionRoot(under project: URL) -> URL? { locator.latestSessionRoot(under: project) }

    /// Every existing `~/.claude/projects/<encoded-cwd>` directory for `root`; empty when Claude
    /// Code has never run there.
    func projectDirectories(for root: URL) -> [URL] { locator.projectDirectories(for: root) }

    // MARK: - Readers (served from the incremental cache)

    /// Token/cost telemetry aggregated over the latest transcript, or `nil` when
    /// there is no transcript or it carries no usage records.
    ///
    /// Cost is estimated from approximate per-model list prices; duplicate JSONL
    /// lines for the same API response (same `message.id`/`requestId`) count once.
    /// - Note: The *first* call on a large session parses the whole file, so call off the
    ///   main thread.
    public func usage(for root: URL) -> AgentUsage? {
        cache.results(for: latestSession(for: root)).usage
    }

    /// The activity timeline parsed from the latest transcript, oldest first, capped to the most
    /// recent ``EventBuffer/cap`` events. Malformed lines are skipped.
    /// - Note: The *first* call on a large session parses the whole file, so call off the
    ///   main thread.
    public func events(for root: URL) -> [TimelineEvent] {
        cache.results(for: latestSession(for: root)).events
    }

    /// The activity timeline parsed from one transcript file, bypassing the `~/.claude/projects`
    /// lookup entirely — the seam that lets this adapter be exercised against a checked-in
    /// fixture rather than a live session.
    public func events(fromSession url: URL) -> [TimelineEvent] {
        cache.results(for: url).events
    }

    /// The edited-files set from the latest transcript, or `nil` when there is no
    /// transcript at all.
    /// - Note: The *first* call on a large session parses the whole file, so call off the
    ///   main thread.
    public func summary(for root: URL) -> AgentSummary? {
        cache.results(for: latestSession(for: root)).summary
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
