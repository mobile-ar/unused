struct ProtocolDefinition: Sendable {
    let name: String
    var requirements: Set<MemberSignature> = []
    var inheritedTypes: Set<String> = []
    var isComplete = true
}
