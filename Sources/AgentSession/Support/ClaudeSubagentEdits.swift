//
//  ClaudeSubagentEdits.swift
//  AgentSession
//
//  The files a Claude Code session's sub-agents wrote.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The files a Claude Code session's sub-agents wrote. A sub-agent's tool calls are not in the
/// session's own transcript: each sub-agent writes `<session>/subagents/agent-<id>.jsonl` beside
/// `<session>.jsonl`, in the transcript's line format. A session that hands its work to sub-agents
/// edits most of its files there, so a reader of the session alone misses them.
///
/// Each file is read once and then only for what was appended: a finished sub-agent's file costs a
/// `stat` per poll. One session's files are remembered at a time.
final class ClaudeSubagentEdits: @unchecked Sendable {
    /// What is remembered of one sub-agent's transcript.
    private struct Entry {
        var inode: UInt64
        var size: UInt64
        /// The first byte not yet read; always at the start of a line.
        var offset: UInt64
        var edited: Set<String>
    }

    /// The longest line that is parsed; a longer one is passed over (``TranscriptCache/lineCap``).
    static var lineCap: Int { 4 << 20 }
    /// The most bytes read from one file in one poll, so a first read of a long transcript is taken
    /// in pieces rather than held whole.
    static var chunk: Int { 8 << 20 }
    /// The bytes every line with a tool call in it contains; other lines are not decoded.
    private static let toolUseMark = Data("\"tool_use\"".utf8)

    /// The most bytes one poll reads across all of a session's sub-agents. A session that ran
    /// hundreds of them leaves gigabytes (2.9 GB over 289 sub-agents, measured on a real one); the
    /// first polls take that a budget at a time and the answer fills in, later polls read only
    /// what was appended.
    let budget: Int

    /// A reader taking at most `budget` bytes a poll.
    init(budget: Int = 256 << 20) { self.budget = budget }

    private let lock = NSLock()
    private let reader = DirectoryReader()
    private var session: String?
    private var entries: [String: Entry] = [:]
    private var bytes = 0

    /// Test seam: the transcript bytes read so far.
    var bytesRead: Int { lock.lock(); defer { lock.unlock() }; return bytes }

    /// The folder a session's sub-agents write in: `<session>/subagents` beside `<session>.jsonl`.
    static func folder(forSession session: URL) -> URL {
        session.deletingPathExtension().appendingPathComponent("subagents", isDirectory: true)
    }

    /// The files the sub-agents of `session` wrote; empty when it has none.
    func editedFiles(forSession session: URL) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        if self.session != session.path {
            self.session = session.path
            entries = [:]
        }
        let files = (reader.contents(of: Self.folder(forSession: session)) ?? [])
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-") }
        var live = Set<String>()
        var edited = Set<String>()
        let spent = bytes
        for file in files {
            live.insert(file.path)
            guard let stat = FileStat(path: file.path) else { continue }
            var entry = entries[file.path] ?? Entry(inode: stat.inode, size: 0, offset: 0, edited: [])
            // Replaced or cut short: not the file that was read, so it is read again from its start.
            if entry.inode != stat.inode || stat.size < entry.offset {
                entry = Entry(inode: stat.inode, size: 0, offset: 0, edited: [])
            }
            if stat.size > entry.offset, bytes - spent < budget { readAppended(file.path, upTo: stat.size, into: &entry) }
            entry.size = stat.size
            entries[file.path] = entry
            edited.formUnion(entry.edited)
        }
        entries = entries.filter { live.contains($0.key) }
        return edited
    }

    /// Reads the complete lines between `entry.offset` and `size`, a chunk at a time.
    private func readAppended(_ path: String, upTo size: UInt64, into entry: inout Entry) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        let spent = bytes
        while entry.offset < size, bytes - spent < budget {
            guard (try? handle.seek(toOffset: entry.offset)) != nil,
                let data = try? handle.read(upToCount: Int(min(UInt64(Self.chunk), size - entry.offset))), !data.isEmpty
            else { return }
            bytes += data.count
            guard let lastBreak = data.lastIndex(of: UInt8(ascii: "\n")) else {
                // No line ends in this piece. One longer than the cap is passed over; a shorter one
                // is still being written and is read whole next time.
                if data.count >= Self.lineCap { entry.offset += UInt64(data.count); continue }
                return
            }
            for line in Self.linesWithToolCalls(in: data, upTo: lastBreak - data.startIndex) {
                var state = ClaudeTranscriptState()
                state.ingest(lineData: line)
                entry.edited.formUnion(state.summaryResult.editedFiles)
            }
            entry.offset += UInt64(lastBreak - data.startIndex + 1)
        }
    }

    /// The lines among the first `end` bytes of `data` that hold a tool call, none longer than
    /// ``lineCap``. The bytes are searched for the mark and only the lines it falls in are cut out:
    /// most of a sub-agent's transcript is request records, hundreds of megabytes that say nothing
    /// about files, and splitting those into lines cost forty seconds on a real session.
    static func linesWithToolCalls(in data: Data, upTo end: Int) -> [Data] {
        var lines: [Data] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            toolUseMark.withUnsafeBytes { mark in
                var position = 0
                while position < end, let hit = memmem(base + position, end - position, mark.baseAddress, mark.count) {
                    let at = base.distance(to: UnsafeRawPointer(hit))
                    var start = at
                    while start > 0, raw[start - 1] != UInt8(ascii: "\n") { start -= 1 }
                    let lineEnd =
                        memchr(base + at, Int32(UInt8(ascii: "\n")), end - at).map { base.distance(to: UnsafeRawPointer($0)) } ?? end
                    if lineEnd - start <= lineCap { lines.append(Data(bytes: base + start, count: lineEnd - start)) }
                    position = lineEnd + 1
                }
            }
        }
        return lines
    }
}
