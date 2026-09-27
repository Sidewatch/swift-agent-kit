//
//  CodexSessionIndex.swift
//  AgentSession
//
//  Which Codex rollout belongs to a project, found without re-reading every session.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Finds the newest Codex rollout for a project. Codex files sessions by DATE
/// (`sessions/YYYY/MM/DD/rollout-*.jsonl`), not by project, so the working directory is read from
/// each rollout's first line (`session_meta.cwd`) — once per file, then remembered — and only the
/// most recent day folders are listed on a poll. A sub-agent's rollout (a `source` that is not a
/// plain string) shares its parent's directory and is skipped: the parent is the conversation.
final class CodexSessionIndex: @unchecked Sendable {
    /// How many day folders, newest first, a lookup lists.
    static let daysScanned = 14
    /// How much of a rollout's first line is read for its metadata.
    static let metaReadLimit = 512 * 1024

    private let sessionsRoot: URL
    private let lock = NSLock()
    /// Rollout path → its working directory (nil for a sub-agent's or an unreadable one).
    private var cwdByPath: [String: String?] = [:]

    /// An index over `sessionsRoot` (`$CODEX_HOME/sessions`, default `~/.codex/sessions`).
    init(sessionsRoot: URL) { self.sessionsRoot = sessionsRoot }

    /// The newest top-level rollout whose working directory is `root`, or nil.
    func latestRollout(for root: URL) -> URL? {
        let want = root.standardizedFileURL.path
        var best: (url: URL, date: Date)?
        for day in recentDayFolders() {
            guard let files = try? FileManager.default.contentsOfDirectory(at: day, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
                guard workingDirectory(of: file) == want else { continue }
                let date = file.modificationDate ?? .distantPast
                if best.map({ date > $0.date }) ?? true { best = (file, date) }
            }
        }
        return best?.url
    }

    /// The `YYYY/MM/DD` folders, newest first, at most ``daysScanned`` of them.
    private func recentDayFolders() -> [URL] {
        func numbered(_ dir: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { Int($0.lastPathComponent) != nil }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var days: [URL] = []
        for year in numbered(sessionsRoot) {
            for month in numbered(year) {
                for day in numbered(month) {
                    days.append(day)
                    if days.count == Self.daysScanned { return days }
                }
            }
        }
        return days
    }

    /// A rollout's working directory, from its `session_meta` line; nil for a sub-agent's.
    func workingDirectory(of file: URL) -> String? {
        lock.lock()
        if let known = cwdByPath[file.path] { lock.unlock(); return known }
        lock.unlock()
        let cwd = Self.readMeta(file)
        lock.lock(); cwdByPath[file.path] = cwd; lock.unlock()
        return cwd
    }

    private static func readMeta(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: metaReadLimit),
              let line = head.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
              let obj = JSONFile.object(from: Data(line)), obj["type"] as? String == "session_meta",
              let payload = obj["payload"] as? [String: Any], payload["source"] is String || payload["source"] == nil,
              let cwd = payload["cwd"] as? String else { return nil }
        return URL(fileURLWithPath: cwd).standardizedFileURL.path
    }
}
