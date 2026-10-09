//
//  SubfolderSessionTests.swift
//  AgentSessionTests
//
//  A session launched in a subfolder of the project is found for the project, and a folder name
//  shared by two paths is told apart by the launch directory each transcript names.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// A session launched in a subfolder of the project is found for the project, and a folder name
/// shared by two paths is told apart by the launch directory each transcript names.
final class SubfolderSessionTests: XCTestCase {
    private var projectsRoot: URL!
    private let project = URL(fileURLWithPath: "/private/tmp/subfolder-tests/R")
    private let worker = URL(fileURLWithPath: "/private/tmp/subfolder-tests/R/worker")
    /// Folds to the same folder name as `worker`.
    private let sibling = URL(fileURLWithPath: "/private/tmp/subfolder-tests/R-worker")
    private let sharedFolder = "-private-tmp-subfolder-tests-R-worker"

    override func setUpWithError() throws {
        projectsRoot = FileManager.default.temporaryDirectory.appendingPathComponent("subfolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: projectsRoot) }

    /// A Claude transcript in `folder`: the mode record first, then a prompt naming its `cwd`.
    @discardableResult
    private func claude(_ folder: String, _ name: String, cwd: String?, age: TimeInterval = 0) throws -> URL {
        let dir = projectsRoot.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines = [#"{"type":"mode"}"#]
        if let cwd {
            lines.append(
                #"{"type":"user","cwd":"CWD","timestamp":"2026-10-09T10:00:00.000Z","message":{"content":"hi"}}"#
                    .replacingOccurrences(of: "CWD", with: cwd))
        }
        let file = dir.appendingPathComponent(name)
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
        return file
    }

    func testASessionLaunchedInASubfolderIsFoundForTheProject() throws {
        let session = try claude(sharedFolder, "s.jsonl", cwd: worker.path)
        try claude("-private-tmp-subfolder-tests-R-fresh", "fresh.jsonl", cwd: nil, age: -5)
        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        XCTAssertNil(adapter.latestSession(for: project), "no session was launched in R itself")
        XCTAssertEqual(
            adapter.latestSessionRoot(under: project)?.path, worker.path, "a transcript naming no directory yet is not confirmed")
        let hit = try XCTUnwrap(Agents.resolve(candidates: [project], in: [adapter]))
        XCTAssertEqual(hit.root.path, worker.path)
        XCTAssertEqual(hit.session.canonicalPath, session.canonicalPath)
        XCTAssertEqual(hit.adapter.events(for: hit.root).count, 1)
    }

    func testAFolderNameSharedByTwoPathsIsToldApartByTheLaunchDirectory() throws {
        try claude(sharedFolder, "sibling.jsonl", cwd: sibling.path)
        try claude(sharedFolder, "worker.jsonl", cwd: worker.path, age: 60)
        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        XCTAssertEqual(
            adapter.latestSession(for: worker)?.lastPathComponent, "worker.jsonl",
            "the newer transcript in the folder was launched in another path")
        XCTAssertEqual(adapter.latestSession(for: sibling)?.lastPathComponent, "sibling.jsonl")
        XCTAssertEqual(adapter.latestSessionRoot(under: project)?.path, worker.path, "the sibling's session is not beneath R")
    }

    func testOnlyTheProjectIsSearchedBeneath() throws {
        try claude(sharedFolder, "s.jsonl", cwd: worker.path)
        let other = URL(fileURLWithPath: "/private/tmp/subfolder-tests/other")
        let parent = URL(fileURLWithPath: "/private/tmp/subfolder-tests")
        let adapter = ClaudeCodeAdapter(projectsRoot: projectsRoot)
        XCTAssertEqual(
            Agents.resolve(candidates: [parent], in: [adapter])?.root.path, worker.path, "the first candidate is searched beneath")
        XCTAssertNil(Agents.resolve(candidates: [other, parent], in: [adapter]), "a later candidate is not: a parent holds other projects")
        XCTAssertEqual(
            Agents.resolve(candidates: [other, parent], under: project, in: [adapter])?.root.path, worker.path,
            "the host can name the project")
    }

    func testACodexRolloutLaunchedInASubfolderIsFoundForTheProject() throws {
        let day = projectsRoot.appendingPathComponent("codex/2026/10/09", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        try #"{"type":"session_meta","payload":{"cwd":"CWD","source":"cli"}}"#.replacingOccurrences(of: "CWD", with: worker.path)
            .write(to: day.appendingPathComponent("rollout-1.jsonl"), atomically: true, encoding: .utf8)
        try #"{"type":"session_meta","payload":{"cwd":"CWD","source":"cli"}}"#.replacingOccurrences(of: "CWD", with: sibling.path)
            .write(to: day.appendingPathComponent("rollout-2.jsonl"), atomically: true, encoding: .utf8)
        let adapter = CodexAdapter(sessionsRoot: projectsRoot.appendingPathComponent("codex"))
        XCTAssertNil(adapter.latestSession(for: project))
        XCTAssertEqual(adapter.latestSessionRoot(under: project)?.path, worker.path, "R-worker is not beneath R")
        XCTAssertEqual(Agents.resolve(candidates: [project], in: [adapter])?.root.path, worker.path)
    }
}
