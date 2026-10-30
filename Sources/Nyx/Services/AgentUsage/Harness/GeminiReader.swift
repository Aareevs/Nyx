import Foundation

/// Reads the per-reply payloads `AgentGeminiSessions` hands over. Gemini
/// counts the cached part inside `input`, and reports thinking tokens apart
/// from the answer; the island keeps cache traffic apart from input and
/// counts thinking inside the output.
struct GeminiReader: AgentHarnessReader {
    var provider: AgentProvider { .gemini }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard AgentLogParser.contains(line, #""gemini":true"#),
              let json = AgentLogParser.object(line) else { return [] }
        // Antigravity's step statuses say whether the agent is still working.
        if let phase = json["phase"] as? String {
            let date = AgentLogParser.timestamp(json["ts"]) ?? now
            if phase == "active" {
                let entry: AgentLogEntry = state.turnOpen ? .turnActive(date) : .turnBegan(date)
                state.turnOpen = true
                return [entry]
            }
            guard state.turnOpen else { return [] }
            state.turnOpen = false
            return [.turnEnded(date, completed: true, duration: nil)]
        }
        guard let id = json["id"] as? String, let counts = json["tokens"] as? [String: Any] else { return [] }
        func count(_ key: String) -> Int { (counts[key] as? NSNumber)?.intValue ?? 0 }
        let cached = min(count("cached"), count("input"))
        let thoughts = count("thoughts")
        let tokens = AgentTokens(input: count("input") - cached + count("tool"), cacheWrite: 0, cacheRead: cached,
                                 output: count("output") + thoughts, reasoning: thoughts)
        guard tokens.total > 0 else { return [] }
        let model = AgentLogParser.native(json["model"] as? String ?? "")
        let hash = json["project"] as? String ?? ""
        let project = json["projectName"] as? String ?? (hash.isEmpty ? "" : "gemini-" + hash.prefix(6))
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        let date = AgentLogParser.timestamp(json["ts"]) ?? now
        var entries: [AgentLogEntry] = [.usage(key: "gemini:" + id, record: AgentUsageRecord(
            provider: .gemini, date: AgentLogParser.timestamp(json["ts"]) ?? now, model: model, project: project,
            session: json["session"] as? String ?? "", tokens: tokens, cost: priced.cost, savings: priced.savings),
                       billable: billable)]
        // The live card names the model and project of the latest call.
        if state.turnOpen { entries.append(.turnContext(model: model, project: project)) }
        return entries
    }
}
