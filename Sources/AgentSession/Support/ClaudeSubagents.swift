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

/// What a Claude Code session's sub-agents did. A sub-agent's tool calls are not in the session's
/// own transcript: each sub-agent writes `<session>/subagents/agent-<id>.jsonl` beside
/// `<session>.jsonl`, in the transcript's line format, with `agent-<id>.meta.json` naming the tool
/// call that started it. A session that hands its work to sub-agents edits most of its files there,
/// so a reader of the session alone misses them.
///
/// Each transcript is read once and then only for what was appended: a finished sub-agent costs a
/// `stat` per poll. A few sessions are remembered at a time (several agents may run at once).
final class ClaudeSubagents: @unchecked Sendable {
    /// What is remembered of one sub-agent.
    private struct Entry {
        var inode: UInt64
        /// The first byte not yet read; always at the start of a line.
        var offset: UInt64 = 0
        var toolCalls = 0
        var edited: [String] = []
        var editedSet = Set<String>()
        /// The tool call that started it, its kind and whether it has finished, from its meta file.
        var toolUseID: String?
        var type = ""
        var finished = false
        var metaRead: Date?
    }

    /// What is remembered of one session.
    private struct Session {
        var entries: [String: Entry] = [:]
        var servedAt = Date()
    }

    /// The longest line that is parsed; a longer one is passed over (``TranscriptCache/lineCap``).
    static var lineCap: Int { 4 << 20 }
    /// The most bytes read from one file in one piece, so a first read of a long transcript is
    /// taken in pieces rather than held whole.
    static var chunk: Int { 8 << 20 }
    /// How many sessions are remembered; the least recently asked for goes first.
    static var capacity: Int { 4 }
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
    private var sessions: [String: Session] = [:]
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
        return refreshed(session).values.reduce(into: Set<String>()) { $0.formUnion($1.editedSet) }
    }

    /// Each sub-agent's work, by the id of the tool call that started it. A sub-agent whose meta
    /// file does not name its call is left out: there is no call to show it under.
    func work(forSession session: URL) -> [String: SubagentWork] {
        lock.lock(); defer { lock.unlock() }
        var work: [String: SubagentWork] = [:]
        for entry in refreshed(session).values {
            guard let call = entry.toolUseID else { continue }
            work[call] = SubagentWork(type: entry.type, toolCalls: entry.toolCalls, editedFiles: entry.edited, isFinished: entry.finished)
        }
        return work
    }

    /// Reads what the session's sub-agents have written since the last poll, within the budget.
    private func refreshed(_ session: URL) -> [String: Entry] {
        var state = sessions[session.path] ?? Session()
        let files = (reader.contents(of: Self.folder(forSession: session)) ?? [])
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-") }
        var live = Set<String>()
        let spent = bytes
        for file in files {
            live.insert(file.path)
            guard let stat = FileStat(path: file.path) else { continue }
            var entry = state.entries[file.path] ?? Entry(inode: stat.inode)
            // Replaced or cut short: not the file that was read, so it is read again from its start.
            if entry.inode != stat.inode || stat.size < entry.offset { entry = Entry(inode: stat.inode) }
            if stat.size > entry.offset, bytes - spent < budget { readAppended(file.path, upTo: stat.size, into: &entry) }
            if !entry.finished { readMeta(of: file, into: &entry) }
            state.entries[file.path] = entry
        }
        state.entries = state.entries.filter { live.contains($0.key) }
        state.servedAt = Date()
        sessions[session.path] = state
        while sessions.count > Self.capacity, let oldest = sessions.min(by: { $0.value.servedAt < $1.value.servedAt }) {
            sessions[oldest.key] = nil
        }
        return state.entries
    }

    /// Reads `agent-<id>.meta.json` beside a transcript when it has changed since it was last read.
    private func readMeta(of transcript: URL, into entry: inout Entry) {
        let meta = transcript.deletingPathExtension().appendingPathExtension("meta.json")
        guard let stat = FileStat(path: meta.path), stat.mtime != entry.metaRead || entry.metaRead == nil,
            stat.size <= 1 << 20, let data = try? Data(contentsOf: meta), let object = JSONFile.object(from: data)
        else { return }
        entry.metaRead = stat.mtime
        entry.toolUseID = object["toolUseId"] as? String
        entry.type = object["agentType"] as? String ?? ""
        entry.finished = object["finished"] as? Bool ?? false
    }

    /// Reads the complete lines between `entry.offset` and `size`, a piece at a time.
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
                entry.toolCalls += state.eventsResult.count { $0.kind == .toolUse || $0.kind == .fileEdit }
                for path in state.summaryResult.editedFiles.sorted() where entry.editedSet.insert(path).inserted {
                    entry.edited.append(path)
                }
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
