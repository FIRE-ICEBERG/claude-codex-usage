import Foundation

/// Usage surge: flag the 5h window when usage is being added much faster than an hour ago.
///
/// Menubar-only (not mirrored to src/ or tray-go/, like Auto Wakeup). No network: it only keeps
/// the last ~2h of the 5h values each poll already fetches and compares two hourly buckets.
///
/// There is deliberately no window-reset detection. Only *increases* between consecutive samples
/// are summed, so Claude's clock-aligned drop to 0 and Codex's rolling decay both count as 0
/// instead of poisoning a bucket, and what was consumed before a reset still serves as the
/// "hour before" baseline.

struct UsageSample: Equatable {
    let at: Date
    let pct: Double   // 0-100
}

let spikeBucket: TimeInterval = 3600
/// This hour must add at least `spikeRatio` × the hour before...
let spikeRatio = 1.5
/// ...and at least this many %p, or a 2%p → 3%p blip would read as "+50%".
/// ponytail: fixed constants; add an env/UserDefaults knob only if real use proves them noisy.
let spikeFloor = 10.0
/// A longer gap since the last sample (restart, sleep) restarts the history, so hours of usage
/// cannot land in one pair and show up as a surge.
let spikeMaxGap: TimeInterval = 20 * 60

/// Append one poll. Keeps only what two buckets need.
func recordSample(_ samples: [UsageSample], pct: Double, now: Date = Date()) -> [UsageSample] {
    let new = UsageSample(at: now, pct: pct)
    guard let last = samples.last, now.timeIntervalSince(last.at) <= spikeMaxGap else { return [new] }
    let cutoff = now.addingTimeInterval(-(2 * spikeBucket + spikeMaxGap))
    return samples.filter { $0.at >= cutoff } + [new]
}

struct SpikeReading: Equatable {
    let thisHour: Double   // %p added in (now-1h, now]
    let lastHour: Double   // %p added in (now-2h, now-1h]
}

/// nil until the oldest sample is at least 2h old, i.e. the hour-before bucket is fully covered.
/// A pair's increase is credited to the bucket of its later sample.
func spikeReading(_ samples: [UsageSample], now: Date = Date()) -> SpikeReading? {
    guard let first = samples.first, now.timeIntervalSince(first.at) >= 2 * spikeBucket else { return nil }
    var thisHour = 0.0, lastHour = 0.0
    for (prev, cur) in zip(samples, samples.dropFirst()) {
        let gain = max(0, cur.pct - prev.pct)
        let age = now.timeIntervalSince(cur.at)
        if age < spikeBucket { thisHour += gain } else if age < 2 * spikeBucket { lastHour += gain }
    }
    return SpikeReading(thisHour: thisHour, lastHour: lastHour)
}

func isSpike(_ r: SpikeReading, ratio: Double = spikeRatio, floor: Double = spikeFloor) -> Bool {
    r.thisHour >= floor && r.thisHour >= r.lastHour * ratio
}

/// The reading only while it is a surge — what the render paths use.
func currentSpike(_ samples: [UsageSample], now: Date = Date()) -> SpikeReading? {
    guard let r = spikeReading(samples, now: now), isSpike(r) else { return nil }
    return r
}

/// Dropdown note. English only, per CLAUDE.md.
func spikeNote(_ r: SpikeReading) -> String {
    "⚠ 5h usage surge: +\(Int(r.thisHour.rounded()))% this hour, +\(Int(r.lastHour.rounded()))% the hour before"
}

/// Suffix on the menu-bar 5h number.
func spikeMark(_ r: SpikeReading?) -> String {
    r == nil ? "" : "▲"
}
