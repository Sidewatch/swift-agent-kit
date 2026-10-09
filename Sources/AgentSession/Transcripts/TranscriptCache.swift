//
//  TranscriptCache.swift
//  AgentSession
//
//  The incremental transcript cache behind ClaudeCodeAdapter's readers: each
//  poll costs O(appended bytes) instead of a full-file read + re-parse.
//
//  Created by David Sherlock on 7/16/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The incremental transcript cache behind every adapter's readers: one entry per transcript
/// PATH mirrors that file, so a project whose live session changes (two agents in one folder,
/// a resumed session) keeps each file's state rather than re-parsing on every switch. Each poll
/// `stat`s the file: unchanged → the memoized ``Snapshot`` (zero reads); grown → `pread` only
/// the new bytes and fold complete lines into its `Parser` (an unterminated tail is parsed into
/// a throwaway copy, and the offset never passes it); anything else (new inode, shrink,
/// same-size rewrite) → one full re-parse. The ``capacity`` least recently served entries are
/// kept. Every access is under one `NSLock`; a bad line is skipped on its own.
final class TranscriptCache<Parser: TranscriptParsing>: @unchecked Sendable {

    /// How many transcripts' states are kept; the least recently served goes first.
    static var capacity: Int { 6 }

    /// The results one poll serves — all three readers' values, materialized
    /// once per parse so usage/events/summary always come from the same bytes.
    struct Snapshot: Sendable {
        /// What an adapter's `usage(for:)` returns.
        let usage: AgentUsage?
        /// What an adapter's `events(for:)` returns.
        let events: [TimelineEvent]
        /// What an adapter's `summary(for:)` returns.
        let summary: AgentSummary?
        /// The no-transcript / unreadable-transcript result.
        static var empty: Snapshot { Snapshot(usage: nil, events: [], summary: nil) }
    }

    /// Cached incremental state for one transcript.
    struct Entry {
        /// The transcript's inode (atomic rewrites replace the file → new inode).
        var inode: UInt64
        /// The modification date observed at the last poll.
        var mtime: Date?
        /// The content length observed at the last poll (consumed + pending tail).
        var size: UInt64
        /// The first byte not yet folded into `durable`. Always line-aligned:
        /// it never points past an unterminated trailing line.
        var offset: UInt64
        /// Parse state accumulated over all complete lines up to `offset`.
        var durable: Parser
        /// The memoized results (durable state + tentative trailing line).
        var snapshot: Snapshot
        /// The poll that last served this entry, for eviction.
        var servedAt = 0
    }

    /// Guards all mutable state below. `NSLock` (non-reentrant) is sufficient:
    /// there is a single locked entry point and no nested locking.
    private let lock = NSLock()

    /// Live entries, keyed by the transcript's path.
    private var entries: [String: Entry] = [:]

    /// Counts polls, so each entry remembers when it was last served.
    private var polls = 0

    /// Test seam: how many transcript *content* reads have been performed
    /// (`stat`-only polls do not count). Guarded by `lock`.
    private var reads = 0

    /// Test seam: total transcript bytes read. With incremental polling this
    /// grows by roughly the appended bytes per poll, not the file size. Guarded
    /// by `lock`.
    private var bytes = 0

    /// Thread-safe accessor for the read-count test seam.
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }

    /// Thread-safe accessor for the bytes-read test seam.
    var bytesRead: Int { lock.lock(); defer { lock.unlock() }; return bytes }

    /// Serves the current results for the transcript `file`, updating the cache incrementally
    /// as described in the type documentation.
    ///
    /// - Parameter file: The transcript to read, or `nil` when there is none.
    /// - Returns: The usage/events/summary snapshot, equal to what a full
    ///   re-parse of the file's current contents would produce.
    func results(for file: URL?) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        guard let file else { return .empty }
        let key = file.path
        guard let stat = FileStat(path: key) else {
            entries[key] = nil
            return .empty
        }
        polls += 1
        // Fast path: nothing observable changed → the memoized snapshot, zero file reads.
        if let e = entries[key], e.isUnchanged(stat) {
            entries[key]?.servedAt = polls
            return e.snapshot
        }

        var entry =
            entries[key].flatMap { $0.isPureAppend(stat) ? $0 : nil }
            ?? Entry(inode: stat.inode, mtime: stat.mtime, size: 0, offset: 0, durable: Parser(), snapshot: .empty)
        // Read exactly [offset, size): the appended bytes plus the prefix of an unterminated line
        // carried over from the previous poll. Bytes appended after our stat wait for the next poll.
        guard let appended = readAppended(path: key, entry: entry, size: stat.size) else {
            entries[key] = nil
            return .empty
        }
        let (lines, tail) = appended.completeLinesAndTail
        for line in lines { entry.durable.ingest(lineData: line) }
        entry.offset += UInt64(appended.count - tail.count)
        entry.size = entry.offset + UInt64(tail.count)
        entry.mtime = stat.mtime
        entry.inode = stat.inode
        entry.snapshot = Self.snapshot(durable: entry.durable, tail: tail)
        entry.servedAt = polls
        entries[key] = entry
        evictBeyondCapacity()
        return entry.snapshot
    }

    /// Drops the least recently served entries once more than ``capacity`` are held.
    private func evictBeyondCapacity() {
        while entries.count > Self.capacity, let oldest = entries.min(by: { $0.value.servedAt < $1.value.servedAt }) {
            entries[oldest.key] = nil
        }
    }

    /// The bytes appended since `entry.offset`, or empty when nothing was; nil when unreadable.
    private func readAppended(path: String, entry: Entry, size: UInt64) -> Data? {
        guard size > entry.offset else { return Data() }
        return read(path: path, from: entry.offset, count: Int(size - entry.offset))
    }

    /// The durable state plus a tentative parse of the unterminated tail — what a full re-parse
    /// would see too.
    private static func snapshot(durable: Parser, tail: Data) -> Snapshot {
        var served = durable
        if !tail.isEmpty { served.ingest(lineData: tail) }
        return Snapshot(usage: served.usageResult, events: served.eventsResult, summary: served.summaryResult)
    }

    // MARK: - Raw file access

    /// Reads up to `count` bytes starting at `offset` using POSIX `pread`
    /// (positioned reads, no availability constraints on any Apple platform).
    ///
    /// Returns fewer bytes than requested only when the file shrank between the
    /// caller's `stat` and this read (the next poll's identity check recovers),
    /// or `nil` when the file cannot be opened/read at all. Increments the
    /// read/bytes test-seam counters; a zero-length request performs no read.
    private func read(path: String, from offset: UInt64, count: Int) -> Data? {
        guard count > 0 else { return Data() }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        reads += 1

        var data = Data(count: count)
        var filled = 0
        let ok = data.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) -> Bool in
            guard let base = buf.baseAddress else { return false }
            while filled < count {
                let n = pread(fd, base + filled, count - filled, off_t(offset) + off_t(filled))
                if n == 0 { break }  // EOF: file shrank since stat
                if n < 0 {
                    if errno == EINTR { continue }  // interrupted — retry
                    return false
                }
                filled += n
            }
            return true
        }
        guard ok else { return nil }
        bytes += filled
        if filled < count { data.removeSubrange(filled..<count) }
        return data
    }
}

extension TranscriptCache.Entry {
    /// Same inode, same size and mtime: the steady-state poll.
    func isUnchanged(_ stat: FileStat) -> Bool {
        inode == stat.inode && size == stat.size && mtime == stat.mtime
    }
    /// The very same file grew: the durable state can be reused. Anything else (atomic
    /// rewrite, shrink, same-size mtime change) starts over.
    func isPureAppend(_ stat: FileStat) -> Bool {
        inode == stat.inode && stat.size > size
    }
}
