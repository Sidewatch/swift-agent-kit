//
//  GeminiSessionIndex.swift
//  AgentSession
//
//  Finds a project's newest Gemini CLI session, by Gemini's own project registry.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import CryptoKit
import Foundation

/// Finds the newest Gemini CLI session for a project. Gemini files a project's chats under
/// `<runtime>/tmp/<id>/chats/session-*.jsonl` (`packages/core/src/config/storage.ts`), where the id
/// is the project's slug from `<runtime>/projects.json` (`projectRegistry.ts`) or, before the
/// registry, the SHA-256 of the project path. A sub-agent's chat sits in a folder under `chats/`
/// and is not the conversation.
final class GeminiSessionIndex: @unchecked Sendable {
    /// The runtime folders a session may live under: `$GEMINI_CLI_HOME/.gemini` (default
    /// `~/.gemini`), and `~/.cache/.gemini`, where a Seatbelt-sandboxed run writes.
    private let runtimeRoots: [URL]
    private let lock = NSLock()
    /// Each registry's projects (path → slug), with the modification date it was read at.
    private var registries: [String: (date: Date?, projects: [String: String])] = [:]

    /// An index over the given runtime folders.
    init(runtimeRoots: [URL]) { self.runtimeRoots = runtimeRoots }

    /// The newest top-level session file for `root`, or nil.
    func latestSession(for root: URL) -> URL? {
        let path = root.standardizedFileURL.path
        var best: (url: URL, date: Date)?
        for runtime in runtimeRoots {
            for id in Set([projects(in: runtime)[path], Self.legacyID(path)].compactMap { $0 }) {
                let chats = runtime.appendingPathComponent("tmp/\(id)/chats", isDirectory: true)
                guard let files = try? FileManager.default.contentsOfDirectory(at: chats, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                for file in files where file.lastPathComponent.hasPrefix("session-") && file.pathExtension == "jsonl" {
                    let date = file.modificationDate ?? .distantPast
                    if best.map({ date > $0.date }) ?? true { best = (file, date) }
                }
            }
        }
        return best?.url
    }

    /// A registry's projects, re-read only when `projects.json` changes.
    private func projects(in runtime: URL) -> [String: String] {
        let file = runtime.appendingPathComponent("projects.json")
        let date = file.modificationDate
        lock.lock()
        if let known = registries[runtime.path], known.date == date { lock.unlock(); return known.projects }
        lock.unlock()
        let projects = (JSONFile.object(at: file)?["projects"] as? [String: String]) ?? [:]
        lock.lock(); registries[runtime.path] = (date, projects); lock.unlock()
        return projects
    }

    /// The pre-registry folder name: the hex SHA-256 of the project path (`getFilePathHash`).
    static func legacyID(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
