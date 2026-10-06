struct DeclarationReference: Hashable, Sendable {
    let name: String
    let parentType: String?
    let file: String
    let line: Int
    var column: Int = 1
    var kind: String = "declaration"
    var signature: String? = nil

    var displayName: String {
        let label = signature ?? name
        return parentType.map { "\($0).\(label)" } ?? label
    }
}
