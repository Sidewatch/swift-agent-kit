//
//  ProjectDirectoryFormsTests.swift
//  AgentSessionTests
//
//  A session filed under the kernel's spelling of its path is found from any spelling the host holds.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// A session filed under the kernel's spelling of its path (`/private` kept, symlinks resolved,
/// the folder name's own Unicode form) is found from any spelling the host holds.
final class ProjectDirectoryFormsTests: XCTestCase {
    /// Under `/tmp`, so the kernel's path begins `/private/tmp`.
    private var scratch: URL!
    private var projectsRoot: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: "/tmp/agent-forms-\(UUID().uuidString)", isDirectory: true)
        projectsRoot = scratch.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    private let prompt = #"{"type":"user","timestamp":"2026-10-09T10:00:00.000Z","message":{"content":"hi"}}"# + "\n"

    /// Claude Code's folder name for an ASCII path: every character outside `[A-Za-z0-9]` is a dash.
    private func folded(_ path: String) -> String { String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }) }

    /// Writes a Claude transcript under the project folder named `folder`, returning it.
    private func claudeSession(in folder: String) throws -> URL {
        let dir = projectsRoot.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("session.jsonl")
        try prompt.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// A real folder under the scratch directory.
    private func folder(_ name: String) throws -> URL {
        let url = scratch.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testPathFormsRestorePrivateAndResolveSymlinks() throws {
        let project = try folder("proj")
        let forms = PathForms.of(project)
        XCTAssertEqual(forms.first, project.path, "the spelling given comes first")
        XCTAssertTrue(forms.contains("/private" + project.path), "\(forms)")
        let link = scratch.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: project)
        XCTAssertTrue(PathForms.of(link).contains("/private" + project.path), "the kernel's cwd behind a symlink: \(PathForms.of(link))")
        XCTAssertEqual(PathForms.of(URL(fileURLWithPath: "/Users/x/dev/app")), ["/Users/x/dev/app"], "a plain path has one spelling")
    }

    func testAnExistingTmpProjectFindsItsKernelNamedClaudeFolder() throws {
        let project = try folder("proj")
        let file = try claudeSession(in: folded("/private" + project.path))
        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        XCTAssertEqual(adapter.latestSession(for: project)?.canonicalPath, file.canonicalPath, "asked as /tmp/…")
        XCTAssertEqual(
            adapter.latestSession(for: URL(fileURLWithPath: "/private" + project.path))?.canonicalPath, file.canonicalPath,
            "asked as /private/tmp/…")
        XCTAssertEqual(adapter.events(for: project).count, 1)
    }

    func testAnAccentedFolderIsFoundFromEitherUnicodeForm() throws {
        let precomposed = try claudeSession(in: "-Users-x-Caf-")
        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        XCTAssertEqual(
            adapter.latestSession(for: URL(fileURLWithPath: "/Users/x/Cafe\u{301}"))?.canonicalPath, precomposed.canonicalPath,
            "asked decomposed")
        XCTAssertEqual(
            adapter.latestSession(for: URL(fileURLWithPath: "/Users/x/Caf\u{E9}"))?.canonicalPath, precomposed.canonicalPath,
            "asked precomposed")
        let decomposed = try claudeSession(in: "-Users-x-The-")
        XCTAssertEqual(
            adapter.latestSession(for: URL(fileURLWithPath: "/Users/x/Th\u{E9}"))?.canonicalPath, decomposed.canonicalPath,
            "a folder created decomposed")
    }

    func testCodexFindsARolloutRecordedUnderTheKernelPathWhenAskedThroughASymlink() throws {
        let real = try folder("real")
        let link = scratch.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let day = scratch.appendingPathComponent("codex/2026/10/09", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        try #"{"type":"session_meta","payload":{"cwd":"CWD","source":"cli"}}"#
            .replacingOccurrences(of: "CWD", with: "/private" + real.path)
            .write(to: day.appendingPathComponent("rollout-1.jsonl"), atomically: true, encoding: .utf8)
        let adapter = CodexAdapter(sessionsRoot: scratch.appendingPathComponent("codex"))
        XCTAssertNotNil(adapter.latestSession(for: link), "asked through the symlink")
        XCTAssertNotNil(adapter.latestSession(for: real))
        XCTAssertNil(adapter.latestSession(for: scratch), "the parent is not the project")
    }

    func testGeminiAndGrokFindAProjectFiledUnderItsKernelPath() throws {
        let project = try folder("proj")
        let kernel = "/private" + project.path
        let gemini = try folder("gemini")
        try #"{"projects":{"KERNEL":"proj"}}"#.replacingOccurrences(of: "KERNEL", with: kernel)
            .write(to: gemini.appendingPathComponent("projects.json"), atomically: true, encoding: .utf8)
        let chats = gemini.appendingPathComponent("tmp/proj/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try #"{"sessionId":"s"}"#.write(to: chats.appendingPathComponent("session-1.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(GeminiAdapter(runtimeRoots: [gemini]).latestSession(for: project), "the registry holds the kernel's spelling")

        let grok = try folder("grok")
        let session = grok.appendingPathComponent("\(GrokSessionIndex.encode(kernel))/s1", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try #"{"type":"user","content":[{"type":"text","text":"hi"}]}"#
            .write(to: session.appendingPathComponent("chat_history.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(GrokAdapter(sessionsRoot: grok).latestSession(for: project), "the bucket is named from the kernel's spelling")
    }
}
