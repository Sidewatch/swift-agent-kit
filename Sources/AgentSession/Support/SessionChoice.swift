//
//  SessionChoice.swift
//  AgentSession
//
//  Which of a project's transcripts is the live one, held steady across polls.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Which of a project's transcripts is the live one, held steady across polls. Two agents in
/// one folder write two transcripts, and "the newest by mtime" flips between them on every
/// poll — each flip reading as a rotation that re-parses the whole file. The file chosen for a
/// key is kept while it is still being written (its mtime advanced since the previous poll, or
/// lies within ``quietAfter``); a newer file takes over only once the chosen one has gone quiet.
final class SessionChoice: @unchecked Sendable {
    /// How long after its last write a transcript still counts as live.
    static let quietAfter: TimeInterval = 30

    /// The file held for a key, with the modification date seen at the previous poll.
    private struct Held {
        let path: String
        let mtime: Date
    }

    private let lock = NSLock()
    private var held: [String: Held] = [:]

    /// The transcript to read for `key` this poll, given `newest` — the freshest candidate the
    /// lookup found, or nil when it found none, which forgets the key. Dates come from a fresh
    /// `stat`, never a `URL`'s cached resource values, and the answer is a fresh `URL`.
    func choose(for key: String, newest: URL?, now: Date = Date()) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard let newest else { held[key] = nil; return nil }
        if let current = held[key], current.path != newest.path, let mtime = FileStat(path: current.path)?.mtime,
            mtime > current.mtime || now.timeIntervalSince(mtime) < Self.quietAfter
        {
            held[key] = Held(path: current.path, mtime: mtime)
            return URL(fileURLWithPath: current.path)
        }
        held[key] = Held(path: newest.path, mtime: FileStat(path: newest.path)?.mtime ?? .distantPast)
        return newest
    }
}
