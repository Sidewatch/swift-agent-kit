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
/// registry, the SHA-256 of the project path. The registry is keyed by the cwd Gemini saw, so every
/// spelling of the path (``PathForms``) is looked up. A sub-agent's chat sits in a folder under
/// `chats/` and is not the conversation. The session chosen is held while it is being written
/// (``SessionChoice``); a miss is remembered briefly (``LookupMisses``).
final class GeminiSessionIndex: @unchecked Sendable {
    /// The runtime folders a session may live under: `$GEMINI_CLI_HOME/.gemini` (default
    /// `~/.gemini`), and `~/.cache/.gemini`, where a Seatbelt-sandboxed run writes.
    private let runtimeRoots: [URL]
    /// Lists folders; its count is the test seam proving a remembered miss lists nothing.
    let reader = DirectoryReader()
    private let choice = SessionChoice()
    private let misses = LookupMisses()
    private let lock = NSLock()
    /// Each registry's projects (path → slug), with the modification date it was read at.
    private var registries: [String: (date: Date?, projects: [String: String])] = [:]

    /// An index over the given runtime folders.
    init(runtimeRoots: [URL]) { self.runtimeRoots = runtimeRoots }

    /// The top-level session file being written for `root`, or nil.
    func latestSession(for root: URL) -> URL? {
        misses.remembering(root.path) { choice.choose(for: root.path, newest: newestSession(for: root)) }
    }

    /// The project folder of the newest top-level session started in a SUBFOLDER of `project`, or
    /// nil. Read from the registry (`projects.json` maps each path to its folder); a legacy folder
    /// is a hash of its path and cannot be read back, so only registered projects are found.
    func latestSessionRoot(under project: URL) -> URL? {
        let parents = PathForms.of(project).map { $0 + "/" }
        return misses.remembering("under:" + project.path) {
            var best: (path: String, date: Date)?
            for runtime in runtimeRoots {
                for (path, id) in projects(in: runtime) where parents.contains(where: { path.hasPrefix($0) }) {
                    let chats = runtime.appendingPathComponent("tmp/\(id)/chats", isDirectory: true)
                    for file in reader.dated(in: chats, extensions: ["jsonl"]) where file.url.lastPathComponent.hasPrefix("session-") {
                        if best.map({ file.date > $0.date }) ?? true { best = (path, file.date) }
                    }
                }
            }
            return best.map { URL(fileURLWithPath: $0.path, isDirectory: true) }
        }
    }

    /// The newest top-level `session-*.jsonl` across every folder a spelling of `root` maps to.
    private func newestSession(for root: URL) -> URL? {
        let spellings = PathForms.of(root)
        var sessions: [(url: URL, date: Date)] = []
        for runtime in runtimeRoots {
            let registry = projects(in: runtime)
            for id in Set(spellings.flatMap { [registry[$0], Self.legacyID($0)].compactMap { $0 } }) {
                let chats = runtime.appendingPathComponent("tmp/\(id)/chats", isDirectory: true)
                sessions += reader.dated(in: chats, extensions: ["jsonl"]).filter { $0.url.lastPathComponent.hasPrefix("session-") }
            }
        }
        return DirectoryReader.newest(sessions)
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
