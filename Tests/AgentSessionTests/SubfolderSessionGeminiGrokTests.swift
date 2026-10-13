//
//  SubfolderSessionGeminiGrokTests.swift
//  AgentSessionTests
//
//  Gemini and Grok find a session launched in a subfolder of the opened folder, as Claude Code
//  and Codex do — and never one in a sibling whose name merely starts the same.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

final class SubfolderSessionGeminiGrokTests: XCTestCase {
    private func temp(_ label: String) -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("\(label)-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func touch(_ file: URL, age: TimeInterval) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
    }

    // MARK: Gemini

    func testGeminiFindsTheNewestSessionInASubfolder() throws {
        let runtime = temp("gemini-sub")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try #"{"projects":{"/work/app/web":"web","/work/app/api":"api","/work/app2":"app2"}}"#
            .write(to: runtime.appendingPathComponent("projects.json"), atomically: true, encoding: .utf8)
        try touch(runtime.appendingPathComponent("tmp/web/chats/session-1.jsonl"), age: 60)
        try touch(runtime.appendingPathComponent("tmp/api/chats/session-2.jsonl"), age: 10)
        try touch(runtime.appendingPathComponent("tmp/app2/chats/session-3.jsonl"), age: 1)  // newest, but a sibling
        let adapter = GeminiAdapter(runtimeRoots: [runtime])
        XCTAssertEqual(adapter.latestSessionRoot(under: URL(fileURLWithPath: "/work/app"))?.path, "/work/app/api")
        XCTAssertNil(adapter.latestSessionRoot(under: URL(fileURLWithPath: "/work/other")))
    }

    // MARK: Grok

    func testGrokFindsTheNewestSessionInASubfolder() throws {
        let sessions = temp("grok-sub")
        func history(_ cwd: String, _ id: String) -> URL {
            sessions.appendingPathComponent("\(GrokSessionIndex.encode(cwd))/\(id)/chat_history.jsonl")
        }
        try touch(history("/work/app/web", "a"), age: 60)
        try touch(history("/work/app/api", "b"), age: 10)
        try touch(history("/work/app2", "c"), age: 1)  // newest, but a sibling
        let adapter = GrokAdapter(sessionsRoot: sessions)
        XCTAssertEqual(adapter.latestSessionRoot(under: URL(fileURLWithPath: "/work/app"))?.path, "/work/app/api")
        XCTAssertNil(adapter.latestSessionRoot(under: URL(fileURLWithPath: "/work/other")))
    }

    func testGrokReadsALongPathFromItsCwdFile() throws {
        let sessions = temp("grok-long")
        let longCwd = "/work/app/" + String(repeating: "deep-folder-name/", count: 20)
        let bucket = sessions.appendingPathComponent("slug-and-hash", isDirectory: true)
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        try longCwd.write(to: bucket.appendingPathComponent(".cwd"), atomically: true, encoding: .utf8)
        try touch(bucket.appendingPathComponent("s1/chat_history.jsonl"), age: 5)
        XCTAssertEqual(
            GrokAdapter(sessionsRoot: sessions).latestSessionRoot(under: URL(fileURLWithPath: "/work/app"))?.path,
            URL(fileURLWithPath: longCwd).path)
    }
}
