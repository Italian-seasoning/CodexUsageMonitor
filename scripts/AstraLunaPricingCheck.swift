import Foundation

// Run with the same Shared sources used by CodexUsageReaderCheck.
@main
struct AstraLunaPricingCheck {
    static func main() {
        let short = TokenUsage(input: 100_000, cachedInput: 50_000, output: 10_000, reasoningOutput: 0, total: 110_000)
        let long = TokenUsage(input: 300_000, cachedInput: 100_000, output: 10_000, reasoningOutput: 0, total: 310_000)
        for (model, shortCost, longCost) in [("gpt-6-astra", 1.05, 4.95), ("gpt-5.6-luna", 0.023, 0.102)] {
            guard let price = ModelPricingCatalog.pricing(for: model) else { fatalError("Missing price: \(model)") }
            precondition(abs(price.estimatedCost(for: short) - shortCost) < 0.000_001)
            precondition(abs(price.estimatedCost(for: long) - longCost) < 0.000_001)
            precondition(ModelPricingCatalog.pricing(for: model + "-2026-09-06") == price)
        }
        precondition(ModelPricingCatalog.pricing(for: "gpt-6-unknown") == nil)
        print("Astra/Luna pricing checks passed")
    }
}
