import Foundation

/// Where the price list comes from: the copy inside the app
/// (`Resources/agent-prices.json`). Nothing is downloaded.
enum AgentPriceSource {

    static func bundled() -> AgentPriceList? {
        guard let url = Bundle.main.url(forResource: "agent-prices", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return AgentPriceList.decode(data)
    }
}
