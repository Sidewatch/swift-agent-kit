//
//  EditReconciliationTests.swift
//  AgentSessionTests
//
//  `EditReconciliation`: a project opened through a link, or as /var/… where the agent wrote
//  /private/var/…, still matches its claimed edits; a deleted file; the split both ways.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentSession

/// `EditReconciliation` over real files, links and the `/private` spelling.
final class EditReconciliationTests: XCTestCase {
    private var real: URL!
    private var link: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reconcile-\(UUID().uuidString)")
        real = base.appendingPathComponent("real", isDirectory: true)
        link = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        for name in ["a.swift", "b.swift"] {
            FileManager.default.createFile(atPath: real.appendingPathComponent(name).path, contents: Data())
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: real.deletingLastPathComponent()) }

    /// The kernel's spelling, as an agent records it: links resolved, /private kept.
    private func kernel(_ name: String) -> String { real.appendingPathComponent(name).realPath! }

    func testAProjectOpenedThroughALinkMatchesTheAgentsRealPaths() {
        let changed = [link.appendingPathComponent("a.swift"), link.appendingPathComponent("b.swift")]
        let split = EditReconciliation.partition(changed: changed, url: { $0 }, claimed: [kernel("a.swift")])
        XCTAssertEqual(split.unmentioned.map(\.lastPathComponent), ["b.swift"], "a.swift was claimed, under its real path")
        XCTAssertEqual(split.notChanged, [])
    }

    func testTheVarSpellingMatchesPrivateVar() throws {
        let kernelPath = kernel("a.swift")
        guard kernelPath.hasPrefix("/private/var/") else { throw XCTSkip("the temporary folder is not under /private/var here") }
        let varSpelling = URL(fileURLWithPath: String(kernelPath.dropFirst("/private".count)))
        XCTAssertTrue(EditReconciliation.contains([kernelPath], varSpelling))
    }

    func testAClaimGitDoesNotShowIsReported() {
        let split = EditReconciliation.partition(
            changed: [link.appendingPathComponent("a.swift")], url: { $0 }, claimed: [kernel("a.swift"), kernel("b.swift")])
        XCTAssertEqual(split.unmentioned, [])
        XCTAssertEqual(split.notChanged, [kernel("b.swift")])
    }

    func testADeletedFileStillMatchesThroughItsFolder() throws {
        let gone = link.appendingPathComponent("gone.swift")
        XCTAssertTrue(EditReconciliation.contains([real.realPath!.directoryPrefix + "gone.swift"], gone))
    }
}
