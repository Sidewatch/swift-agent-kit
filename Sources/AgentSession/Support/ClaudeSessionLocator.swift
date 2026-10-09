//
//  ClaudeSessionLocator.swift
//  AgentSession
//
//  Finds a project's live Claude Code transcript among the project directories that could be its.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Finds a project's live Claude Code transcript. Claude files a session under
/// `<projects>/<encoded launch cwd>/<session id>.jsonl`, where the encoding folds every
/// character outside `[A-Za-z0-9]` to `-`: lossy, so one folder name serves several paths, and
/// spelled from the kernel's cwd, so one path has several candidate folders
/// (``ClaudeSessionIndex/candidateEncodings(of:)``). Every existing candidate folder is read; a
/// transcript whose launch directory (the first record carrying `cwd`) names another path is
/// another project's and is skipped; the newest of the rest is the session, held steady while
/// it is being written (``SessionChoice``). A miss is remembered briefly (``LookupMisses``).
final class ClaudeSessionLocator: @unchecked Sendable {
    /// How much of a transcript's head is read for its launch directory.
    static let headReadLimit = 256 * 1024
    /// How many leading records are scanned for one: the first carries only the session's mode.
    static let headRecordLimit = 32

    /// The `~/.claude/projects`-shaped folder scanned.
    let projectsRoot: URL
    /// Lists folders; its count is the test seam proving a remembered miss lists nothing.
    let reader = DirectoryReader()
    private let choice = SessionChoice()
    private let misses = LookupMisses()
    private let lock = NSLock()
    /// Transcript path → the launch directory its head names. A launch directory never changes,
    /// so it is read once; a head with no `cwd` yet (a session before its first prompt) is not
    /// remembered, and is read again next poll.
    private var launchDirectories: [String: String] = [:]

    /// A locator over `projectsRoot`.
    init(projectsRoot: URL) { self.projectsRoot = projectsRoot }

    /// Every existing project directory `root` may be filed under.
    func projectDirectories(for root: URL) -> [URL] {
        ClaudeSessionIndex.candidateEncodings(of: root).sorted()
            .map { projectsRoot.appendingPathComponent($0, isDirectory: true) }
            .filter(\.isExistingDirectory)
    }

    /// The live transcript for `root`, or nil when Claude Code has no session there.
    func latestSession(for root: URL) -> URL? {
        misses.remembering(root.path) { choice.choose(for: root.path, newest: newestTranscript(for: root)) }
    }

    /// The launch directory of the newest session started in a subfolder of `project`, or nil.
    /// A subfolder's directory name begins with the project's encoding and a `-`; the launch
    /// directory each transcript names decides, because `-` also folds `.` and `_`.
    func latestSessionRoot(under project: URL) -> URL? {
        misses.remembering("under:" + project.path) {
            newestDescendant(under: project).map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
    }

    // MARK: - Reading the candidates

    /// The newest transcript in `root`'s directories whose launch directory is `root` or unknown.
    private func newestTranscript(for root: URL) -> URL? {
        let spellings = PathForms.of(root)
        let transcripts = projectDirectories(for: root).flatMap { reader.dated(in: $0, extensions: ["jsonl"]) }
        return DirectoryReader.newest(transcripts.filter { launchDirectory(of: $0.url).map(spellings.contains) ?? true })
    }

    /// The launch directory of the newest transcript filed beneath `project`, or nil.
    private func newestDescendant(under project: URL) -> String? {
        let prefixes = ClaudeSessionIndex.candidateEncodings(of: project).map { $0 + "-" }
        let parents = PathForms.of(project).map { $0 + "/" }
        let folders = (reader.contents(of: projectsRoot) ?? []).filter { folder in
            prefixes.contains { folder.lastPathComponent.hasPrefix($0) }
        }
        let transcripts = folders.flatMap { reader.dated(in: $0, extensions: ["jsonl"]) }
            .compactMap { file in launchDirectory(of: file.url).map { (date: file.date, launch: $0) } }
            .filter { transcript in parents.contains { transcript.launch.hasPrefix($0) } }
        return transcripts.max { $0.date < $1.date }?.launch
    }

    /// The directory a transcript's session was launched in: the `cwd` of the first record that
    /// carries one. Nil until a record does.
    func launchDirectory(of transcript: URL) -> String? {
        lock.lock()
        if let known = launchDirectories[transcript.path] { lock.unlock(); return known }
        lock.unlock()
        guard let cwd = Self.readLaunchDirectory(transcript) else { return nil }
        lock.lock(); launchDirectories[transcript.path] = cwd; lock.unlock()
        return cwd
    }

    private static func readLaunchDirectory(_ transcript: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headReadLimit) else { return nil }
        for line in head.split(separator: UInt8(ascii: "\n")).prefix(headRecordLimit) {
            if let cwd = JSONFile.object(from: Data(line))?["cwd"] as? String { return cwd }
        }
        return nil
    }
}
