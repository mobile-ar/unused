struct SDKInterfaceAlias: Sendable {
    let name: String
    var referencedTypes: Set<String> = []
    var isComplete = true
}
