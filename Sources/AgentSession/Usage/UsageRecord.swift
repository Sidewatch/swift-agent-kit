//
//  UsageRecord.swift
//  AgentSession
//
//  One usage-bearing transcript line: the model, the four token counts and when.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One usage-bearing transcript line: the model, the four token counts and when.
struct UsageRecord {
    /// The API response id (`message.id`, else `requestId`), for counting a response once.
    let id: String?
    /// The model id, or `"unknown"` for a synthetic or missing one.
    let model: String
    /// The local calendar day, `yyyy-MM-dd`.
    let day: String
    /// The local hour, 0–23, when the timestamp gives one.
    let localHour: Int?
    /// The message's instant, when its timestamp parsed — what session lengths are measured from.
    let instant: Date?
    /// Token counts by kind: fresh input, cache writes, cache reads, output.
    let input: Int, cacheWrite: Int, cacheRead: Int, output: Int

    /// Every token the line reported.
    var tokens: Int { input + cacheWrite + cacheRead + output }
    /// Estimated USD cost at list prices (``ModelPricing``).
    var cost: Double { ModelPricing.cost(model: model, input: input, cacheWrite: cacheWrite, cacheRead: cacheRead, output: output) }

    /// Nil unless the line is a JSON object carrying `message.usage`.
    init?(line: Data) {
        guard let obj = JSONFile.object(from: line),
            let msg = obj["message"] as? [String: Any],
            let usage = msg["usage"] as? [String: Any]
        else { return nil }
        id = (msg["id"] as? String) ?? (obj["requestId"] as? String)
        model = (msg["model"] as? String).flatMap { $0.isEmpty || $0 == "<synthetic>" ? nil : $0 } ?? "unknown"
        // The LOCAL calendar day and hour. Must not be the timestamp's first ten characters
        // (its UTC date): west of UTC, evening work would land on tomorrow's heatmap cell.
        // The raw-string fallbacks cover a timestamp the parser rejects.
        let ts = obj["timestamp"] as? String
        let instant = ts.flatMap(ISOTimestamp.date)
        self.instant = instant
        day = instant.map(UsageAggregator.dayString) ?? ts.map { String($0.prefix(10)) } ?? ""
        localHour = instant.map { Calendar.current.component(.hour, from: $0) } ?? ts.flatMap(UsageRecord.localHour(fromISO:))
        input = usage["input_tokens"] as? Int ?? 0
        cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
        cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        output = usage["output_tokens"] as? Int ?? 0
    }

    /// The local hour of an ISO timestamp the parser rejected, from its UTC hour (chars 11–12)
    /// and the current offset — the fallback behind the parsed instant above.
    static func localHour(fromISO ts: String) -> Int? {
        guard ts.count >= 13, let utcHour = Int(ts.dropFirst(11).prefix(2)) else { return nil }
        let offset = TimeZone.current.secondsFromGMT() / 3600
        return ((utcHour + offset) % 24 + 24) % 24
    }
}
