struct WitnessResolution: Sendable {
    var required: Set<DeclarationIdentity> = []
    var uncertain: Set<DeclarationIdentity> = []
    var typeConformances: [String: Set<String>] = [:]
    var warnings: [String] = []
}
