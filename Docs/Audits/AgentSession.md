# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift); line-by-line logic review was targeted at the areas changed since
5 Sep 2026, not the whole tree. Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Fixed: `ClockFormat.hhmm`: dropped a `nonisolated(unsafe)` the compiler reported as unnecessary (DateFormatter is Sendable now).
- Fixed: CLAUDE.md / AGENTS.md module map listed CodexAdapter, GeminiAdapter, OpenCodeAdapter — only `ClaudeCodeAdapter` (+ `Agents`) exists.

## Logic review — 18 Sep 2026 (every source and test file, line by line)

Fixed, each pinned by a test that fails against the old code:

- **The usage heatmap and streaks bucketed by UTC day.** `UsageRecord.day` was the timestamp's
  first ten characters — its UTC date — so for anyone west of UTC every evening's work landed on
  tomorrow's cell and `currentStreak` read 0 until the next day (`streaks` compares against a LOCAL
  "today"). The day and the peak hour now come from the parsed instant in the local calendar
  (`ISOTimestamp`, shared with the timeline's `HH:mm`); the raw-string reads remain as the
  fallback for a timestamp the parser rejects.
- **A CRLF edit had no usable anchor.** `editAnchor` split `new_string` on the Character `"\n"`,
  and `"\r\n"` is ONE Character in Swift, so a Windows-authored file's edit kept its whole
  inserted text as the anchor — which no single line contains — and Follow Agent fell back to the
  first hunk. `firstLine` (prompt and prose rows) and `BurnDetector.key`'s label had the same split.
  All three split on `isNewline` now.
- **Helpers left over from the removed adapters** (`SessionMemo`, `FileHead`, `Data.lenientUTF8String`,
  `Date(epochMilliseconds:)`, `JSONFile.lines(in:)`) had no caller outside their own tests since
  11 Sep 2026; removed with their tests. The module map gains the `Support/` line it never had.

Reviewed and sound: `TranscriptCache` (the stat fast path, pure-append detection by inode and size,
the line-aligned offset, the tentative parse of an unterminated tail into a COPY of the state, the
`pread` loop), `TranscriptState` (message-id dedupe across polls, the 300-event cap, `<`-prefixed
user content skipped, read-only tools never file edits), `TurnBoundary` (FNV ids, events before the
first prompt dropped), `BurnDetector` (prose skipped, prompts and edits end a run, bookkeeping
ignored), `ClaudeQuota.parse` and its microsecond dates, `ClaudeQuotaCache`'s throttle (a failed
refresh still stamps `lastFetch`, so failures cannot hammer the endpoint), `ClaudeSessionIndex`'s
per-UTF-16-unit fold and candidate encodings, `Agents.resolve`'s candidate order.

### Usage prices and plan limits, later on 18 Sep 2026

Two more fixes from comparing the dashboard with what Claude Code itself shows, each pinned by a test that
fails against the old code:

- **`ModelPricing` charged by family name only, and every family had moved.** The table was Opus 4.1 /
  Sonnet 4 / Haiku 3.5 list prices, applied by substring: `claude-opus-5` (the most-used model in the
  local transcripts) was charged $15/$75 where the published price is $5/$25 — three times over —
  while `claude-fable-5-1` fell to the Sonnet default, $3/$15 against $10/$50, and Sonnet 5 and
  Haiku 4.5 were off too. Rates now follow the generation read from the id (both id shapes, the 8-digit
  date ignored), from platform.claude.com/docs/en/about-claude/pricing as read that day; an id with no
  version keeps its family's older rates, which is also what keeps the fixture-based tests honest.
  Mutant: every Opus at the 4.1 rates → `ModelPricingTests` fails, nothing else.
- **`ClaudeQuota.parse` missed the Fable weekly cap and showed a codename bucket instead.** A live
  response (`--dump-quota`, 18 Sep 2026) carries the per-model cap ONLY in a new `limits` array
  (`kind: weekly_scoped`, `scope.model.display_name: "Fable"`, with a `severity`); the top-level
  `seven_day_opus` / `seven_day_sonnet` keys are null and there is no `seven_day_fable` at all. The
  shape-based sweep therefore rendered the 5-hour and weekly bars, an "Extra Usage" percentage and an
  internal feature bucket by its codename — the one bar the user was about to hit absent. The `limits`
  array is now the source of truth when present (keys `session`, `weekly_all`, `weekly_scoped:<Name>`;
  the legacy accessors read them), the older shape still parses when it is absent, `extra_usage` is
  never a limit row, `spend` / `extra_usage` become `Spend` (minor units, currency, exponent → "£12.34
  of £100.00"), and `seven_day_breakdown` becomes `weekShares`. Mutants: ignore `limits` → the
  limits test fails; drop the spend → the two spend tests fail; nothing else either way.
- **The Keychain read prompted on every launch, sometimes twice.** Claude Code writes its
  credential item with the `security` tool, which leaves the item's partition list at
  `apple-tool:` (read from the live keychain's ACL dump); a Security-framework read from the
  signed app is therefore asked for the login password, and the "Always Allow" grant is wiped when
  Claude Code rewrites the item at the next token refresh (`mdat` moved the same afternoon, the
  list stayed `apple-tool:` only). `ClaudeKeychain.accessToken` now reads through
  `/usr/bin/security find-generic-password -w` first — silent for that partition, killed after
  five seconds, fresh on every call so a refreshed token is used — and keeps the framework read as
  the fallback. `ClaudeKeychainTests` covers the tool's output shape and the missing-item case.
- **Two stats added, not fixed:** `UsageReport.longestSession` (a transcript's first message instant to
  its last — `UsageRecord.instant` is kept for it; a transcript with no timestamps still counts as a
  session but has no span) and `mostActiveDay` (the local day with the most tokens, the earliest on a
  tie). `UsageSessionStatsTests`; mutants shortest-for-longest and least-for-most fail only that test.

## Session lookup — 9 Oct 2026

Where a project's transcript is and which one is live, from bugs reviewers measured on this machine. Each
fix is pinned by a test that fails against the code before it (the mutant named), in a new file per topic.

Measured first, before changing anything (43 transcripts under `~/.claude/projects`, read for their `type`
and `cwd` fields only): every transcript's FIRST record is `type: mode` and carries no `cwd`; the first
record that carries one is the 4th–6th line (`user` ×37, `attachment` ×1; 5 transcripts have none in
their first 50 lines, sessions before their first prompt); in all 38 the per-UTF-16-unit fold of that `cwd`
equals the folder name. The rule adopted is therefore "the `cwd` of the first record that carries one",
not "the first record's `cwd`". No `-private-` or non-ASCII folder exists on this machine, so those setups
are synthetic, built from the documented rule.

- **A project under `/tmp`, `/var` or `/etc` was never found.** Claude Code folds the kernel's cwd,
  `/private/tmp/proj` → `-private-tmp-proj`; `encode` folded `standardizedFileURL.path`, which strips
  `/private` from an EXISTING path (keeps it for a nonexistent one, which is why the existing tests, all
  on nonexistent `/private/tmp/…` roots, passed). Gemini's registry and Grok's bucket were keyed by the
  cwd those agents saw and compared with the standardized path. Now `PathForms.of` gives every spelling
  (as given, standardized, symlinks resolved, each with `/private` restored), `candidateEncodings` folds
  each one as-is, NFC and NFD, and `ClaudeSessionLocator` reads EVERY existing candidate folder;
  Codex, Gemini and Grok try every spelling. Pinned by `ProjectDirectoryFormsTests` (a real folder under
  `/tmp`, a symlink, Codex/Gemini/Grok equivalents). Mutants: no `/private` restore → 4 tests fail; no
  symlink resolution → 2 fail.
- **An accented folder.** Foundation keeps a decomposed path decomposed (`URL(fileURLWithPath:)
  .standardizedFileURL.path`, measured), so `Café` asked for as `Cafe\u{301}` folded to `Cafe-` and the
  folder `Caf-` was missed. `candidateEncodings` folded three ways already but only `encode` was used.
  Pinned by `testAnAccentedFolderIsFoundFromEitherUnicodeForm`. Mutant: fold one form only → fails.
- **Two sessions in one folder flipped the reader every poll.** `latestSession` was the newest mtime,
  so with two agents writing, each poll chose whichever wrote last, and the root-keyed `TranscriptCache`
  saw every flip as a rotation: a full re-parse of a 40–110 MB transcript per poll. `SessionChoice` keeps
  the chosen file while it is being written (its mtime advanced since the previous poll, or lies within
  30 s) and lets a newer one take over once it has gone quiet; all four adapters use it, and the hit
  carries the chosen transcript (`Agents.Hit.session`) so a host keys per-session state by it. Pinned by
  `StableSessionChoiceTests` (alternating writes never flip; a quiet file yields once and the switch does
  not reverse). Mutants: always the newest → 3 fail; no "advanced since the previous poll" rule → 1 fails.
  Found on the way: a `URL` instance caches its resource values, so the held file's `modificationDate`
  read through the same instance was stale and a growing file looked quiet — `SessionChoice` stats
  through `FileStat` and answers a fresh `URL`.
- **The cache is keyed by transcript path**, with the six least recently served kept, so a flip or a
  `--resume` of another session is not a rotation of the first file's state, and switching back costs a
  `stat`; a rewrite of the same file (new inode) still re-parses. Pinned by `TranscriptCacheByPathTests`.
  Mutants: one entry at a time → 2 fail; no eviction → 1 fails.
- **A session launched in a subfolder of the opened project was never found** (a Terminal.app agent in
  `R/worker` while `R` is open): matching was exact. `Agents.resolve` now has a second tier: when no
  candidate matches, `latestSessionRoot(under:)` looks for folders named `encode(project) + "-"` (every
  spelling), confirms each transcript by its launch `cwd` lying beneath the project, and returns the
  launch directory as the hit's `root`, so every other reader works unchanged. Searched beneath is
  `under:` or, unnamed, the FIRST candidate — never a later one, because the opened folder's parent holds
  other projects (the host's list is terminal cwds, opened folder, repo root, parent). The same `cwd`
  check tells a colliding folder apart on an exact match (`/a/b.c` and `/a/b-c` share one folder; a
  transcript with no `cwd` yet is accepted there and rejected beneath). Codex has the tier too (its index
  is cwd-keyed); Gemini and Grok keep the protocol default (nil): their registry and bucket names would
  have to be enumerated for prefixes, which no reviewer asked for. Pinned by `SubfolderSessionTests`.
  Mutants: no second tier → 3 fail; search beneath the last candidate → 1 fails; no `cwd` check on an
  exact match → 1 fails; descendant accepted without the `cwd` check → 1 fails; Codex by equality → 1 fails.
- **Misses are remembered for 2 s** (`LookupMisses`, one per index): an idle poll with no session listed
  Claude 1, Codex 4 (sessions, year, month, day), Gemini 2 (slug and legacy hash folders), Grok 1
  directories per candidate — 8, and the host polls 4 candidates from 4 timers every 2 s: 128 listings
  per 2 s, now at most 32 (each candidate once per adapter per interval). A hit is never remembered and
  clears the miss. Pinned by `LookupMissMemoTests` (listing counts do not grow across two immediate
  calls, for all four adapters). Mutant: a miss never fresh → 2 fail.
- **A transcript before its first prompt** (a `mode` record only) already resolved as a session with no
  turns; now pinned by `EmptySessionTests`, because the new `cwd` check could have broken it. Mutant: a
  transcript with no `cwd` is not this root's → it and the four `AgentsResolveTests` fail.
- **Vocabulary pins** (`TranscriptVocabularyTests`): the field is `cwd`, top-level, on the first record
  that carries one, not remembered while absent; the folder is the kernel path folded per UTF-16 unit
  (`Tëst_Prøjéct 2.0` → `T-st-Pr-j-ct-2-0`, an emoji → two dashes, an existing `/tmp` path keeps
  `/private`). Mutants: another field name → 4 fail; the last `cwd` → 1 fails; fold per scalar → 1 fails.

API: `Agents.resolve(candidates:preferring:under:)` returns `Agents.Hit` = `(adapter, root, session)` —
source-compatible with `hit.adapter` / `hit.root`; `AgentAdapter.latestSessionRoot(under:)` is a new
requirement with a default of nil; `latestSession(for:)` is documented stable. `Files` became
`DirectoryReader` (listings counted); `ClaudeCodeAdapter.projectDir(for:)` became
`projectDirectories(for:)`. Build clean under Swift 6, `swift format lint --strict` silent, 172 tests.

A host follow-up, outside this package: pass the opened folder as `under:`; with no terminal running an
agent the default (first candidate) is already the opened folder.

### Known non-issue added

- `contentsOfDirectory(at:)` returns `/private/var/…` for a folder created as `/var/…`; a test compares
  `canonicalPath` (`Tests/AgentSessionTests/URL+CanonicalPath.swift`), never `path`.

## Known non-issues (do not "fix" these again)

- `TurnBoundary.id` collapses two turns opened by the same text within one clock minute — documented on
  the property; fixing it means a full-precision timestamp on `TimelineEvent`.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review (every source and test file, line by line), Claude with David.
- 18 Sep 2026 — `ModelPricing` by generation from the published page; `ClaudeQuota` reads the `limits` array,
  `spend` and `seven_day_breakdown` (see "Usage prices and plan limits" above).
- 18 Sep 2026 — `UsageReport.longestSession` / `mostActiveDay`.
- 18 Sep 2026 — `ClaudeKeychain` reads through the `security` tool first (no prompt); framework read as fallback.
- 22 Sep 2026 — `TurnEffort` and `TurnBoundary.effort(in:)` / `plan(in:)` moved in from Sidewatch's `AgentTurnNode` (the outline row keeps only its drawing); `TurnEffortTests`. AGENTS.md re-mirrored from CLAUDE.md (it had drifted: Extensions, Monitoring and ClaudeQuota+Display were missing).
- 24 Sep 2026 — `PersistedOutput` (`Support/`): a `<persisted-output>` tool result is read back from its `tool-results/` file's tail, so a test runner's summary survives the spill (`PersistedOutputTests`, four tests, one through the parser). The plan (`TimelineEvent.todos`, `TurnBoundary.plan(in:)`, `AgentSummary.todos`) is REMOVED: Claude Code 2.1.233 / 2.1.268 stopped offering TodoWrite and the task tools on Opus 4.8, Sonnet 5, Fable 5 and newer, and 0 of 368 transcripts on David's machine carry one.
- 9 Oct 2026 — session lookup: every candidate folder (`/private`, symlinks, NFC/NFD), the chosen transcript held while written, path-keyed cache, subfolder search, misses remembered 2 s (see "Session lookup").
- 9 Oct 2026 — security review: `TranscriptCache.lineCap` (4 MB). The cache read a whole appended range and parsed every line of it, so one line another program wrote could hold the poll's memory and time hostage. A complete line over the cap is skipped unparsed; an unterminated tail over the cap is consumed and the entry remembers it is inside an oversized line, dropping bytes up to the next line feed on later polls — every byte is read exactly once and nothing re-read. `TranscriptCacheOversizedLineTests` (two tests, synthetic 4 MB lines). Mutant: lines ingested regardless of size and the tail never skipped — 6 failures (the giant parsed, the tail re-read, 8.4 MB read for a 4.2 MB file).
- 20 Oct 2026 — plan limits and the usage dashboard REMOVED. `ClaudeKeychain`, `ClaudeCredentials`, `ClaudeQuota` (+Display), `ClaudeQuotaCache`, `ClaudeUsageEndpoint`, `UsageAggregator`, `UsageTotals`, `UsageRecord` and `UsageReport` are gone with their tests, and so is the ProcessRunner dependency. The quota came from an undocumented endpoint for whichever account was logged in, and the aggregate read every transcript on the Mac, which no account owns: with two Claude accounts on one machine the dashboard mixed them. Per-session context, tokens and cost (`AgentUsage`, `ModelPricing`) stay.
