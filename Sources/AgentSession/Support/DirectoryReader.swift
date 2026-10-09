//
//  DirectoryReader.swift
//  AgentSession
//
//  Directory questions every adapter asks, counted so a test can prove a poll did not ask them.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Directory questions every adapter asks, counted so a test can prove a poll did not ask them.
final class DirectoryReader: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// Test seam: how many directories have been listed so far.
    var listings: Int { lock.lock(); defer { lock.unlock() }; return count }

    /// The entries of `directory`, or nil when it is unreadable.
    func contents(of directory: URL, keys: [URLResourceKey] = []) -> [URL]? {
        lock.lock(); count += 1; lock.unlock()
        return try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
    }

    /// The files in `directory` whose extension is in `extensions`, each with its modification date.
    func dated(in directory: URL, extensions: Set<String>) -> [(url: URL, date: Date)] {
        (contents(of: directory, keys: [.contentModificationDateKey]) ?? [])
            .filter { extensions.contains($0.pathExtension) }
            .map { ($0, $0.modificationDate ?? .distantPast) }
    }

    /// The most recently modified of `files`, or nil when there is none.
    static func newest(_ files: [(url: URL, date: Date)]) -> URL? {
        files.max { $0.date < $1.date }?.url
    }
}
