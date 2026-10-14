import Foundation

/// Estimated cost of the local token statistics, at **API list prices** — menubar-only, like the
/// Codex provider. Neither usage API reports money, and a subscription bill is flat, so this is
/// "what these tokens would cost on the pay-as-you-go API", not what the user is charged.
///
/// Prices are $ per million tokens and hard-coded; update the tables when prices change. A model
/// missing here is "unpriced": its tokens are counted in `DayCost.unpriced` and the displayed
/// amount gets a trailing `+` (a lower bound), never a guess.
struct ModelPrice: Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite5m: Double
    let cacheWrite1h: Double

    /// Anthropic's standard multipliers: cache read 0.1×, 5-minute write 1.25×, 1-hour write 2×.
    init(input: Double, output: Double, cacheRead: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead ?? input * 0.1
        self.cacheWrite5m = input * 1.25
        self.cacheWrite1h = input * 2
    }
}

/// Claude API list prices (2026-10).
private let claudePrices: [String: ModelPrice] = [
    "claude-fable-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
    "claude-mythos-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
    "claude-fable-5": ModelPrice(input: 10, output: 50),
    "claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheRead: 0.20),
    "claude-opus-5": ModelPrice(input: 5, output: 25),
    "claude-opus-4-8": ModelPrice(input: 5, output: 25),
    "claude-opus-4-7": ModelPrice(input: 5, output: 25),
    "claude-opus-4-6": ModelPrice(input: 5, output: 25),
    "claude-opus-4-5": ModelPrice(input: 5, output: 25),
    "claude-sonnet-5-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
    "claude-sonnet-5": ModelPrice(input: 2, output: 10),
    "claude-sonnet-4-6": ModelPrice(input: 3, output: 15),
    "claude-sonnet-4-5": ModelPrice(input: 3, output: 15),
    "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50),
    "claude-haiku-4-5": ModelPrice(input: 1, output: 5),
]

/// OpenAI API list prices for the Codex models (2026-10, standard short-context tier). Codex
/// reports a separate `cache_write_input_tokens`, priced at the same 1.25× of input.
private let codexPrices: [String: ModelPrice] = [
    "gpt-6.1-sol": ModelPrice(input: 2, output: 10, cacheRead: 0.10),
    "gpt-6-astra": ModelPrice(input: 10, output: 50, cacheRead: 1),
    "gpt-6-luna": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01),
    "gpt-5.6-sol": ModelPrice(input: 5, output: 30, cacheRead: 0.50),
    "gpt-5.6-terra": ModelPrice(input: 2, output: 12, cacheRead: 0.20),
    "gpt-5.6-luna": ModelPrice(input: 0.20, output: 1.20, cacheRead: 0.02),
]

/// `claude-opus-4-5-20251101` → `claude-opus-4-5`: dated snapshots share the alias' price.
private func stripDateSuffix(_ model: String) -> String {
    guard let range = model.range(of: #"-\d{8}$"#, options: .regularExpression) else { return model }
    return String(model[..<range.lowerBound])
}

/// The price of a Claude or Codex model id; nil when unknown (aliases like `opus`, `<synthetic>`).
func modelPrice(_ model: String) -> ModelPrice? {
    let id = stripDateSuffix(model.lowercased())
    return claudePrices[id] ?? codexPrices[id]
}

/// One day's estimated cost for one provider. Like token totals, a ledger day keeps the
/// per-field MAX ever observed (see `TokenHistory.swift`).
struct DayCost: Equatable, Codable {
    var usd: Double = 0
    /// Tokens of models without a known price (not included in `usd`).
    var unpriced: Int = 0

    static func + (a: DayCost, b: DayCost) -> DayCost {
        DayCost(usd: a.usd + b.usd, unpriced: a.unpriced + b.unpriced)
    }

    static func max(_ a: DayCost, _ b: DayCost) -> DayCost {
        DayCost(usd: Swift.max(a.usd, b.usd), unpriced: Swift.max(a.unpriced, b.unpriced))
    }
}

typealias DailyCost = [String: DayCost]

/// The cost of one response. `cacheWrite1h` is the part of `t.cacheCreate` written with a 1-hour
/// TTL (the rest is priced as 5-minute writes). `multiplier` covers premium modes (fast = 2×).
func responseCost(_ t: TokenTotals, model: String?, cacheWrite1h: Int = 0, multiplier: Double = 1) -> DayCost {
    guard let model, let p = modelPrice(model) else { return DayCost(usd: 0, unpriced: t.total) }
    let write1h = min(Swift.max(0, cacheWrite1h), t.cacheCreate)
    let dollars = Double(t.input) * p.input + Double(t.output) * p.output
        + Double(t.cacheRead) * p.cacheRead
        + Double(t.cacheCreate - write1h) * p.cacheWrite5m + Double(write1h) * p.cacheWrite1h
    return DayCost(usd: dollars / 1_000_000 * multiplier, unpriced: 0)
}

/// "≈$0.42" / "≈$12.34" / "≈$1,234"; a trailing "+" when some tokens could not be priced.
func formatUSD(_ c: DayCost) -> String {
    let text: String
    if c.usd < 100 {
        text = String(format: "%.2f", c.usd)
    } else {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        text = f.string(from: NSNumber(value: c.usd.rounded())) ?? String(format: "%.0f", c.usd)
    }
    return "≈$\(text)\(c.unpriced > 0 ? "+" : "")"
}
