//
//  TerminalStartFolderTests.swift
//  AgentStatusTests
//
//  Tests for `TerminalStartFolder`: an inherited folder inside the project is kept, one outside it
//  gives way to the project, links count as inside, and an idle shell moves only from outside.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import FoundationExtensions
@testable import AgentStatus

/// Tests for `TerminalStartFolder`: an inherited folder inside the project is kept, one outside it
/// gives way to the project, links count as inside, and an idle shell moves only from outside.
final class TerminalStartFolderTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/Users/someone/Code/shop", isDirectory: true)

    func testAFolderOutsideTheProjectGivesWayToTheProject() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        XCTAssertEqual(TerminalStartFolder.folder(inheriting: home, project: project), project, "the home folder is outside")
        let other = URL(fileURLWithPath: "/Users/someone/Code/blog", isDirectory: true)
        XCTAssertEqual(TerminalStartFolder.folder(inheriting: other, project: project), project, "the last project is outside")
    }

    func testAFolderInsideTheProjectIsKept() {
        let sub = project.appendingPathComponent("worker", isDirectory: true)
        XCTAssertEqual(TerminalStartFolder.folder(inheriting: sub, project: project), sub)
        XCTAssertEqual(TerminalStartFolder.folder(inheriting: project, project: project), project, "the project itself")
    }

    func testASiblingSharingThePrefixIsOutside() {
        let sibling = URL(fileURLWithPath: "/Users/someone/Code/shop-old", isDirectory: true)
        XCTAssertEqual(TerminalStartFolder.folder(inheriting: sibling, project: project), project)
    }

    func testNoProjectKeepsTheInheritedFolderAndNoFolderTakesTheProject() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        XCTAssertEqual(TerminalStartFolder.folder(inheriting: home, project: nil), home)
        XCTAssertEqual(TerminalStartFolder.folder(inheriting: nil, project: project), project)
        XCTAssertNil(TerminalStartFolder.folder(inheriting: nil, project: nil))
    }

    func testAProjectOpenedThroughALinkContainsTheShellsResolvedFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tsf-\(UUID().uuidString)", isDirectory: true)
        let real = base.appendingPathComponent("real", isDirectory: true)
        let sub = real.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let link = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        // The shell reports its resolved folder; the project keeps the link it was opened by.
        let reported = URL(fileURLWithPath: try XCTUnwrap(sub.realPath), isDirectory: true)
        XCTAssertEqual(TerminalStartFolder.folder(inheriting: reported, project: link), reported)
        XCTAssertFalse(TerminalStartFolder.moves(to: link, from: reported))
    }

    func testAnIdleShellMovesOnlyFromOutsideTheProject() {
        XCTAssertTrue(TerminalStartFolder.moves(to: project, from: URL(fileURLWithPath: "/Users/someone", isDirectory: true)))
        XCTAssertTrue(TerminalStartFolder.moves(to: project, from: nil), "nowhere known")
        XCTAssertFalse(TerminalStartFolder.moves(to: project, from: project))
        XCTAssertFalse(TerminalStartFolder.moves(to: project, from: project.appendingPathComponent("docs", isDirectory: true)))
    }
}
