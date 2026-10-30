import Foundation

struct CPUCoreFeatureStrings {
    let title: String
    let coreFormat: String
    let hint: String
    let superCores: String
    let performanceCores: String
    let efficiencyCores: String
    let apps: String
    /// Settings switch for the per-core bars under CPU.
    let perCore: String
}

extension FeatureStrings {
    static func cpuCores(_ language: AppLanguage) -> CPUCoreFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension CPUCoreFeatureStrings {
    static let enUS = CPUCoreFeatureStrings(
        title: "Logical CPU cores",
        coreFormat: "Core %d",
        hint: "Each bar is one logical core. Its fill height shows utilization, not remaining performance.",
        superCores: "Super",
        performanceCores: "Performance",
        efficiencyCores: "Efficiency",
        apps: "Apps using CPU",
        perCore: "Per core"
    )











}
