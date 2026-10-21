//
//  BuildDiagnosticTests.swift
//  AgentStatusTests
//
//  What the toolchains print parses, what merely looks like it must not, colour is stripped,
//  and the latest diagnostic per location wins.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import AgentStatus

/// Tests for `BuildDiagnostic`. The bar is higher than "does it find errors": a gutter mark is
/// BELIEVED, so a wrong one is worse than a missing one — it sends you to a line that is fine
/// and teaches you to distrust every other mark. Most cases here are about what must NOT parse.
final class BuildDiagnosticTests: XCTestCase {

    // MARK: - What the toolchains actually print

    func testSwiftCompilerLineParsesPathLineColumnSeverityAndMessage() throws {
        let d = try XCTUnwrap(BuildDiagnostic.parse("/Users/d/Proj/Sources/App/Main.swift:42:17: error: cannot find 'foo' in scope"))
        XCTAssertEqual(d.path, "/Users/d/Proj/Sources/App/Main.swift")
        XCTAssertEqual(d.line, 42)
        XCTAssertEqual(d.column, 17)
        XCTAssertEqual(d.severity, .error)
        XCTAssertEqual(d.message, "cannot find 'foo' in scope")
    }

    func testGccStyleLineWithoutAColumn() throws {
        let d = try XCTUnwrap(BuildDiagnostic.parse("src/main.c:7: warning: unused variable 'x'"))
        XCTAssertEqual(d.line, 7)
        XCTAssertNil(d.column)
        XCTAssertEqual(d.severity, .warning)
    }

    func testANoteIsKeptAsANoteAndTheLabelIsCaseInsensitive() {
        XCTAssertEqual(BuildDiagnostic.parse("a/b.swift:3:1: note: did you mean 'bar'?")?.severity, .note)
        XCTAssertEqual(BuildDiagnostic.parse("a/b.swift:3:1: Warning: shadowed")?.severity, .warning)
    }

    func testALeadingIndentedLineStillParses() {
        XCTAssertNotNil(BuildDiagnostic.parse("    lib/x.rb:9: error: boom"))
    }

    // MARK: - What must NOT parse

    func testProseTimestampsURLsStackFramesAndBareErrorsDoNotParse() {
        let mustNot = [
            "Cloning into 'repo'... done",
            "https://example.com:443: error connecting",  // a URL, not a path
            "12:30:05: error: this is a log timestamp",  // no path component
            "note: this is just prose with a colon",
            "TODO: fix this: error: not really",  // no line number
            "Binary file matches",
            "  at Object.<anonymous> (/app/x.js:3:9)",  // a stack frame, not a diagnostic
            "error: something went wrong",  // no file at all
            "warning:12: warning: a bare word is not a path",  // no separator or extension
            "",
        ]
        for line in mustNot {
            let got = BuildDiagnostic.parse(line)
            XCTAssertNil(got, "\(line.prefix(40)) parsed as \(got.map { "\($0.path):\($0.line)" } ?? "")")
        }
    }

    func testAPathologicalLineIsNotADiagnostic() {
        let long = "/p/A.swift:1:1: error: " + String(repeating: "x", count: 5_000)
        XCTAssertNil(BuildDiagnostic.parse(long))
    }

    func testLineZeroIsRejected() {
        XCTAssertNil(BuildDiagnostic.parse("/p/A.swift:0:1: error: no such line"))
    }

    // MARK: - ANSI, because compilers colour their output

    func testANSIIsStrippedAndTheColouredLineStillParses() throws {
        let coloured = "\u{1B}[1m/p/File.swift:5:3: \u{1B}[31merror:\u{1B}[0m bad thing\u{1B}[0m"
        let stripped = BuildDiagnostic.stripANSI(coloured)
        XCTAssertFalse(stripped.contains("\u{1B}"), stripped)
        let d = try XCTUnwrap(BuildDiagnostic.parse(stripped))
        XCTAssertEqual(d.line, 5)
        XCTAssertEqual(d.severity, .error)
        XCTAssertEqual(d.message, "bad thing")
    }

    func testOSCSequencesAndABareTrailingEscapeAreStripped() {
        XCTAssertEqual(BuildDiagnostic.stripANSI("\u{1B}]0;title\u{07}a/b.c:1: error: x"), "a/b.c:1: error: x")
        XCTAssertEqual(BuildDiagnostic.stripANSI("plain\u{1B}"), "plain")
        XCTAssertEqual(BuildDiagnostic.stripANSI("no escapes here"), "no escapes here")
    }

    // MARK: - Last wins, because a scrollback holds the build's history

    func testTheLatestDiagnosticPerLocationWinsInFirstSeenOrder() {
        let history = [
            "/p/A.swift:10:1: error: first run, since fixed",
            "/p/B.swift:20:1: warning: still there",
            "not a diagnostic",
            "/p/A.swift:10:1: warning: second run, now only a warning",
        ]
        let all = BuildDiagnostic.parseAll(history)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.path, "/p/A.swift", "first-seen order is kept")
        XCTAssertEqual(all.first { $0.path == "/p/A.swift" }?.severity, .warning, "the LATEST line for a location wins")
        XCTAssertEqual(all.first { $0.path == "/p/A.swift" }?.message, "second run, now only a warning")
    }

    func testDifferentLinesOfOneFileAreSeparateLocations() {
        let all = BuildDiagnostic.parseAll(["/p/A.swift:1:1: error: a", "/p/A.swift:2:1: error: b"])
        XCTAssertEqual(all.map(\.line), [1, 2])
    }

    // MARK: - A note annotates; it is never the newer report

    func testANoteAfterAnErrorOnTheSameLineDoesNotReplaceIt() {
        let swiftc = [
            "/p/A.swift:10:5: error: cannot find 'x' in scope",
            "/p/A.swift:10:5: note: did you mean 'y'?",
        ]
        XCTAssertEqual(BuildDiagnostic.parseAll(swiftc).first?.severity, .error)
        XCTAssertEqual(BuildDiagnostic.parseAll(["/p/A.swift:3:1: warning: w", "/p/A.swift:3:1: note: n"]).first?.severity, .warning)
        XCTAssertEqual(BuildDiagnostic.parseAll(["/p/A.swift:4:1: note: alone"]).first?.severity, .note, "a note alone is kept")
        XCTAssertEqual(
            BuildDiagnostic.parseAll(["/p/A.swift:6:1: note: older", "/p/A.swift:6:1: note: newer"]).first?.message, "newer",
            "among notes the latest still wins")
        XCTAssertEqual(
            BuildDiagnostic.parseAll(["/p/A.swift:5:1: error: old", "/p/A.swift:5:1: warning: new"]).first?.severity, .warning,
            "a newer warning still replaces an older error")
    }

    // MARK: - Marks

    func testMarksResolvePathsAndTheMoreSeriousWinsOnAMergedLine() {
        let diagnostics = BuildDiagnostic.parseAll([
            "Sources/A.swift:7:1: warning: relative",
            "/repo/Sources/A.swift:7:1: error: absolute",
            "/repo/Sources/A.swift:9:1: note: n",
            "/gone/B.swift:1:1: error: a file that does not exist",
        ])
        let marks = BuildDiagnostic.marks(diagnostics) { raw in
            raw == "/gone/B.swift" ? nil : (raw.hasPrefix("/") ? raw : "/repo/" + raw)
        }
        XCTAssertEqual(marks["/repo/Sources/A.swift"]?[7], .error, "two spellings of one file merge; the error wins")
        XCTAssertEqual(marks["/repo/Sources/A.swift"]?[9], .note)
        XCTAssertNil(marks["/gone/B.swift"], "an unresolved path marks nothing")
        let reversed = BuildDiagnostic.marks(diagnostics.reversed()) { $0.hasPrefix("/") ? $0 : "/repo/" + $0 }
        XCTAssertEqual(reversed["/repo/Sources/A.swift"]?[7], .error, "whatever the order")
    }

    func testAPrintedPathResolvesAgainstTheCommandsDirectoryOrNotAtAll() {
        let real: Set<String> = ["/repo/Sources/A.swift", "/abs/B.swift"]
        let exists = { real.contains($0) }
        let cwd = URL(fileURLWithPath: "/repo")
        XCTAssertEqual(BuildDiagnostic.resolvedPath("Sources/A.swift", cwd: cwd, exists: exists), "/repo/Sources/A.swift")
        XCTAssertEqual(BuildDiagnostic.resolvedPath("./Sources/../Sources/A.swift", cwd: cwd, exists: exists), "/repo/Sources/A.swift")
        XCTAssertEqual(BuildDiagnostic.resolvedPath("/abs/B.swift", cwd: cwd, exists: exists), "/abs/B.swift")
        XCTAssertNil(BuildDiagnostic.resolvedPath("Missing.swift", cwd: cwd, exists: exists))
        XCTAssertNil(BuildDiagnostic.resolvedPath("Sources/A.swift", cwd: nil, exists: exists), "a relative path needs a directory")
    }
}
