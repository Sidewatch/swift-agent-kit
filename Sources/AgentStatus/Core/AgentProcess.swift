//
//  AgentProcess.swift
//  AgentStatus
//
//  Naming the foreground program the way a user would, from argv (Zed's approach).
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Naming the foreground program the way a user would, from argv (Zed's approach).
public enum AgentProcess {
    /// The command a user would recognise, from argv: the basename of argv[0], and where that is
    /// a bare runtime, the first argument that looks like a program rather than a flag.
    /// `node /opt/homebrew/lib/node_modules/@openai/codex/cli.js` reads as "codex", not "node".
    public static func commandName(fromArgs args: String?) -> String? {
        guard let args, !args.isEmpty else { return nil }
        let parts = args.split(separator: " ").map(String.init)
        guard let first = parts.first else { return nil }
        let base = (first as NSString).lastPathComponent
        guard TerminalStatus.isGenericRuntime(base) else { return base.isEmpty ? nil : base }
        // A runtime names nothing. Use the script it was handed, minus its extension.
        let rest = Array(parts.dropFirst())
        var k = 0
        while k < rest.count {
            let arg = rest[k]
            // Inline code (`python3 -c …`, `node -e …`, `sh -c …`) is not a program: the runtime
            // is the honest name, not the first word of the snippet.
            if ["-c", "-e", "-p", "--eval", "--print"].contains(arg) { return base }
            // `python -m http.server`: the module is the program.
            if arg == "-m", k + 1 < rest.count { return rest[k + 1] }
            if arg.hasPrefix("-") { k += 1; continue }
            var name = (arg as NSString).lastPathComponent
            for ext in [".js", ".mjs", ".cjs", ".py", ".rb"] where name.hasSuffix(ext) {
                name = String(name.dropLast(ext.count))
            }
            // `cli`/`index`/`main` are the file, not the tool — the package directory above is.
            if ["cli", "index", "main", "bin", "run"].contains(name.lowercased()) {
                let dirs = arg.split(separator: "/").map(String.init)
                if dirs.count >= 2 { return dirs[dirs.count - 2] }
            }
            return name.isEmpty ? base : name
        }
        return base
    }
}
