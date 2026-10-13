struct UsageLocalScope {
    var bindings: [String: UsageLocalBinding] = [:]
    var genericTypeNames = Set<String>()
    var isClassContext: Bool? = nil
}
