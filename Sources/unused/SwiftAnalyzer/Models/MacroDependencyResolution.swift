struct MacroDependencyResolution: Sendable {
    var used: Set<DeclarationIdentity> = []
    var uncertain: Set<DeclarationIdentity> = []
    var warnings: [String] = []
}
